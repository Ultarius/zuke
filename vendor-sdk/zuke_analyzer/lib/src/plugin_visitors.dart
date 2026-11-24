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

  /// The target that owns the file being analyzed, or null when the index
  /// cannot attribute it to a configured package.
  final String? targetId;

  ZukeMissingTestVisitor(this.index, this.report, {this.targetId});

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
    // Verification is target-scoped, so the flat set is not enough: a
    // requirement tested only by the backend package is still untested for a
    // Flutter file that implements it. Reading the claims keeps this in step
    // with `zuke validate`, which resolves the same rule.
    final missing = ids.where(
      (id) =>
          index.requirementIds.contains(id) &&
          !claimsSatisfyRequirement(index.verifiedClaims, id, targetId),
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
      // [unimplemented] is the target-aware definition, already folded together
      // with `appliesToTarget`. Testing the flat `implementedRequirementIds`
      // instead would skip a requirement that only some other target implements,
      // which is exactly the gap this rule exists to report.
      if (!unimplemented.contains(id)) continue;
      _reported.add(id);
      report(variable, id);
    }
    super.visitFieldDeclaration(node);
  }
}

/// Flags a managed test registration that publishes no evidence type.
///
/// `zukeTest` and `zukeTestWidgets` both throw an `ArgumentError` when
/// `evidenceTypes` is absent or empty, but only under a managed run. A plain
/// `dart test` therefore stays green, and the failure surfaces later as
/// "published no Zuke result artifacts" or an unmet evidence type -- far from the
/// line that caused it. This reports at the call site instead.
///
/// Deliberately per-call: it fires on a registration that would throw, and on
/// nothing else. It does not try to decide whether the requirement a scenario
/// names is covered, because that is a workspace-wide question and belongs in
/// the index.
class ZukeMissingEvidenceTypesVisitor extends SimpleAstVisitor<void> {
  final void Function(MethodInvocation node, bool declaresEmpty) report;

  ZukeMissingEvidenceTypesVisitor(this.report);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = zukeManagedEntrypointName(node.methodName.element);
    // `zukeUnit` supplies its own type, so it is never missing one.
    if (name != null && zukeEvidenceDeclaringEntrypoints.contains(name)) {
      final declaresTypes = declaresReadableEvidenceTypes(
        node.argumentList.arguments,
      );
      if (declaresTypes == null) {
        report(node, false);
      } else if (!declaresTypes) {
        report(node, true);
      }
    }
    super.visitMethodInvocation(node);
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

/// Reports rule/slot obligations that no managed registration satisfies.
///
/// **Why this needs the index rather than the file being analyzed.** A slot is
/// unbound only if *no* registration anywhere satisfies it, so the question is
/// about the whole workspace and cannot be answered by looking at one file. The
/// index carries the registrations for exactly this reason, and the verdict comes
/// from the same `BindingVerdictEngine` `zuke validate` uses, so the two cannot
/// disagree about whether a slot is bound.
///
/// **Why it must not run on a stale index.** A gap is a claim about absence, and
/// an absence read from a snapshot that predates an edit is not a fact. The
/// freshness gate on the rule means findings vanish while the index is behind
/// rather than accusing the workspace of a gap it has already closed — but the
/// consequence is that findings also *appear* only after `zuke generate`. This
/// rule never refreshes the index itself: doing that from an analysis callback
/// would mean a save writing to the workspace, which is not something a
/// diagnostic may do.
///
/// **What it does not decide.** A registration it credits as satisfying a slot
/// may call a service directly and never perform the user's action. So this
/// reports that a matching test *exists*, never that the promised behaviour ran.
/// Deciding that needs the entry point observed at runtime.
///
/// **One owner per finding.** Each finding is anchored on the generated constant
/// for its own rule, and only in the contract generated from that rule's feature.
/// A contract that aliases the same rule ID must not produce a second copy.
class ZukeBindingCoverageVisitor extends SimpleAstVisitor<void> {
  /// Unbound findings, already restricted to the features this file owns.
  final List<BindingCoverageFinding> findings;

  /// Emits one diagnostic for one finding.
  final void Function(AstNode anchor, BindingCoverageFinding finding) report;

  /// Findings already emitted, keyed by rule and slot.
  ///
  /// A generated contract can spell the same rule more than once, so without this
  /// a rule with two unbound slots would report each at every occurrence.
  final Set<String> _reported = {};

  ZukeBindingCoverageVisitor({required this.findings, required this.report});

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (!node.isStatic || !node.fields.isConst) return;
    for (final variable in node.fields.variables) {
      final initializer = variable.initializer;
      // Only a plain `static const name = 'RULE-…';` is an anchor. The
      // generator's `nameId = RuleId('RULE-…')` companion is a constructor call,
      // so it cannot match here.
      if (initializer is! StringLiteral) continue;
      final ruleId = initializer.stringValue;
      if (ruleId == null || ruleId.isEmpty) continue;
      for (final finding in findings) {
        if (finding.ruleId != ruleId) continue;
        // The slot is part of the key: a rule may leave two slots unbound, and
        // they are two separate obligations.
        if (!_reported.add('${finding.ruleId}|${finding.slotKey}')) continue;
        report(variable, finding);
      }
    }
    super.visitFieldDeclaration(node);
  }
}
