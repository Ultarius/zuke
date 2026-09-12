import 'dart:io';

import 'package:args/args.dart';
import 'package:yaml/yaml.dart';
import 'package:zuke_core/zuke_core.dart';

import 'command_result.dart';
import 'configuration_preflight.dart';
import 'extraction_service.dart';

const _httpMethods = {
  'get',
  'post',
  'put',
  'patch',
  'delete',
  'head',
  'options',
  'trace',
};

/// Compares the parsed OpenAPI path/method surface with extracted route
/// topology. It deliberately does not claim response-schema or authorization
/// verification; those require separate contract and runtime evidence.
final class OpenApiContractReport {
  const OpenApiContractReport({
    required this.openapiOperations,
    required this.topologyOperations,
    required this.missing,
    required this.extra,
    required this.unknownMethodTopology,
  });

  final Set<String> openapiOperations;
  final Set<String> topologyOperations;
  final Set<String> missing;
  final Set<String> extra;
  final Set<String> unknownMethodTopology;

  bool get passed =>
      missing.isEmpty && extra.isEmpty && unknownMethodTopology.isEmpty;

  Map<String, Object?> toJson() => {
    'openapiOperations': _sorted(openapiOperations),
    'topologyOperations': _sorted(topologyOperations),
    'missing': _sorted(missing),
    'extra': _sorted(extra),
    'unknownMethodTopology': _sorted(unknownMethodTopology),
    'methodCompleteness': unknownMethodTopology.isEmpty,
    'schemaAndAuthorizationChecked': false,
  };
}

final class OpenApiContractVerifier {
  const OpenApiContractVerifier();

  Future<OpenApiContractReport> verify({
    required Directory root,
    required File openApi,
    String? targetId,
  }) async {
    final document = loadYaml(openApi.readAsStringSync());
    if (document is! Map) {
      throw const FormatException('OpenAPI document must contain a mapping');
    }
    final paths = document['paths'];
    if (paths is! Map) {
      throw const FormatException(
        'OpenAPI document is missing a paths mapping',
      );
    }
    final openapi = <String>{};
    for (final entry in paths.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      final path = _normalizePath(entry.key as String);
      for (final method in (entry.value as Map).keys) {
        if (method is String && _httpMethods.contains(method.toLowerCase())) {
          openapi.add('${method.toUpperCase()} $path');
        }
      }
    }
    final workspace = requireCurrentWorkspace(root.path);
    final extraction = await ExtractionService().extract(
      workspace,
      includeEvidence: false,
      targetId: targetId,
      topologyOnly: true,
    );
    final topology = <String>{};
    final unknown = <String>{};
    for (final output in extraction.topologyOutputs) {
      if (targetId != null && output.targetId != targetId) continue;
      for (final node in output.nodes) {
        // Compare HTTP routes and the adapter's explicit WebSocket handshake
        // methods. WebSocket messages still need separate contract evidence.
        if (node.kind != 'route' && node.kind != 'websocket-route') continue;
        final path = node.attributes['route'];
        if (path is! String || path.isEmpty) continue;
        final methods = node.kind == 'websocket-route'
            ? node.attributes['httpUpgradeMethods']
            : node.attributes['methods'];
        if (methods is List && methods.whereType<String>().isNotEmpty) {
          for (final method in methods.whereType<String>()) {
            topology.add('${method.toUpperCase()} ${_normalizePath(path)}');
          }
        } else {
          // A Dart Frog route file may serve more than one HTTP method. Never
          // invent GET: an adapter must extract the method set or the
          // report retains explicit method incompleteness.
          unknown.add(_normalizePath(path));
        }
      }
    }
    final unknownPaths = unknown.toSet();
    final missing = <String>{
      for (final operation in openapi)
        if (!topology.contains(operation) &&
            !unknownPaths.contains(
              operation.substring(operation.indexOf(' ') + 1),
            ))
          operation,
    };
    final extra = <String>{
      for (final operation in topology)
        if (!openapi.contains(operation)) operation,
    };
    return OpenApiContractReport(
      openapiOperations: openapi,
      topologyOperations: topology,
      missing: missing,
      extra: extra,
      unknownMethodTopology: unknown,
    );
  }
}

