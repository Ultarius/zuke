import '../adapter_sdk.dart';

class DartExtractionResult {
  final List<CanonicalFragment> fragments;
  final List<String> errors;

  const DartExtractionResult({
    this.fragments = const [],
    this.errors = const [],
  });
}

class AnnotationTarget {
  final String uri;
  final int offset;
  final int length;
  final int line;
  final int column;
  final String symbolName;
  final String kind; // 'class', 'getter', 'function', 'method'

  const AnnotationTarget({
    required this.uri,
    required this.offset,
    required this.length,
    required this.line,
    required this.column,
    required this.symbolName,
    required this.kind,
  });
}

class DartAnnotationValue {
  final String annotationName; // e.g. 'ImplementsRequirement'
  final List<String> stringArgs;
  final Map<String, String> namedArgs;

  const DartAnnotationValue({
    required this.annotationName,
    this.stringArgs = const [],
    this.namedArgs = const {},
  });
}
