import '../assurance_ir.dart';

class CanonicalFragment {
  final String schemaVersion;
  final AdapterDescriptor adapter;
  final String packageName;
  final String packageRoot;
  final AdapterCompleteness completeness;
  final List<ExtractedSymbol> symbols;
  final String inputDigest;
  final IrGraph? graph;

  const CanonicalFragment({
    required this.schemaVersion,
    required this.adapter,
    required this.packageName,
    required this.packageRoot,
    required this.completeness,
    required this.symbols,
    required this.inputDigest,
    this.graph,
  });

  factory CanonicalFragment.fromOutput(
    AdapterOutput output, {
    String? workspaceRoot,
  }) {
    final packageName = output.packageName;
    final packageRoot = output.packageRoot;
    if (packageName == null || packageRoot == null) {
      throw ArgumentError('Adapter output must identify its package');
    }
    var normalizedRoot = packageRoot.replaceAll('\\', '/');
    if (workspaceRoot != null) {
      final workspace = workspaceRoot
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'/$'), '');
      if (normalizedRoot.startsWith('$workspace/')) {
        normalizedRoot = normalizedRoot.substring(workspace.length + 1);
      }
    }
    return CanonicalFragment(
      schemaVersion: 'zuke.trace.v1',
      adapter: output.adapter,
      packageName: packageName,
      packageRoot: normalizedRoot,
      completeness: output.completeness,
      symbols: output.symbols,
      inputDigest: output.inputDigest,
      graph: output.graph,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'adapter': {
      'id': adapter.id,
      'version': adapter.version,
      'compatibilityId': adapter.compatibilityId,
    },
    'package': {'name': packageName, 'root': packageRoot},
    'completeness': completeness.toJson(),
    'inputs': {'digest': 'sha256:$inputDigest'},
    if (graph != null) 'graph': graph!.toJson(),
    'symbols': symbols
        .map(
          (s) => {
            'kind': s.kind,
            'role': s.role,
            'symbolId': s.symbolId,
            if (s.requirementIds.isNotEmpty) 'requirementIds': s.requirementIds,
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
  };
}