final class OpenApiContractCommand {
  const OpenApiContractCommand(this.args);

  final ArgResults args;

  Future<int> execute() async {
    if (!(args['openapi'] as bool? ?? false)) {
      throw const FormatException(
        'contract verify currently requires --openapi',
      );
    }
    final root = Directory(args['root'] as String? ?? Directory.current.path);
    final input = args['input'] as String? ?? 'docs/openapi.yaml';
    final file = File(
      input.startsWith(Platform.pathSeparator) ||
              RegExp(r'^[A-Za-z]:[\\/]').hasMatch(input)
          ? input
          : '${root.path}${Platform.pathSeparator}${input.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!file.existsSync()) {
      throw FormatException('OpenAPI document does not exist: ${file.path}');
    }
    final report = await const OpenApiContractVerifier().verify(
      root: root,
      openApi: file,
      targetId: args['target'] as String?,
    );
    final diagnostics = <Diagnostic>[
      for (final path in report.missing)
        Diagnostic(
          code: 'ZK-CONTRACT-OPENAPI-MISSING',
          stage: 'contract',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.project,
          message:
              'OpenAPI operation is not present in extracted topology: $path',
          remediation: 'Add the route or remove the stale OpenAPI operation.',
        ),
      for (final path in report.extra)
        Diagnostic(
          code: 'ZK-CONTRACT-OPENAPI-EXTRA',
          stage: 'contract',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.project,
          message:
              'Extracted route operation is not documented in OpenAPI: $path',
          remediation: 'Document the route or remove the unintentional route.',
        ),
      for (final path in report.unknownMethodTopology)
        Diagnostic(
          code: 'ZK-CONTRACT-OPENAPI-METHOD-UNKNOWN',
          stage: 'contract',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.project,
          message:
              'HTTP method could not be extracted for route topology: $path',
          remediation:
              'Teach the route adapter to extract methods or declare the route method set; path parity is reported separately.',
        ),
    ];
    final result = CommandResult(
      command: 'contract verify',
      stage: 'contract',
      exitCode: report.passed ? 0 : 1,
      status: report.passed ? CommandStatus.passed : CommandStatus.failed,
      eligible: report.passed,
      diagnostics: diagnostics,
      details: {
        'root': root.path,
        'openapi': file.path,
        'topology': report.toJson(),
      },
    );
    final encoded = encodeCommandResult(result);
    if ((args['format'] as String? ?? 'text') == 'json') {
      stdout.write(encoded);
    } else {
      stdout.writeln(
        report.passed
            ? 'OpenAPI route topology is aligned.'
            : 'OpenAPI route topology is not aligned.',
      );
      if (report.unknownMethodTopology.isNotEmpty) {
        stdout.writeln(
          'HTTP methods were not inferred for ${report.unknownMethodTopology.length} route(s).',
        );
      }
    }
    writeCommandSummaryBytes(args['summary-file'] as String?, encoded);
    return result.exitCode;
  }
}

String _normalizePath(String value) {
  var path = value.replaceAll('\\', '/');
  path = path.replaceAll(RegExp(r'\{[^}/]+\}'), ':param');
  path = path.replaceAll(RegExp(r'\[[^]/]+\]'), ':param');
  path = path.replaceAll(RegExp(r'<[^>/]+>'), ':param');
  if (!path.startsWith('/')) path = '/$path';
  path = path.replaceAll(RegExp(r'/+'), '/');
  if (path.length > 1) path = path.replaceFirst(RegExp(r'/$'), '');
  return path;
}

List<String> _sorted(Iterable<String> values) => [...values]..sort();
