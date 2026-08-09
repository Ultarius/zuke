import 'types.dart';

/// Metadata collected from a workspace's specification files.
class MetadataExtractorResult {
  /// Parsed feature documents.
  final List<ParsedFeature> features;

  /// Epic records keyed by identifier.
  final Map<String, Map<String, dynamic>> epics;

  /// Control records keyed by identifier.
  final Map<String, Map<String, dynamic>> controls;

  /// Registry records keyed by identifier.
  final Map<String, Map<String, dynamic>> registries;

  /// Project policy documents keyed by path.
  final Map<String, Map<String, dynamic>> policies;

  /// Extraction errors.
  final List<String> errors;

  /// Creates extracted workspace metadata.
  const MetadataExtractorResult({
    this.features = const [],
    this.epics = const {},
    this.controls = const {},
    this.registries = const {},
    this.policies = const {},
    this.errors = const [],
  });
}
