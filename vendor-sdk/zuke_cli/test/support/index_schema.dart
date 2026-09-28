import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Inspect serializer keys, including conditional fields not exercised by a
/// fixture. Dynamic dictionary keys are data, not schema.
Map<String, List<String>> indexSerializerKeys(Directory cli) {
  final result = <String, List<String>>{};
  for (final path in [
    'lib/src/tooling/dart_extractor/zuke_index.dart',
    'lib/src/implementation_claims.dart',
  ]) {
    final unit = parseString(
      content: File('${cli.path}/$path').readAsStringSync(),
    ).unit;
    for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
      for (final method
          in declaration.body.childEntities.whereType<MethodDeclaration>()) {
        if (method.name.lexeme != 'toJson') continue;
        final visitor = _Keys();
        method.body.accept(visitor);
        result[declaration.namePart.typeName.lexeme] = visitor.keys.toList()
          ..sort();
      }
    }
  }
  return {for (final name in result.keys.toList()..sort()) name: result[name]!};
}

class _Keys extends RecursiveAstVisitor<void> {
  final keys = <String>{};
  @override
  void visitMapLiteralEntry(MapLiteralEntry node) {
    final key = node.key;
    if (key is SimpleStringLiteral) keys.add(key.value);
    super.visitMapLiteralEntry(node);
  }
}
