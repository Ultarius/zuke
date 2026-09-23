import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

/// Requirement IDs declared by `@VerifiesRequirement` plus the source files
/// that contributed them, so generate can index verification coverage and
/// invalidate the index when those sources change.
final class VerifiedRequirementScan {
  final Set<String> requirementIds;
  final List<String> sourcePaths;

  const VerifiedRequirementScan({
    required this.requirementIds,
    required this.sourcePaths,
  });
}

VerifiedRequirementScan scanVerifiedRequirements(
  String root,
  WorkspaceDiscoveryResult workspace,
) {
  final requirementIds = <String>{};
  final sourcePaths = <String>{};
  final constValues = <String, String>{};
  final annotationFiles = <File>[];
  final contractOutputs = <String>{
    if (workspace.config.contractOutput?.isNotEmpty ?? false)
      workspace.config.contractOutput!,
  };
  for (final target in workspace.config.targetsConfig.values) {
    if (target is! Map) continue;
    final output = target['contractOutput'];
    if (output is String && output.trim().isNotEmpty) {
      contractOutputs.add(output);
    }
  }
  for (final contractOutput in contractOutputs) {
    final outputDirectory = Directory(
      '$root${Platform.pathSeparator}'
      '${contractOutput.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!outputDirectory.existsSync()) continue;
    for (final file
        in outputDirectory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      _collectStaticConstStrings(file, constValues);
    }
  }
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
        for (final file in files) {
          if (!file.path.endsWith('.g.dart') &&
              !file.path.endsWith('.freezed.dart')) {
            annotationFiles.add(file);
          }
          _collectStaticConstStrings(file, constValues);
        }
      }
    }
  }
  for (final file in annotationFiles) {
    final ids = _verifiedIdsIn(file, constValues);
    if (ids.isEmpty) continue;
    requirementIds.addAll(ids);
    sourcePaths.add(file.absolute.path);
  }
  return VerifiedRequirementScan(
    requirementIds: requirementIds,
    sourcePaths: sourcePaths.toList()..sort(),
  );
}

void _collectStaticConstStrings(File file, Map<String, String> values) {
  final content = file.readAsStringSync();
  if (!content.contains('static const')) return;
  try {
    final parsed = parseString(
      content: content,
      path: file.path,
      throwIfDiagnostics: false,
    );
    parsed.unit.accept(_StaticConstCollector(values));
  } on FormatException {
    return;
  } on FileSystemException {
    return;
  }
}

class _StaticConstCollector extends RecursiveAstVisitor<void> {
  _StaticConstCollector(this.values);

  final Map<String, String> values;
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
  void visitFieldDeclaration(FieldDeclaration node) {
    if (!node.isStatic || !node.fields.isConst) return;
    for (final variable in node.fields.variables) {
      final initializer = variable.initializer;
      if (initializer is! StringLiteral) continue;
      final value = initializer.stringValue;
      if (value == null || value.isEmpty) continue;
      final name = variable.name.lexeme;
      values[name] = value;
      final className = _className;
      if (className != null) values['$className.$name'] = value;
    }
  }
}

Set<String> _verifiedIdsIn(File file, Map<String, String> constValues) {
  final content = file.readAsStringSync();
  if (!content.contains('VerifiesRequirement')) return const {};
  try {
    final parsed = parseString(
      content: content,
      path: file.path,
      throwIfDiagnostics: false,
    );
    final collector = _VerifiesRequirementCollector(constValues);
    parsed.unit.accept(collector);
    return collector.requirementIds;
  } on FormatException {
    return const {};
  } on FileSystemException {
    return const {};
  }
}

class _VerifiesRequirementCollector extends RecursiveAstVisitor<void> {
  _VerifiesRequirementCollector(this.constValues);

  final Map<String, String> constValues;
  final Set<String> requirementIds = {};

  @override
  void visitAnnotation(Annotation node) {
    final name = node.name.name;
    if (name != 'VerifiesRequirement') return;
    final arguments = node.arguments?.arguments;
    if (arguments == null || arguments.isEmpty) return;
    final first = arguments.first;
    if (first is! ListLiteral) return;
    for (final element in first.elements) {
      if (element is! Expression) continue;
      final value = _idOf(element);
      if (value != null && value.isNotEmpty) requirementIds.add(value);
    }
  }

  String? _idOf(Expression element) {
    if (element is StringLiteral) return element.stringValue;
    if (element is PrefixedIdentifier) {
      final key = '${element.prefix.name}.${element.identifier.name}';
      return constValues[key] ?? constValues[element.identifier.name];
    }
    if (element is SimpleIdentifier) return constValues[element.name];
    return null;
  }
}
