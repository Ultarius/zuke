import 'ir.dart';
import 'validation.dart';

/// Diagnostic severities are shared by adapters, validators, and reporters.
enum IrDiagnosticSeverity { error, warning, info }

class IrDiagnostic {
  final String code;
  final String message;
  final IrDiagnosticSeverity severity;

  /// SourceSpan is canonical; Object? keeps frontend diagnostics source
  /// compatible during the migration and is normalized by toJson.
  final Object? source;

  const IrDiagnostic({
    required this.code,
    required this.message,
    required this.severity,
    this.source,
  });

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'severity': severity.name,
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

class ExtractedSymbol {
  final String kind;
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
    'kind': kind,
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
  final String inputDigest;
  final List<IrDiagnostic> diagnostics;
  final String? packageName;
  final String? packageRoot;
  final IrGraph? graph;
  final List<SemanticEvidenceRecord> evidenceRecords;

  const IrAdapterOutput({
    required this.adapter,
    required this.completeness,
    required this.symbols,
    required this.inputDigest,
    this.diagnostics = const [],
    this.packageName,
    this.packageRoot,
    this.graph,
    this.evidenceRecords = const [],
  });

  List<String> get errors => diagnostics.map((d) => d.message).toList();

  Map<String, Object?> toJson() => {
    'schemaVersion': 'zuke.adapter-output.v1',
    'adapter': adapter.toJson(),
    'completeness': completeness.toJson(),
    'symbols': symbols.map((s) => s.toJson()).toList(),
    'inputDigest': inputDigest,
    if (packageName != null) 'packageName': packageName,
    if (packageRoot != null) 'packageRoot': packageRoot,
  };
}
