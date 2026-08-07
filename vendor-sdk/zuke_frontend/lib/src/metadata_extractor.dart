import 'types.dart';

class MetadataExtractorResult {
  final List<ParsedFeature> features;
  final Map<String, Map<String, dynamic>> epics;
  final Map<String, Map<String, dynamic>> controls;
  final Map<String, Map<String, dynamic>> registries;
  final Map<String, Map<String, dynamic>> policies;
  final List<String> errors;

  const MetadataExtractorResult({
    this.features = const [],
    this.epics = const {},
    this.controls = const {},
    this.registries = const {},
    this.policies = const {},
    this.errors = const [],
  });
}
