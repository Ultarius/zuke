import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:zuke_cli/editor.dart';

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

/// Flags implemented or presented requirements that have no workspace
/// `@VerifiesRequirement` in the current generated index.
class ZukeMissingTestVisitor extends SimpleAstVisitor<void> {
  final ZukeIndex index;
  final AnnotationReporter report;

  ZukeMissingTestVisitor(this.index, this.report);

  @override
  void visitAnnotation(Annotation node) {
    final annotationName = zukeAnnotationName(node.elementAnnotation?.element);
    if (annotationName != 'ImplementsRequirement' &&
        annotationName != 'PresentsRequirement') {
      return;
    }
    final value = node.elementAnnotation?.computeConstantValue();
    if (value == null || !value.hasKnownValue) return;
    final ids = constantStrings(value, 'requirementIds') ?? const <String>[];
    final missing = ids.where(
      (id) =>
          index.requirementIds.contains(id) &&
          !index.verifiedRequirementIds.contains(id),
    );
    if (missing.isNotEmpty) report(node);
  }
}

/// Flags generated requirement-ID constants that no configured source
/// implements.
///
/// The existing `ZukeMissingTestRule` looks the other way round: it fires on an
/// implementation that has no test. This one fires on a contract that has no
/// implementation at all, which is otherwise invisible until `zuke validate`
/// reports a missing evidence slot. Both matter, and neither subsumes the
/// other, so they are separate rules with separate suppression comments.
class ZukeUnimplementedRequirementVisitor extends SimpleAstVisitor<void> {
  final ZukeIndex index;

  /// The target that owns the file being analyzed, or null when the index
  /// cannot attribute it to a configured package.
  final String? targetId;

  /// Emits the diagnostic for one requirement ID.
  final void Function(AstNode anchor, String requirementId) report;

  ZukeUnimplementedRequirementVisitor({
    required this.index,
    required this.targetId,
    required this.report,
  });

  /// The unresolved IDs for the target this file belongs to.
  Set<String> get unimplemented => index.unimplementedRequirementIds(targetId);

  /// IDs already reported in this file.
  ///
  /// A contract can spell the same requirement more than once — the generator
  /// emits a plain `name = 'RULE-…'` for a requirement and that same ID can also
  /// appear in an aggregate or alias constant — and reporting one requirement at
  /// every occurrence would bury the finding in duplicates. The first constant
  /// carrying the ID is the anchor.
  final Set<String> _reported = {};

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (!node.isStatic || !node.fields.isConst) return;
    for (final variable in node.fields.variables) {
      final initializer = variable.initializer;
      // Only a plain `static const name = 'RULE-…';` is reported. The
      // generator's `nameId = RuleId('RULE-…')` companion is a constructor
      // call, so it cannot match here.
      if (initializer is! StringLiteral) continue;
      final id = initializer.stringValue;
      if (id == null || id.isEmpty) continue;
      if (_reported.contains(id)) continue;
      if (!index.requirementIds.contains(id)) continue;
      if (index.implementedRequirementIds.contains(id)) continue;
      if (!index.appliesToTarget(id, targetId)) continue;
      _reported.add(id);
      report(variable, id);
    }
    super.visitFieldDeclaration(node);
  }
}

/// Reports the specification findings recorded in the index against the
/// contract generated from the feature that owns them.
///
/// An analysis-server plugin can only anchor a diagnostic on a Dart node, so a
/// finding about a `.feature` line cannot be reported *on* that line. It is
/// reported on the generated contract for the same feature and the
/// specification's own `file:line:column` is carried in the message, which is
/// what makes the finding actionable.
///
/// Every finding for a feature shares the contract's class declaration as its
/// anchor. That is deliberate: the alternative is inventing a generated
/// declaration per finding purely to give each one its own line, which trades a
/// cosmetic improvement for a generated file whose shape is load-bearing.
class ZukeSpecLintVisitor extends SimpleAstVisitor<void> {
  /// Findings for the features this file was generated from.
  final List<ZukeSpecDiagnostic> findings;

  /// Emits one diagnostic for one finding.
  final void Function(AstNode anchor, ZukeSpecDiagnostic finding) report;

  ZukeSpecLintVisitor({required this.findings, required this.report});

  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (findings.isEmpty) return;
    // Prefer the class declaration: it is the contract's own identity, and it
    // is a real line in the file rather than a byte offset at the top.
    AstNode? anchor;
    for (final declaration in node.declarations) {
      if (declaration is ClassDeclaration) {
        anchor = declaration;
        break;
      }
    }
    anchor ??= node.directives.isNotEmpty ? node.directives.first : node;
    for (final finding in findings) {
      report(anchor, finding);
    }
  }
}
