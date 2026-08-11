import 'dart:io';

import 'package:adapter_sdk/adapter_sdk.dart';
import 'package:assurance_ir/assurance_ir.dart';
import 'package:dart_frog_gen/dart_frog_gen.dart';
import 'package:path/path.dart' as path;

/// Compatibility identity for the public Dart Frog route configuration API.
const dartFrogCompatibilityId = 'dart-frog-gen-2-route-topology-v1';

final class DartFrogAdapter implements FrameworkAdapter {
  const DartFrogAdapter();

  @override
  String get id => 'dart-frog';

  @override
  String get compatibilityId => dartFrogCompatibilityId;

  @override
  Future<AdapterOutputV2> extract(AdapterRequest request) async {
    final diagnostics = <DiagnosticV2>[];
    final nodes = <TopologyNode>[];
    RouteConfiguration? configuration;
    try {
      configuration = buildRouteConfiguration(Directory(request.packageRoot));
    } catch (error) {
      diagnostics.add(_error(
        'ZK-DART-FROG-001',
        'Unable to build Dart Frog route configuration: $error',
      ));
      return AdapterOutputV2(
        targetId: request.targetId,
        packageId: request.packageId,
        sourceAdapter: id,
        compatibilityId: compatibilityId,
        completeness: const AdapterCompletenessV2(
          routeRegistration: CompletenessStatus.incomplete,
          middlewareOrder: CompletenessStatus.incomplete,
          dynamicRegistration: CompletenessStatus.incomplete,
          externalVisibility: CompletenessStatus.incomplete,
        ),
        nodes: const [],
        diagnostics: diagnostics,
      );
    }

    final endpointEntries = configuration.endpoints.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    var routeComplete = configuration.rogueRoutes.isEmpty;
    for (final entry in endpointEntries) {
      final routeFiles = entry.value;
      if (routeFiles.length != 1) {
        routeComplete = false;
        diagnostics.add(_error(
          'ZK-DART-FROG-002',
          'Conflicting Dart Frog route registration for ${entry.key}',
        ));
      }
      for (final routeFile in routeFiles) {
        final sourcePath = _sourcePath(request.packageRoot, routeFile.path);
        final source = File(sourcePath);
        if (!source.existsSync()) {
          routeComplete = false;
          diagnostics.add(_error(
            'ZK-DART-FROG-003',
            'Dart Frog route handler could not be resolved: ${routeFile.path}',
          ));
        }
        final contents = source.existsSync() ? source.readAsStringSync() : '';
        final isWebSocket = RegExp(r'\bwebSocketHandler\s*\(').hasMatch(contents);
        final nodeId = _nodeId(request, 'route', entry.key);
        nodes.add(TopologyNode(
          id: nodeId,
          kind: isWebSocket ? 'websocket-route' : 'route',
          name: routeFile.name,
          path: routeFile.path,
          attributes: {
            'route': entry.key,
            'parameters': routeFile.params,
            'wildcard': routeFile.wildcard,
            'alias': routeFile.name,
            'handlerResolved': source.existsSync(),
          },
        ));
        nodes.add(TopologyNode(
          id: _nodeId(
            request,
            'route-alias',
            '${entry.key}|${routeFile.path}',
          ),
          kind: 'route-alias',
          name: routeFile.name,
          path: routeFile.path,
          attributes: {'route': entry.key, 'target': nodeId},
        ));
      }
    }
    if (configuration.rogueRoutes.isNotEmpty) {
      routeComplete = false;
      for (final route in configuration.rogueRoutes) {
        diagnostics.add(_error(
          'ZK-DART-FROG-004',
          'Rogue Dart Frog route is not part of the generated topology: ${route.path}',
        ));
      }
    }

    final middlewareResult = _extractMiddleware(request, configuration, nodes);
    diagnostics.addAll(middlewareResult.diagnostics);
    final customEntrypoint = configuration.invokeCustomEntrypoint ||
        configuration.invokeCustomInit;
    return AdapterOutputV2(
      targetId: request.targetId,
      packageId: request.packageId,
      sourceAdapter: id,
      compatibilityId: compatibilityId,
      completeness: AdapterCompletenessV2(
        routeRegistration: routeComplete
            ? CompletenessStatus.complete
            : CompletenessStatus.incomplete,
        middlewareOrder: middlewareResult.complete
            ? CompletenessStatus.complete
            : CompletenessStatus.indeterminate,
        dynamicRegistration: customEntrypoint
            ? CompletenessStatus.indeterminate
            : CompletenessStatus.complete,
        externalVisibility: customEntrypoint
            ? CompletenessStatus.indeterminate
            : CompletenessStatus.complete,
        // The adapter proves topology, not conditional failure or logging
        // branches inside application middleware.
        failureFlow: CompletenessStatus.indeterminate,
        logFlow: CompletenessStatus.indeterminate,
      ),
      nodes: nodes,
      diagnostics: diagnostics,
    );
  }

