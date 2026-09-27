/// Shared machinery for scanning a workspace's sources for Zuke annotations.
///
/// Zuke annotations rarely spell their identifiers inline. They reference
/// `static const` fields and `static const` lists declared elsewhere — usually
/// in the generated contracts — so any scan that has to resolve an
/// annotation's real IDs has to collect those declarations first.
///
/// Both the `@VerifiesRequirement` scan and the implementation scan need this,
/// so it lives here rather than being copied per scan. The file-discovery
/// helpers at the bottom are shared for the same reason: every annotation scan
/// must visit the same files in the same order.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

/// Accumulated `static const` values found across a set of source files.
///
/// Keys are both the bare member name (`addition`) and the qualified form
/// (`FeatCalc001RequirementIds.addition`), because an annotation may reference
/// either.
final class SourceConstants {
  final Map<String, String> values = {};
  final Map<String, ListLiteral> listDeclarations = {};

  /// Const lists resolved to their IDs once every file has been scanned.
  ///
  /// A list alias can reference constants declared in a *later* file — a list of
  /// members imported from a file that sorts after it — so lists are resolved
  /// in a second pass by [resolveLists] rather than at first use. Reading an
  /// annotation before that pass would silently resolve the alias to nothing.
  final Map<String, List<String>> _resolvedLists = {};

  /// Resolves every collected const list against the full value map.
  ///
  /// Call this once all files have been scanned and before reading any
  /// annotation. It is idempotent.
  void resolveLists() {
    for (final entry in listDeclarations.entries) {
      if (_resolvedLists.containsKey(entry.key)) continue;
      final ids = constIdsInList(entry.value, values);
      if (ids.isNotEmpty) _resolvedLists[entry.key] = ids;
    }
  }

  /// Resolves a const list declaration to its string IDs.
  ///
  /// Accepts an inline list literal, a bare or qualified reference, and
  /// tolerates the reference being written in either `Class.member` or
  /// `.member` form. Annotations use all three spellings.
  List<String> idsForList(Expression reference) {
    if (reference is ListLiteral) return constIdsInList(reference, values);
    final key = _keyFor(reference);
    if (key == null) return const [];
    final resolved = _resolvedLists[key] ?? _resolvedLists[key.split('.').last];
    if (resolved != null) return resolved;
    final list = listDeclarations[key] ?? listDeclarations[key.split('.').last];
    return list == null ? const [] : constIdsInList(list, values);
  }

  /// Resolves a const string declaration to its value.
  String? valueOf(Expression reference) {
    if (reference is StringLiteral) return reference.stringValue;
    final key = _keyFor(reference);
    if (key == null) return null;
    return values[key] ?? values[key.split('.').last];
  }

  static String? _keyFor(Expression expression) {
    if (expression is PrefixedIdentifier) {
      return '${expression.prefix.name}.${expression.identifier.name}';
    }
    if (expression is SimpleIdentifier) return expression.name;
    return null;
  }
}

/// Scans [files] for `static const` strings and const lists, adding to
/// [constants]. Unparseable files are skipped: a scan must not fail the
/// generation of everything else.
void collectSourceConstants(File file, SourceConstants constants) {
  final content = file.readAsStringSync();
  if (!content.contains('const')) return;
  try {
    final parsed = parseString(
      content: content,
      path: file.path,
      throwIfDiagnostics: false,
    );
    parsed.unit.accept(_StaticConstCollector(constants));
  } on FormatException {
    return;
  } on FileSystemException {
    return;
  }
}

/// The string IDs a const list literal resolves to, skipping unresolvable
/// elements rather than failing the whole list.
List<String> constIdsInList(ListLiteral list, Map<String, String> values) {
  final ids = <String>[];
  for (final element in list.elements) {
    if (element is! Expression) continue;
    final value = _constIdOf(element, values);
    if (value != null && value.isNotEmpty) ids.add(value);
  }
  return ids;
}

String? _constIdOf(Expression element, Map<String, String> values) {
  if (element is StringLiteral) return element.stringValue;
  if (element is PrefixedIdentifier) {
    final key = '${element.prefix.name}.${element.identifier.name}';
    return values[key] ?? values[element.identifier.name];
  }
  if (element is SimpleIdentifier) return values[element.name];
  return null;
}

class _StaticConstCollector extends RecursiveAstVisitor<void> {
  _StaticConstCollector(this.constants);

  final SourceConstants constants;
  String? _className;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final previous = _className;
    _className = node.namePart.typeName.lexeme;
    super.visitClassDeclaration(node);
    _className = previous;
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final previous = _className;
    _className = node.namePart.typeName.lexeme;
    super.visitEnumDeclaration(node);
    _className = previous;
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    if (!node.variables.isConst) return;
    _collectVariables(node.variables.variables);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (!node.isStatic || !node.fields.isConst) return;
    _collectVariables(node.fields.variables);
  }

  void _collectVariables(NodeList<VariableDeclaration> variables) {
    for (final variable in variables) {
      final initializer = variable.initializer;
      final name = variable.name.lexeme;
      if (initializer is StringLiteral) {
        final value = initializer.stringValue;
        if (value == null || value.isEmpty) continue;
        constants.values[name] = value;
        final className = _className;
        if (className != null) constants.values['$className.$name'] = value;
        continue;
      }
      if (initializer is ListLiteral) {
        constants.listDeclarations[name] = initializer;
        final className = _className;
        if (className != null) {
          constants.listDeclarations['$className.$name'] = initializer;
        }
      }
    }
  }
}

