/// Published inspection implementation API; not an extension contract.
library;

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

export '../implementation_claims.dart';
export '../index_contract.dart';
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

/// Libraries that publish managed test entry points.
///
/// A Dart-only workspace reaches them through `package:zuke`, a Flutter one
/// through `package:zuke_runner_flutter`, and both expose a `zukeTest` with the
/// same contract, so both have to be recognised or a pure-Dart project is never
/// checked.
const zukeManagedTestLibraries = {
  'package:zuke/testing.dart',
  'package:zuke/src/testing.dart',
  'package:zuke_runner_flutter/zuke_runner_flutter.dart',
};

/// Managed entry points that must be told which evidence they publish.
///
/// Both throw an `ArgumentError` when `evidenceTypes` is absent or empty, but
/// only under a managed run, so the code is green under a plain `dart test` and
/// then fails the assurance gate.
const zukeEvidenceDeclaringEntrypoints = {'zukeTest', 'zukeTestWidgets'};

/// Managed entry points that publish evidence without being told which.
///
/// `zukeUnit` takes no `evidenceTypes` parameter at all and delegates with
/// `const ['unit']`, so the exemption has to be by resolved name: it cannot be
/// inferred from the call site having no such argument.
const zukeSelfEvidencingEntrypoints = {'zukeUnit'};

/// The managed entry point [element] resolves to, or null when it is not one.
///
/// Matches on the resolved library identity rather than the spelling, so a
/// locally declared `zukeTest` cannot impersonate the real one and inherit a
/// diagnostic it does not deserve.
String? zukeManagedEntrypointName(Element? element) {
  final libraryUri = element?.library?.firstFragment.source.uri.toString();
  if (libraryUri == null || !zukeManagedTestLibraries.contains(libraryUri)) {
    return null;
  }
  final name = resolvedElementName(element);
  if (name == null) return null;
  return zukeEvidenceDeclaringEntrypoints.contains(name) ||
          zukeSelfEvidencingEntrypoints.contains(name)
      ? name
      : null;
}

/// Whether a managed call's `evidenceTypes` argument is present and non-empty.
///
/// Returns null when the named argument is absent. A nonliteral expression is
/// treated as declared because its runtime contents cannot be known here.
///
/// Analyzer 12 models a named argument as `NamedExpression`, while analyzer 14
/// models it as `NamedArgument`. Both expose the name and colon as consecutive
/// tokens and the value as their final expression child. Inspecting that common
/// AST structure keeps this check typed without binding it to either node API.
bool? declaresReadableEvidenceTypes(Iterable<AstNode> arguments) {
  for (final argument in arguments) {
    final name = argument.beginToken;
    if (name.lexeme != 'evidenceTypes' || name.next?.lexeme != ':') continue;
    final expressions = argument.childEntities.whereType<Expression>();
    if (expressions.isEmpty) return true;
    return switch (expressions.last) {
      ListLiteral(:final elements) => elements.isNotEmpty,
      SetOrMapLiteral(:final elements) => elements.isNotEmpty,
      _ => true,
    };
  }
  return null;
}

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