  _MiddlewareResult _extractMiddleware(
    AdapterRequest request,
    RouteConfiguration configuration,
    List<TopologyNode> nodes,
  ) {
    final diagnostics = <DiagnosticV2>[];
    final files = <String>{};
    final global = configuration.globalMiddleware;
    if (global != null) files.add(_sourcePath(request.packageRoot, global.path));
    for (final middleware in configuration.middleware) {
      files.add(_sourcePath(request.packageRoot, middleware.path));
    }
    var complete = true;
    for (final filePath in files) {
      final file = File(filePath);
      if (!file.existsSync()) {
        complete = false;
        diagnostics.add(_error(
          'ZK-DART-FROG-005',
          'Dart Frog middleware file could not be resolved: $filePath',
        ));
        continue;
      }
      final source = file.readAsStringSync();
      final useCalls = RegExp(r'\.use\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(')
          .allMatches(source)
          .map((match) => match.group(1)!)
          .toList()
          .reversed
          .toList();
      if (useCalls.isEmpty && source.contains('.use(')) {
        complete = false;
        diagnostics.add(_error(
          'ZK-DART-FROG-006',
          'Dart Frog middleware chain contains an unresolved use call: $filePath',
        ));
      }
      for (var index = 0; index < useCalls.length; index++) {
        final middlewareName = useCalls[index];
        nodes.add(TopologyNode(
          id: _nodeId(
            request,
            'middleware',
            '${path.relative(filePath, from: request.packageRoot)}|$middlewareName',
          ),
          kind: 'middleware',
          name: middlewareName,
          path: path.relative(filePath, from: request.packageRoot),
          attributes: {'incomingOrder': index, 'chainResolved': true},
        ));
      }
    }
    return _MiddlewareResult(complete: complete, diagnostics: diagnostics);
  }

  String _sourcePath(String packageRoot, String generatedPath) {
    final normalized = generatedPath.replaceAll('\\', '/');
    // dart_frog_gen computes paths relative to its own process directory.
    // That can produce ../../<package>/routes/... when Zuke is invoked from a
    // workspace different from the consumer. The final routes/ segment is
    // the stable framework boundary; resolve it against the declared package
    // root instead of trusting the generator's process-relative prefix.
    final marker = '/routes/';
    final index = normalized.lastIndexOf(marker);
    if (index != -1) {
      return path.join(
        packageRoot,
        'routes',
        normalized.substring(index + marker.length),
      );
    }
    if (normalized.startsWith('routes/')) {
      return path.join(packageRoot, normalized);
    }
    return path.normalize(path.join(packageRoot, normalized));
  }

  String _nodeId(AdapterRequest request, String kind, String name) =>
      '${request.targetId}/${request.packageId}/$kind/$name';

  DiagnosticV2 _error(String code, String message) => DiagnosticV2(
        code: code,
        stage: 'extract',
        severity: DiagnosticSeverity.error,
        owner: DiagnosticOwner.zuke,
        message: message,
        remediation: 'Resolve the Dart Frog topology or mark the dimension indeterminate.',
      );
}

final class _MiddlewareResult {
  final bool complete;
  final List<DiagnosticV2> diagnostics;

  const _MiddlewareResult({required this.complete, required this.diagnostics});
}
