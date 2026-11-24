import 'ir.dart';
import '../digest.dart';
import '../evidence.dart';

/// Diagnostic severities are shared by adapters, validators, and reporters.
enum IrDiagnosticSeverity { error, warning, info }

class IrDiagnostic {
  final String code;
  final String message;
  final IrDiagnosticSeverity severity;

  /// Concrete next step for this code, rendered alongside the message in
  /// text mode. Validators own it so a failure never leaves the operator to
  /// infer the remedy from the finding itself.
  final String? remediation;

  /// SourceSpan is canonical; Object? keeps frontend diagnostics source
  /// compatible during the migration and is normalized by toJson.
  final Object? source;

  const IrDiagnostic({
    required this.code,
    required this.message,
    required this.severity,
    this.remediation,
    this.source,
  });

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'severity': severity.name,
    if (remediation != null) 'remediation': remediation,
    if (source != null)
      'source': source is SourceSpan
          ? (source as SourceSpan).toJson()
          : source.toString(),
  };

  @override
  String toString() => '$code: $message';
}

class AdapterDescriptor {
  final String id;
  final String version;
  final String compatibilityId;

  const AdapterDescriptor({
    required this.id,
    required this.version,
    this.compatibilityId = '',
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'compatibilityId': compatibilityId,
  };
}

class IrAdapterCompleteness {
  final CompletenessValue annotationTargets;
  final CompletenessValue generatedParts;
  final GraphCompleteness graph;

  const IrAdapterCompleteness({
    this.annotationTargets = CompletenessValue.complete,
    this.generatedParts = CompletenessValue.complete,
    this.graph = const GraphCompleteness(),
  });

  Map<String, String> toJson() => {
    'annotationTargets': annotationTargets.name,
    'generatedParts': generatedParts.name,
    ...graph.toJson(),
  };
}

class ExtractedSourceLocation {
  final String uri;
  final int offset;
  final int length;
  final int line;
  final int column;

  const ExtractedSourceLocation({
    required this.uri,
    required this.offset,
    required this.length,
    required this.line,
    required this.column,
  });

  Map<String, Object?> toJson() => {
    'uri': uri,
    'offset': offset,
    'length': length,
    'line': line,
    'column': column,
  };
}

/// Kinds of symbols emitted by package extractors.
///
/// Enum names match the adapter JSON wire strings (`requirementBoundary`, …).
enum ExtractedSymbolKind {
  requirementBoundary,
  presentationBoundary,
  verificationBoundary,
  controlProvider,
  binding,
}

class ExtractedSymbol {
  final ExtractedSymbolKind kind;
  final String role;
  final String symbolId;
  final List<String> requirementIds;
  final List<String> controlIds;
  final String? bindingId;
  final String? providerKind;
  final String? layer;
  final String? target;
  final String variant;
  final String slot;
  final String? evidenceType;
  final List<String> scenarioIds;
  final ExtractedSourceLocation source;

  const ExtractedSymbol({
    required this.kind,
    required this.role,
    required this.symbolId,
    this.requirementIds = const [],
    this.controlIds = const [],
    this.bindingId,
    this.providerKind,
    this.layer,
    this.target,
    this.variant = 'default',
    this.slot = 'primary',
    this.evidenceType,
    this.scenarioIds = const [],
    required this.source,
  });

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'role': role,
    'symbolId': symbolId,
    if (requirementIds.isNotEmpty)
      'requirementIds': [...requirementIds]..sort(),
    if (controlIds.isNotEmpty) 'controlIds': [...controlIds]..sort(),
    if (bindingId != null) 'bindingId': bindingId,
    if (providerKind != null) 'providerKind': providerKind,
    if (layer != null) 'layer': layer,
    if (target != null) 'target': target,
    'variant': variant,
    'slot': slot,
    if (evidenceType != null) 'evidenceType': evidenceType,
    if (scenarioIds.isNotEmpty) 'scenarioIds': [...scenarioIds]..sort(),
    'source': source.toJson(),
  };
}

class IrAdapterOutput {
  final AdapterDescriptor adapter;
  final IrAdapterCompleteness completeness;
  final List<ExtractedSymbol> symbols;

  /// The digest of everything this adapter read, in the adapter's own terms.
  ///
  /// Meaningful to the adapter and to the extraction cache; it is *not* the
  /// identity published in evidence. An adapter that reads generated files sees
  /// them here, so regenerating a contract moves this value.
  final String inputDigest;

  /// The prose-free identity published for this source snapshot.
  ///
  /// Set by [ExtractionService] only — the single place that decides what
  /// evidence, lock fragments and control digests record. Null for an output
  /// produced or loaded outside that service; read it through
  /// `publishedSourceDigest` rather than directly so the fallback lives in one
  /// place.
  final SourceSnapshotDigest? provenanceDigest;

  final List<IrDiagnostic> diagnostics;
  final String? packageName;
  final String? packageRoot;
  final IrGraph? graph;
  final List<EvidenceRecord> evidenceRecords;

  const IrAdapterOutput({
    required this.adapter,
    required this.completeness,
    required this.symbols,
    required this.inputDigest,
    this.provenanceDigest,
    this.diagnostics = const [],
    this.packageName,
    this.packageRoot,
    this.graph,
    this.evidenceRecords = const [],
  });

  List<String> get errors => diagnostics.map((d) => d.message).toList();

  /// The `sha256:<hex>` identity to publish for this output's source snapshot.
  ///
  /// Prefers [provenanceDigest], the prose-free identity the extraction service
  /// publishes. Falls back to the adapter's own [inputDigest] for an output that
  /// never passed through that service — an adapter used directly, or a
  /// hand-built fixture. Null when neither value is a usable SHA-256 digest, so
  /// each caller can choose between failing loudly and treating the record as
  /// stale rather than silently comparing against a mangled string.
  String? get publishedSourceDigest {
    final provenance = provenanceDigest;
    if (provenance != null) return provenance.wireForm;
    try {
      return SourceSnapshotDigest.parse(inputDigest).wireForm;
    } on FormatException {
      return null;
    }
  }

  /// The published `sha256:<hex>` identity of [output], or a [FormatException].
  ///
  /// Use this wherever the digest is written into a durable artifact — evidence
  /// records, lock fragments, control digests — so that an unusable identity is
  /// reported rather than recorded as a plausible-looking wrong value. Only
  /// validation should read [IrAdapterOutput.publishedSourceDigest] leniently,
  /// because there a missing identity legitimately means the record is stale.
  String requirePublishedSourceDigest() {
    final digest = publishedSourceDigest;
    if (digest != null) return digest;
    throw FormatException(
      'Package ${packageName ?? adapter.id} has no usable published source '
      'identity (adapter read-digest "$inputDigest").',
    );
  }

  Map<String, Object?> toJson() => {
    'kind': 'zuke.adapter-output',
    'adapter': adapter.toJson(),
    'completeness': completeness.toJson(),
    'symbols': symbols.map((s) => s.toJson()).toList(),
    'inputDigest': inputDigest,
    if (provenanceDigest != null) 'provenanceDigest': provenanceDigest!.value,
    if (packageName != null) 'packageName': packageName,
    if (packageRoot != null) 'packageRoot': packageRoot,
  };
}
