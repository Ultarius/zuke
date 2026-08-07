import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

class WorkspaceExtraction {
  final List<AdapterOutput> outputs;
  final List<EvidenceRecord> evidenceRecords;
  final List<String> errors;

  const WorkspaceExtraction({
    this.outputs = const [],
    this.evidenceRecords = const [],
    this.errors = const [],
  });
}

class ExtractionService {
  CompletenessValue _completeness(Object? value) => switch (value) {
    'complete' => CompletenessValue.complete,
    'indeterminate' => CompletenessValue.indeterminate,
    'notVisible' => CompletenessValue.notVisible,
    _ => CompletenessValue.notApplicable,
  };

  Future<WorkspaceExtraction> extract(
    WorkspaceDiscoveryResult workspace, {
    bool includeEvidence = true,
  }) async {
    final root = workspace.config.root!;
    final outputs = <AdapterOutput>[];
    final errors = <String>[];
    for (final target in workspace.config.targetsConfig.entries) {
      final targetConfig = target.value;
      if (targetConfig is! Map) continue;
      final language = targetConfig['language'];
      if (language == 'dart') {
        final packages = targetConfig['packages'];
        if (packages is! List) continue;
        for (final package in packages) {
          if (package is! Map || package['path'] is! String) continue;
          final packageRoot = _join(root, package['path'] as String);
          if (!Directory(packageRoot).existsSync()) {
            errors.add('target package not found: $packageRoot');
            continue;
          }
          final roots =
              (package['roots'] as List?)?.whereType<String>().toList() ??
              const ['lib'];
          final cacheKey = _sourceDigest(packageRoot, roots, 'dart-http-v2');
          final cached = _loadCached(root, 'dart', cacheKey);
          AdapterOutput output;
          if (cached != null) {
            output = cached;
          } else {
            try {
              // Extraction is a tooling phase, not a proof.  Bound it so a
              // stuck analyzer cannot turn `validate` into an unreported
              // hang or be mistaken for successful topology discovery.
              output = await DartExtractor()
                  .extract(packageRoot, roots: roots)
                  .timeout(const Duration(seconds: 60));
            } on TimeoutException {
              errors.add(
                'ZUKE-EXTRACT-TIMEOUT: Dart extraction exceeded 60 seconds for $packageRoot',
              );
              continue;
            } catch (error) {
              errors.add('ZUKE-EXTRACT-FAILED: $packageRoot: $error');
              continue;
            }
          }
          if (output.graph != null) {
            errors.addAll(output.graph!.validate());
          }
          if (cached == null) _writeCached(root, 'dart', cacheKey, output);
          outputs.add(output);
          errors.addAll(output.errors);
        }
      }
    }
    final evidenceLoad = includeEvidence
        ? _loadEvidence(root, workspace.config.evidenceOutput)
        : const _EvidenceLoad([], []);
    errors.addAll(evidenceLoad.errors);
    final evidence = evidenceLoad.records;
    return WorkspaceExtraction(
      outputs: outputs,
      evidenceRecords: evidence,
      errors: errors,
    );
  }

  String _join(String root, String relative) =>
      '$root${Platform.pathSeparator}$relative'
          .replaceAll('/', Platform.pathSeparator)
          .replaceAll('\\', Platform.pathSeparator);

  String _sourceDigest(String root, List<String> roots, String adapter) {
    final files = <File>[];
    for (final relative in [
      ...roots,
      'pubspec.yaml',
      'pubspec.lock',
      'analysis_options.yaml',
      'zuke.yaml',
    ]) {
      final path = _join(root, relative);
      final file = File(path);
      if (file.existsSync()) files.add(file);
    }
    for (final relative in roots) {
      final dir = Directory(_join(root, relative));
      if (dir.existsSync())
        files.addAll(dir.listSync(recursive: true).whereType<File>());
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    final bytes = <int>[]..addAll(utf8.encode('$adapter|compat-8.2|'));
    final normalizedRoot = Directory(
      root,
    ).absolute.path.replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '');
    for (final file in files) {
      final normalized = file.absolute.path.replaceAll('\\', '/');
      final relative = normalized.startsWith('$normalizedRoot/')
          ? normalized.substring(normalizedRoot.length + 1)
          : normalized;
      bytes.addAll(utf8.encode(relative));
      bytes.add(0);
      bytes.addAll(canonicalDigestBytes(relative, file.readAsBytesSync()));
      bytes.add(0);
    }
    return sha256.convert(bytes).toString();
  }

  String _cachePath(String root, String adapter, String key) =>
      _join(root, '.zuke/cache/$adapter/$key.json');

