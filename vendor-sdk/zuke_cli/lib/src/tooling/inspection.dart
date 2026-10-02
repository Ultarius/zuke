/// Published inspection implementation API; not an extension contract.
library;

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

export '../implementation_claims.dart';
export '../index_contract.dart';
export '../path_safety.dart'
    show
        isSameWorkspacePath,
        normalizeRelativePath,
        pathComparisonKey,
        pathEqualsOrWithin;
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
/// The library exporting the Flutter evidence harness. Named because a caller
/// matching a harness by library had no constant to reach for and inlined the
/// URI, which then drifted from the set above.
const zukeFlutterHarnessLibrary =
    'package:zuke_runner_flutter/zuke_runner_flutter.dart';

const zukeManagedTestLibraries = {
  'package:zuke/testing.dart',
  'package:zuke/src/testing.dart',
  zukeFlutterHarnessLibrary,
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

/// The evidence kinds a managed entry point publishes when the call site does
/// not say. `zukeUnit` takes no `evidenceTypes` parameter and delegates with
/// `const ['unit']`, so the only way to know what it publishes is to know that.
const zukeImpliedEvidenceTypes = {
  'zukeUnit': ['unit'],
};

/// The evidence kind a scenario harness publishes when the call site does not
/// say. `ZukeFlutterHarness` declares a single `evidenceType` defaulting to
/// `gherkin-ui`, and that default is what every example workspace relies on, so
/// a harness whose argument is absent still publishes it.
const zukeHarnessDefaultEvidenceType = 'gherkin-ui';

/// The evidence kinds a managed entry point publishes, or null when unknown.
///
/// A null result means "cannot be read", not "publishes nothing": the
/// registration may be exactly the one satisfying a declared slot, so a caller
/// reporting gaps must treat null as blocking the question.
///
/// Managed entry points declare a list (`evidenceTypes:`). `zukeUnit` declares
/// none and delegates with `const ['unit']`.
///
/// An entry point that declares nothing readable is null, not the implied
/// default: `zukeTest` has no default, and an unreadable list may name the very
/// kind a declared slot requires.
List<String>? entrypointEvidenceTypes(
  String entrypoint,
  Iterable<AstNode> arguments,
) {
  final declared = constantStringsArgument(arguments, 'evidenceTypes');
  if (declared.isReadable) return declared.values;
  if (declared.isPresent) return null;
  final implied = zukeImpliedEvidenceTypes[entrypoint];
  return implied == null ? null : List.unmodifiable(implied);
}

/// The harness type [node] constructs, or null when it is not one from the
/// harness library.
///
/// Matched on the resolved library rather than the spelling, so a locally
/// declared `FlutterEvidenceCase` cannot contribute evidence kinds to a scan.
String? zukeFlutterHarnessTypeName(InstanceCreationExpression node) {
  final type = node.constructorName.type.element;
  if (type?.library?.firstFragment.source.uri.toString() !=
      zukeFlutterHarnessLibrary) {
    return null;
  }
  return type?.name;
}

/// Whether [element] is a `registerAll` declared by the Flutter harness library.
///
/// This is what makes a call a registration. A `FlutterEvidenceCase` that is
/// constructed but never handed to a `registerAll` call is not a test, so
/// counting the construction alone would credit a case nothing runs.
///
/// Identified from the declaring library rather than the spelling, so a
/// user-defined `registerAll` is not mistaken for the harness one.
bool isZukeHarnessRegisterAll(Element? element) =>
    element?.library?.firstFragment.source.uri.toString() ==
        zukeFlutterHarnessLibrary &&
    resolvedElementName(element) == 'registerAll';

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

/// The value expression of the named argument [name], or null when absent.
///
/// Analyzer 12 models a named argument as `NamedExpression` and analyzer 14 as
/// `NamedArgument`; both expose the name and colon as consecutive tokens and the
/// value as their final expression child. Walking that common structure keeps
/// this usable from the CLI and the analysis-server plugin without binding to
/// either node API.
Expression? namedArgumentValue(Iterable<AstNode> arguments, String name) {
  for (final argument in arguments) {
    final label = argument.beginToken;
    if (label.lexeme != name || label.next?.lexeme != ':') continue;
    final expressions = argument.childEntities.whereType<Expression>();
    return expressions.isEmpty ? null : expressions.last;
  }
  return null;
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

/// Whether an optional constant argument is absent, readable, or unreadable.
///
/// Three states, not two. Callers act differently on each: an absent argument
/// may fall back to a declared default, a readable one is the answer, and an
/// unreadable one blocks the question outright. Collapsing absent and
/// unreadable is what lets an unreadable override silently inherit a default it
/// may have replaced.
enum ConstantArgumentState { absent, readable, unreadable }

/// The result of reading an optional constant string-list argument.
final class ConstantStringsArgument {
  const ConstantStringsArgument._(this.state, this.values);

  const ConstantStringsArgument.absent()
    : this._(ConstantArgumentState.absent, null);

  const ConstantStringsArgument.unreadable()
    : this._(ConstantArgumentState.unreadable, null);

  ConstantStringsArgument.readable(List<String> values)
    : this._(ConstantArgumentState.readable, List.unmodifiable(values));

  final ConstantArgumentState state;

  /// The values when [state] is [ConstantArgumentState.readable].
  final List<String>? values;

  bool get isAbsent => state == ConstantArgumentState.absent;
  bool get isReadable => state == ConstantArgumentState.readable;

  /// Present but not interpretable. Not the same as absent: the call site said
  /// something this cannot read.
  bool get isPresent => state != ConstantArgumentState.absent;
}

/// Reads the optional constant string-list argument [name].
ConstantStringsArgument constantStringsArgument(
  Iterable<AstNode> arguments,
  String name,
) {
  final expression = namedArgumentValue(arguments, name);
  if (expression == null) return const ConstantStringsArgument.absent();
  final values = constantStringsFromExpression(expression);
  return values == null
      ? const ConstantStringsArgument.unreadable()
      : ConstantStringsArgument.readable(values);
}

/// [expression] resolved to a constant list of strings, or null when it is not
/// one.
///
/// Null covers every way the value cannot be known: a nonliteral expression, an
/// unresolvable constant, or a collection that carries elements this does not
/// interpret. A spread or a collection-if yields null rather than the literal
/// elements around it, because returning those would report a partial reading as
/// a complete one and could invent or hide a gap.
List<String>? constantStringsFromExpression(Expression expression) {
  // A literal list needs no element model: read its elements directly, so the
  // common `evidenceTypes: const ['domain-unit']` form does not depend on the
  // resolver having attached elements to it.
  if (expression is ListLiteral) {
    // `elements` rather than the `Expression` children: a spread or a
    // collection-if is a CollectionElement and would be skipped by a filter on
    // Expression, silently narrowing a list that has more in it.
    final literals = <String>[];
    for (final element in expression.elements) {
      if (element is! SimpleStringLiteral || element.value.isEmpty) return null;
      literals.add(element.value);
    }
    return literals;
  }
  // A bare string is a reading of one kind, which is how `evidenceType:` is
  // declared.
  if (expression is StringLiteral) {
    final value = expression.stringValue;
    return value == null || value.isEmpty ? null : [value];
  }
  Element? member;
  if (expression is SimpleIdentifier) {
    member = expression.element;
  } else {
    final identifiers = expression.childEntities
        .whereType<SimpleIdentifier>()
        .toList();
    if (identifiers.isNotEmpty) member = identifiers.last.element;
  }
  // `PropertyAccessorElement` must resolve through its variable: the accessor
  // itself carries no constant value.
  final DartObject? value;
  if (member is VariableElement) {
    value = member.computeConstantValue();
  } else if (member is PropertyAccessorElement) {
    value = member.variable.computeConstantValue();
  } else {
    return null;
  }
  if (value == null || !value.hasKnownValue) return null;
  return _constantStringsOf(value);
}

/// The strings of a resolved constant, or null when it is not a list of them.
///
/// A single string constant is also a reading of one kind, so `evidenceType:`
/// pointing at a constant works the same as one written inline.
List<String>? _constantStringsOf(DartObject value) {
  if (value.isNull) return const [];
  final single = value.toStringValue();
  if (single != null) return single.isEmpty ? null : [single];
  final items = value.toListValue();
  if (items == null) return null;
  final result = <String>[];
  for (final item in items) {
    final text = item.toStringValue();
    if (text == null || text.isEmpty) return null;
    result.add(text);
  }
  return result;
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
