/// Published inspection implementation API; not an extension contract.
library;

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

export 'dart_extractor/zuke_index.dart';

const zukeAnnotationLibrary = 'package:zuke_annotations/zuke_annotations.dart';

bool isResolvedLibrary(Element? element, String libraryUri) =>
    element?.library?.firstFragment.source.uri.toString() == libraryUri;

String? resolvedElementName(Element? element) {
  if (element is ConstructorElement) return element.enclosingElement.name;
  return element?.name;
}

String? constantString(DartObject? value, String field) =>
    value?.getField(field)?.toStringValue();

List<String>? constantStrings(DartObject? value, String field) {
  final list = value?.getField(field)?.toListValue();
  if (list == null) return null;
  final result = <String>[];
  for (final item in list) {
    final string = item.toStringValue();
    if (string == null || string.isEmpty) return null;
    result.add(string);
  }
  return result;
}

/// Whether [element] resolves to an annotation owned by Zuke. This uses
/// the resolved library identity rather than an annotation spelling, so local
/// classes with matching names cannot impersonate the public annotations.
bool isZukeAnnotation(Element? element) {
  final libraryUri = element?.library?.firstFragment.source.uri.toString();
  return libraryUri == zukeAnnotationLibrary ||
      (libraryUri?.startsWith('package:zuke_annotations/') ?? false);
}

/// The canonical Zuke annotation name for a resolved annotation element.
String? zukeAnnotationName(Element? element) =>
    isZukeAnnotation(element) ? resolvedElementName(element) : null;

/// The declaration targets supported by each public annotation. The extractor,
/// analyzer plugin, and hook must all consult this one matrix.
bool supportsZukeAnnotationTarget(String annotationName, String target) {
  final allowed = switch (annotationName) {
    'ImplementsRequirement' => const {
      'class',
      'mixin',
      'extensionType',
      'method',
      'function',
    },
    'PresentsRequirement' => const {'class', 'method', 'function'},
    'ProvidesControl' => const {'class', 'mixin', 'method', 'function'},
    'ZukeBinding' => const {'field', 'getter'},
    'VerifiesRequirement' => const {'method', 'function'},
    _ => const <String>{},
  };
  return allowed.contains(target);
}