  _EvidenceLoad _loadEvidence(String root, String? configuredPath) {
    final path = configuredPath == null || configuredPath.isEmpty
        ? _join(root, '.zuke/evidence')
        : _join(root, configuredPath);
    final files = <File>[];
    final candidate = File(path);
    if (candidate.existsSync()) {
      files.add(candidate);
    } else {
      final directory = Directory(path);
      if (directory.existsSync())
        files.addAll(
          directory.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.json'),
          ),
        );
    }
    final records = <EvidenceRecord>[];
    final errors = <String>[];
    final ids = <String>{};
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        final values = decoded is Map && decoded['record'] is Map
            ? [decoded['record']]
            : decoded is List
            ? decoded
            : decoded is Map
            ? [decoded]
            : const [];
        if (values.isEmpty) {
          errors.add(
            'Evidence file is not a record or record list: ${file.path}',
          );
        }
        for (final value in values.whereType<Map>()) {
          final record = Map<String, Object?>.from(value);
          final executionId = record['executionId'];
          if (executionId is! String || executionId.isEmpty) {
            errors.add('Invalid evidence record: ${file.path}');
            continue;
          }
          if (!ids.add(executionId)) {
            errors.add('Duplicate evidence executionId: $executionId');
            continue;
          }
          records.add(EvidenceRecord.fromJson(record));
        }
      } catch (error) {
        errors.add('Malformed evidence file ${file.path}: $error');
      }
    }
    return _EvidenceLoad(records, errors);
  }

  AdapterOutput? _loadCached(String root, String adapter, String key) {
    final file = File(_cachePath(root, adapter, key));
    if (!file.existsSync()) return null;
    try {
      final value = jsonDecode(file.readAsStringSync());
      if (value is! Map || value['schemaVersion'] != 'zuke.cache.v1')
        return null;
      final adapterMap = value['adapter'];
      final expectedCompatibility = adapter == 'dart'
          ? 'dart-analyzer-8.2-http-topology-v2'
          : null;
      if (adapterMap is! Map ||
          (expectedCompatibility != null &&
              adapterMap['compatibilityId'] != expectedCompatibility)) {
        return null;
      }
      final package = value['package'];
      final symbols = (value['symbols'] as List? ?? const [])
          .whereType<Map>()
          .map(_symbolFromJson)
          .toList();
      final completeness = value['completeness'] as Map? ?? const {};
      final output = AdapterOutput(
        adapter: AdapterInfo(
          id: adapterMap['id'] as String,
          version: adapterMap['version'] as String,
          compatibilityId: adapterMap['compatibilityId'] as String? ?? '',
        ),
        completeness: AdapterCompleteness(
          annotationTargets: _completeness(completeness['annotationTargets']),
          generatedParts: _completeness(completeness['generatedParts']),
          graph: GraphCompleteness(
            dynamicRegistration: _completeness(
              completeness['dynamicRegistration'],
            ),
            routeRegistration: _completeness(completeness['routeRegistration']),
            middlewareOrder: _completeness(completeness['middlewareOrder']),
            failureFlow: _completeness(completeness['failureFlow']),
            logFlow: _completeness(completeness['logFlow']),
            externalVisibility: _completeness(
              completeness['externalVisibility'],
            ),
          ),
        ),
        symbols: symbols,
        inputDigest: value['inputDigest'] as String? ?? key,
        packageName: package['name'] as String?,
        packageRoot: package['root'] as String?,
        diagnostics: (value['errors'] as List? ?? const [])
            .whereType<String>()
            .map(
              (message) => Diagnostic(
                code: 'CACHE-EXTRACT-001',
                message: message,
                severity: DiagnosticSeverity.error,
              ),
            )
            .toList(),
        graph: _graphFromJson(value['graph']),
      );
      if (output.graph != null && output.graph!.validate().isNotEmpty) {
        return null;
      }
      return output;
    } catch (_) {
      return null;
    }
  }

  ExtractedSymbol _symbolFromJson(Map value) {
    final source = value['source'] as Map? ?? const {};
    return ExtractedSymbol(
      kind: value['kind'] as String? ?? 'unknown',
      role: value['role'] as String? ?? 'unknown',
      symbolId: value['symbolId'] as String? ?? 'unknown',
      requirementIds: (value['requirementIds'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      controlIds: (value['controlIds'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      bindingId: value['bindingId'] as String?,
      providerKind: value['providerKind'] as String?,
      layer: value['layer'] as String?,
      target: value['target'] as String?,
      variant: value['variant'] as String? ?? 'default',
      slot: value['slot'] as String? ?? 'primary',
      evidenceType: value['evidenceType'] as String?,
      scenarioIds: (value['scenarioIds'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      source: ExtractedSourceLocation(
        uri: source['uri'] as String? ?? '',
        offset: source['offset'] as int? ?? 0,
        length: source['length'] as int? ?? 0,
        line: source['line'] as int? ?? 0,
        column: source['column'] as int? ?? 0,
      ),
    );
  }

  IrGraph? _graphFromJson(Object? raw) {
    if (raw is! Map) return null;
    final nodes = (raw['nodes'] as List? ?? const []).whereType<Map>().map((
      node,
    ) {
      return IrNode(
        id: node['id'] as String,
        kind: NodeKind.values.firstWhere((k) => k.name == node['kind']),
        target: node['target'] as String?,
        role: node['role'] as String?,
        variant: node['variant'] as String?,
        slot: node['slot'] as String?,
        properties: Map<String, Object?>.from(
          node['properties'] as Map? ?? const {},
        ),
      );
    }).toList();
    final edges = (raw['edges'] as List? ?? const []).whereType<Map>().map((
      edge,
    ) {
      return IrEdge(
        sourceId: edge['source'] as String,
        targetId: edge['target'] as String,
        kind: EdgeKind.values.firstWhere((k) => k.name == edge['kind']),
        properties: Map<String, Object?>.from(
          edge['properties'] as Map? ?? const {},
        ),
        source: edge['location'] is Map
            ? SourceSpan.fromJson(
                Map<String, Object?>.from(edge['location'] as Map),
              )
            : null,
      );
    }).toList();
    final c = raw['completeness'] as Map? ?? const {};
    CompletenessValue parse(String? value) =>
        CompletenessValue.values.firstWhere(
          (v) => v.name == value,
          orElse: () => CompletenessValue.notApplicable,
        );
    return IrGraph(
      nodes: nodes,
      edges: edges,
      completeness: GraphCompleteness(
        routeRegistration: parse(c['routeRegistration'] as String?),
        middlewareOrder: parse(c['middlewareOrder'] as String?),
        failureFlow: parse(c['failureFlow'] as String?),
        logFlow: parse(c['logFlow'] as String?),
        dynamicRegistration: parse(c['dynamicRegistration'] as String?),
        externalVisibility: parse(c['externalVisibility'] as String?),
      ),
    );
  }

  void _writeCached(
    String root,
    String adapter,
    String key,
    AdapterOutput output,
  ) {
    if (output.errors.isNotEmpty) return;
    final file = File(_cachePath(root, adapter, key));
    file.parent.createSync(recursive: true);
    final temporary = File('${file.path}.tmp');
    temporary.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
            'schemaVersion': 'zuke.cache.v1',
            'adapter': {
              'id': output.adapter.id,
              'version': output.adapter.version,
              'compatibilityId': output.adapter.compatibilityId,
            },
            'package': {'name': output.packageName, 'root': output.packageRoot},
            'completeness': output.completeness.toJson(),
            'inputDigest': output.inputDigest,
            'errors': output.errors,
            if (output.graph != null) 'graph': output.graph!.toJson(),
            'symbols': output.symbols
                .map(
                  (s) => {
                    'kind': s.kind,
                    'role': s.role,
                    'symbolId': s.symbolId,
                    if (s.requirementIds.isNotEmpty)
                      'requirementIds': s.requirementIds,
                    if (s.controlIds.isNotEmpty) 'controlIds': s.controlIds,
                    if (s.bindingId != null) 'bindingId': s.bindingId,
                    if (s.providerKind != null) 'providerKind': s.providerKind,
                    if (s.layer != null) 'layer': s.layer,
                    if (s.target != null) 'target': s.target,
                    'variant': s.variant,
                    'slot': s.slot,
                    if (s.evidenceType != null) 'evidenceType': s.evidenceType,
                    if (s.scenarioIds.isNotEmpty) 'scenarioIds': s.scenarioIds,
                    'source': {
                      'uri': s.source.uri,
                      'offset': s.source.offset,
                      'length': s.source.length,
                      'line': s.source.line,
                      'column': s.source.column,
                    },
                  },
                )
                .toList(),
          }) +
          '\n',
    );
    if (file.existsSync()) file.deleteSync();
    temporary.renameSync(file.path);
  }
}

class _EvidenceLoad {
  final List<EvidenceRecord> records;
  final List<String> errors;
  const _EvidenceLoad(this.records, this.errors);
}
