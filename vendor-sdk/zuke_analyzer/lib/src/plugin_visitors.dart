import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:zuke_cli/tooling.dart';

typedef AnnotationReporter = void Function(Annotation annotation);

/// Shared, resolved-AST validation used by the analyzer rule and its parity
/// tests. This is internal implementation code, not a public extension API.
class ZukeAnnotationVisitor extends SimpleAstVisitor<void> {
  final AnnotationReporter report;

  ZukeAnnotationVisitor(this.report);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _check(node.metadata, 'class');
    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _check(node.metadata, 'mixin');
    super.visitMixinDeclaration(node);
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    _check(node.metadata, 'extensionType');
    super.visitExtensionTypeDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _check(node.metadata, 'function');
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _check(node.metadata, node.isGetter ? 'getter' : 'method');
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    _check(node.metadata, 'field');
    super.visitFieldDeclaration(node);
  }

  void _check(NodeList<Annotation> metadata, String target) {
    for (final annotation in metadata) {
      final annotationName = zukeAnnotationName(
        annotation.elementAnnotation?.element,
      );
      if (annotationName == null) continue;
      final value = annotation.elementAnnotation?.computeConstantValue();
      if (value == null || !value.hasKnownValue) {
        report(annotation);
        continue;
      }
      if (!supportsZukeAnnotationTarget(annotationName, target)) {
        report(annotation);
        continue;
      }
      final identifierField = zukeAnnotationIdentifierField(annotationName);
      final valid = identifierField == 'bindingId'
          ? (constantString(value, identifierField)?.isNotEmpty ?? false)
          : (constantStrings(value, identifierField)?.isNotEmpty ?? false);
      if (!valid) report(annotation);
    }
  }
}

String zukeAnnotationIdentifierField(String annotationName) =>
    switch (annotationName) {
      'ProvidesControl' => 'controlIds',
      'ZukeBinding' => 'bindingId',
      _ => 'requirementIds',
    };

/// Checks resolved annotation constants against a current generated index.
class ZukeUnknownIdVisitor extends SimpleAstVisitor<void> {
  final ZukeIndex index;
  final AnnotationReporter report;

  ZukeUnknownIdVisitor(this.index, this.report);

  @override
  void visitAnnotation(Annotation node) {
    final annotationName = zukeAnnotationName(node.elementAnnotation?.element);
    final value = node.elementAnnotation?.computeConstantValue();
    if (annotationName == null || value == null || !value.hasKnownValue) return;
    final field = zukeAnnotationIdentifierField(annotationName);
    final unknown = field == 'bindingId'
        ? (() {
            final id = constantString(value, field);
            return id != null && !index.bindingIds.contains(id);
          })()
        : field == 'controlIds'
        ? (constantStrings(value, field) ?? const <String>[]).any(
            (id) => !index.controlIds.contains(id),
          )
        : (constantStrings(value, field) ?? const <String>[]).any(
            (id) => !index.requirementIds.contains(id),
          );
    if (unknown) report(node);
  }
}