/// Collects the IDs named by a set of Zuke annotations in one file.
///
/// [idField] names the argument to read, so the same collector serves
/// `requirementIds` / `controlIds` list arguments and `ZukeBinding`'s single
/// `bindingId` string argument.
class AnnotationIdCollector extends RecursiveAstVisitor<void> {
  AnnotationIdCollector({
    required this.constants,
    required this.annotationNames,
    required this.idField,
    this.single = false,
  });

  final SourceConstants constants;
  final Set<String> annotationNames;
  final String idField;

  /// Whether [idField] holds one identifier rather than a list of them.
  final bool single;

  final Set<String> ids = {};

  @override
  void visitAnnotation(Annotation node) {
    final name = node.name.name;
    if (!annotationNames.contains(name)) {
      super.visitAnnotation(node);
      return;
    }
    final arguments = node.arguments?.arguments;
    if (arguments == null || arguments.isEmpty) {
      super.visitAnnotation(node);
      return;
    }
    // Prefer the named argument the annotation declares, so
    // `@ZukeBinding(bindingId: 'x')` reads the same as `@ZukeBinding('x')`.
    // Reading only the first positional argument silently ignores the named
    // form and reports nothing, which reads as a missing implementation.
    Expression? named;
    for (final argument in arguments) {
      if (argument is NamedExpression && argument.name.label.name == idField) {
        named = argument.expression;
        break;
      }
    }
    final target = named ?? arguments.first;
    if (single) {
      final value = constants.valueOf(target);
      if (value != null && value.isNotEmpty) ids.add(value);
    } else {
      ids.addAll(constants.idsForList(target));
    }
    super.visitAnnotation(node);
  }
}

/// Parses [file] and collects the IDs named by the given Zuke annotations.
///
/// A file that does not mention any of [annotationNames] is skipped without
/// parsing, which keeps the common case cheap.
Set<String> collectAnnotationIds(
  File file,
  SourceConstants constants, {
  required Set<String> annotationNames,
  required String idField,
  bool single = false,
}) {
  final content = file.readAsStringSync();
  if (!annotationNames.any((name) => content.contains(name))) return const {};
  try {
    final parsed = parseString(
      content: content,
      path: file.path,
      throwIfDiagnostics: false,
    );
    final collector = AnnotationIdCollector(
      constants: constants,
      annotationNames: annotationNames,
      idField: idField,
      single: single,
    );
    parsed.unit.accept(collector);
    return collector.ids;
  } on FormatException {
    return const {};
  } on FileSystemException {
    return const {};
  }
}

/// Every configured contract output directory, workspace-level first and then
/// any declared per target.
Iterable<String> contractOutputs(WorkspaceDiscoveryResult workspace) sync* {
  final workspaceLevel = workspace.config.contractOutput;
  if (workspaceLevel != null && workspaceLevel.isNotEmpty) {
    yield workspaceLevel;
  }
  for (final target in workspace.config.targetsConfig.values) {
    if (target is! Map) continue;
    final output = target['contractOutput'];
    if (output is String && output.trim().isNotEmpty) yield output;
  }
}

/// Every Dart file under the configured contract outputs.
///
/// Collected before the package roots because annotations reference the
/// constants these files declare.
Iterable<File> generatedContractFiles(
  String root,
  WorkspaceDiscoveryResult workspace,
) sync* {
  for (final contractOutput in contractOutputs(workspace)) {
    final outputDirectory = Directory(
      '$root${Platform.pathSeparator}'
      '${contractOutput.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!outputDirectory.existsSync()) continue;
    final files =
        outputDirectory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    yield* files;
  }
}

/// Every Dart source file under the configured package roots, in a stable
/// order so collected constants do not depend on directory iteration.
Iterable<File> packageDartFiles(
  String root,
  WorkspaceDiscoveryResult workspace,
) sync* {
  for (final target in workspace.config.workspaceTargets.values) {
    if (target.language != 'dart') continue;
    for (final package in target.packages) {
      final packageRoot = Directory(
        '$root${Platform.pathSeparator}'
        '${package.path.replaceAll('/', Platform.pathSeparator)}',
      );
      if (!packageRoot.existsSync()) continue;
      for (final relativeRoot in package.roots) {
        final directory = Directory(
          '${packageRoot.path}${Platform.pathSeparator}'
          '${relativeRoot.replaceAll('/', Platform.pathSeparator)}',
        );
        if (!directory.existsSync()) continue;
        final files =
            directory
                .listSync(recursive: true, followLinks: false)
                .whereType<File>()
                .where((file) => file.path.endsWith('.dart'))
                .toList()
              ..sort((left, right) => left.path.compareTo(right.path));
        yield* files;
      }
    }
  }
}

/// Whether [file] is generated rather than hand-maintained source.
///
/// Generated files declare identifiers; they never implement them, so a scan
/// for implementations must skip them or every requirement would look covered.
bool isGeneratedSource(File file) =>
    file.path.endsWith('.g.dart') || file.path.endsWith('.freezed.dart');
