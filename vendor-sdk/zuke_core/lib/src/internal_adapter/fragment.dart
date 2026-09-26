import '../internal_ir.dart';

class CanonicalFragment {
  final String kind;
  final AdapterDescriptor adapter;
  final String packageName;
  final String packageRoot;
  final IrAdapterCompleteness completeness;
  final List<ExtractedSymbol> symbols;

  /// The adapter's own read-digest, not the published snapshot identity.
  ///
  /// The tools that build a fragment (`zuke extract`) invoke the adapter
  /// directly and never go through the extraction service, so no
  /// `IrAdapterOutput.provenanceDigest` exists at this level. Locks and evidence
  /// records publish the *provenance* identity instead, through
  /// `IrAdapterOutput.requirePublishedSourceDigest`. The two are deliberately
  /// different quantities: the read-digest covers generated files, the
  /// provenance identity does not. Do not "fix" this to use the provenance —
  /// there is none here, and the trace envelope is an adapter-level contract.
  final String inputDigest;
  final IrGraph? graph;

  const CanonicalFragment({
    required this.kind,
    required this.adapter,
    required this.packageName,
    required this.packageRoot,
    required this.completeness,
    required this.symbols,
    required this.inputDigest,
    this.graph,
  });

  factory CanonicalFragment.fromOutput(
    IrAdapterOutput output, {
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
      kind: 'zuke.adapter-fragment',
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
    'kind': kind,
    'adapter': {
      'id': adapter.id,
      'version': adapter.version,
      'compatibilityId': adapter.compatibilityId,
    },
    'package': {'name': packageName, 'root': packageRoot},
    'completeness': completeness.toJson(),
    // The adapter read-digest; see [inputDigest] for why this is not the
    // published snapshot identity.
    'inputs': {'digest': 'sha256:$inputDigest'},
    if (graph != null) 'graph': graph!.toJson(),
    'symbols': symbols
        .map(
          (s) => {
            'kind': s.kind.name,
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
