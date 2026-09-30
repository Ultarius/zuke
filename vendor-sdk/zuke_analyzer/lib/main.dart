import 'dart:io';

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:zuke_cli/editor.dart';

import 'src/plugin_visitors.dart';

final plugin = ZukePlugin();

class ZukePlugin extends Plugin {
  @override
  String get name => 'zuke';

  @override
  void register(PluginRegistry registry) {
    // A newly introduced guard must work with existing lint configurations.
    // Warning-rule registration enables it by default; the code severity is ERROR.
    registry.registerWarningRule(ZukePluginStaleRule());
    registry.registerLintRule(ZukeAnnotationRule());
    // Warning-registered so a workspace that has never regenerated is told about
    // it by default. The severity lives on the code: drift is a warning because
    // ordinary editing causes it, an unusable index is an error.
    registry.registerWarningRule(ZukeIndexStaleRule());
    registry.registerWarningRule(ZukeIndexUnusableRule());
    registry.registerLintRule(ZukeUnknownIndexIdRule());
    registry.registerLintRule(ZukeMissingTestRule());
    registry.registerLintRule(ZukeMissingEvidenceTypesRule());
    registry.registerLintRule(ZukeUnimplementedRequirementRule());
    registry.registerLintRule(ZukeSpecLintRule());
  }
}

class ZukePluginStaleRule extends AnalysisRule {
  static const code = LintCode(
    'zuke_plugin_stale',
    '{0}',
    uniqueName: 'LintCode.zuke_plugin_stale',
    severity: DiagnosticSeverity.ERROR,
  );

  ZukePluginStaleRule()
    : super(
        name: 'zuke_plugin_stale',
        description: 'Rejects incompatible analyzer and index contracts',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final path = context.definingUnit.file.path;
    final message = _pluginStaleMessageFor(path);
    if (message == null) return;
    registry.addCompilationUnit(this, _PluginStaleVisitor(this, message));
  }
}

class _PluginStaleVisitor extends SimpleAstVisitor<void> {
  final ZukePluginStaleRule rule;
  final String message;
  _PluginStaleVisitor(this.rule, this.message);

  @override
  void visitCompilationUnit(CompilationUnit node) =>
      rule.reportAtNode(_diagnosticAnchor(node), arguments: [message]);
}

String? zukePluginStaleMessageForTesting(String path) =>
    _pluginStaleMessageFor(path);

String? _pluginStaleMessageFor(String path) {
  final state = _indexStateFor(path);
  if (!state.incompatible) return null;
  final anchor = state.header!.diagnosticAnchor(state.workspaceRoot!);
  if (anchor == null ||
      ZukeIndex.relativeToRoot(state.workspaceRoot!, anchor) !=
          ZukeIndex.relativeToRoot(state.workspaceRoot!, path)) {
    return null;
  }
  return state.header!.mismatchMessage;
}

/// Shared placement logic for the two index-freshness notices.
///
/// One rule can only carry one [DiagnosticCode], so drift and an unusable index
/// are reported by separate rules over this base.
abstract class _ZukeIndexFreshnessRule extends AnalysisRule {
  _ZukeIndexFreshnessRule({required super.name, required super.description});

  /// Whether this rule reports [state], which decides both whether a notice is
  /// warranted and which single file carries it.
  bool appliesTo(ZukePluginIndexState state);

  /// The wording for [state], distinguishing the cause from the effect.
  String messageFor(ZukePluginIndexState state);

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final path = context.definingUnit.file.path;
    final state = _indexStateFor(path);
    // Only Zuke workspaces (zuke.yaml present) own index freshness. Files
    // outside a workspace are not stale—they are not governed by Zuke.
    if (!state.hasWorkspace || state.isCurrent || state.incompatible) return;
    if (!appliesTo(state)) return;
    if (_ownsStalenessNotice(state, path)) {
      registry.addCompilationUnit(this, _FreshnessVisitor(this, state));
    }
  }

  /// Whether the file being analyzed is the one that should carry this notice.
  ///
  /// Staleness belongs to the workspace, but a plugin can only report on a
  /// compilation unit it is analyzing. Reporting on every one put an identical
  /// diagnostic at line 1 of every open file, which is how a single stale index
  /// became a wall of red on startup. Prefer the Dart file whose drift caused
  /// it, so the notice stays attached to something actionable and appears once.
  ///
  /// The owner is selected once when loading the workspace state: an existing
  /// Dart issue path, then the recorded anchor, then a workspace source file.
  /// Comparing against that one owner prevents the anchor, changed sources and
  /// fallback from each reporting the same workspace problem.
  static bool _ownsStalenessNotice(
    ZukePluginIndexState state,
    String analyzedPath,
  ) {
    final root = state.workspaceRoot;
    if (root == null) return true;
    final owner = state.noticeOwner;
    return owner != null && isSameWorkspacePath(root, owner, analyzedPath);
  }

  /// One sentence naming the cause, folding in how many others there were.
  static String describe(List<ZukeIndexFreshnessIssue> issues, String cause) {
    final first = issues.first.message;
    final extra = issues.length - 1;
    return extra > 0
        ? '$cause. $first (+$extra more; run zuke doctor for the full list)'
        : '$cause. $first';
  }
}

/// The index is a faithful snapshot and the workspace has simply moved past it.
///
/// Ordinary editing produces exactly this, so it is a warning rather than an
/// error. An error here put a red squiggle on every open file for the whole of a
/// normal editing session, which is a cost with no corresponding signal.
class ZukeIndexStaleRule extends _ZukeIndexFreshnessRule {
  static const code = LintCode(
    'zuke_index_stale',
    '{0}',
    uniqueName: 'LintCode.zuke_index_stale',
    severity: DiagnosticSeverity.WARNING,
  );

  ZukeIndexStaleRule()
    : super(
        name: 'zuke_index_stale',
        description: 'Warns that the Zuke index is behind the sources.',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  bool appliesTo(ZukePluginIndexState state) => !state.unusable;

  @override
  String messageFor(ZukePluginIndexState state) =>
      _ZukeIndexFreshnessRule.describe(
        state.issues,
        'The Zuke analyzer index is behind the sources',
      );
}

/// The index cannot answer correctly at all: an incompatible contract, or
/// missing or edited generated output.
///
/// Kept an error because no edit resolves it. The plugin is being asked about
/// facts it does not have, and only regenerating supplies them.
class ZukeIndexUnusableRule extends _ZukeIndexFreshnessRule {
  static const code = LintCode(
    'zuke_index_unusable',
    '{0}',
    uniqueName: 'LintCode.zuke_index_unusable',
    severity: DiagnosticSeverity.ERROR,
  );

  ZukeIndexUnusableRule()
    : super(
        name: 'zuke_index_unusable',
        description: 'Reports a Zuke index that cannot answer correctly.',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  bool appliesTo(ZukePluginIndexState state) => state.unusable;

  @override
  String messageFor(ZukePluginIndexState state) =>
      _ZukeIndexFreshnessRule.describe(
        state.issues,
        'The Zuke analyzer index cannot answer correctly',
      );
}

class _FreshnessVisitor extends SimpleAstVisitor<void> {
  final _ZukeIndexFreshnessRule rule;
  final ZukePluginIndexState state;
  _FreshnessVisitor(this.rule, this.state);

  @override
  void visitCompilationUnit(CompilationUnit node) {
    rule.reportAtNode(
      _diagnosticAnchor(node),
      arguments: [rule.messageFor(state)],
    );
  }
}

/// Give both workspace-wide diagnostics one short, stable source location.
AstNode _diagnosticAnchor(CompilationUnit node) => node.directives.isNotEmpty
    ? node.directives.first
    : node.declarations.isNotEmpty
    ? node.declarations.first
    : node;

class ZukeUnknownIndexIdRule extends AnalysisRule {
  static const code = LintCode(
    'zuke_unknown_index_id',
    'ZUKE-INDEX-UNKNOWN-ID: Annotation references an ID absent from the current index.',
    uniqueName: 'LintCode.zuke_unknown_index_id',
    severity: DiagnosticSeverity.ERROR,
  );

  ZukeUnknownIndexIdRule()
    : super(
        name: 'zuke_unknown_index_id',
        description: 'Checks annotation IDs against the current Zuke index',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    // Only reads requirement, control and binding IDs, all of which come from
    // the specifications. Editing Dart cannot change them, so this rule keeps
    // working while a workspace is edited.
    final index = _indexStateFor(
      context.definingUnit.file.path,
    ).indexFor(_needsSpecificationFacts);
    if (index != null) {
      registry.addAnnotation(this, ZukeUnknownIdVisitor(index, reportAtNode));
    }
  }
}

class ZukeMissingEvidenceTypesRule extends AnalysisRule {
  static const code = LintCode(
    'zuke_missing_evidence_types',
    'ZUKE-MISSING-EVIDENCE-TYPES: {0}',
    uniqueName: 'LintCode.zuke_missing_evidence_types',
    severity: DiagnosticSeverity.WARNING,
  );

  ZukeMissingEvidenceTypesRule()
    : super(
        name: 'zuke_missing_evidence_types',
        description:
            'Requires a managed test to declare which evidence types it publishes',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    // Needs no index payload, but does need a managed workspace with a
    // compatible contract; a mismatch must suppress every other Zuke rule.
    //
    // The rule reports a registration that would throw *under a managed run*, so
    // outside one it is noise: a `zukeTest` in a plain `dart test` suite is a
    // legitimate unit test, and the framework's own test suite is exactly that.
    // A managed registration cannot exist outside a workspace either, because
    // the scenario contract it names is generated into one.
    //
    // This also means the diagnostic cannot be silenced where it is wrong: an
    // analysis-server plugin diagnostic does not honour `// ignore:` here, so
    // the workspace test is the only available guard.
    if (!_missingEvidenceTypesApplies(context.definingUnit.file.path)) return;
    registry.addMethodInvocation(
      this,
      ZukeMissingEvidenceTypesVisitor((node, declaresEmpty) {
        reportAtNode(
          node,
          arguments: [
            declaresEmpty
                ? 'This managed test declares an empty evidenceTypes list, so it '
                      'publishes no evidence. `zuke test` fails with an '
                      "ArgumentError, and a requirement it was meant to verify is "
                      'left unevidenced.'
                : 'This managed test does not declare evidenceTypes. `zuke test` '
                      'fails with an ArgumentError because a managed test must '
                      'publish at least one evidence type; a plain test() run '
                      'stays green and the requirement is left unevidenced.',
          ],
        );
      }),
    );
  }
}

class ZukeMissingTestRule extends AnalysisRule {
  static const code = LintCode(
    'zuke_missing_test',
    'ZUKE-MISSING-TEST: Implemented requirement has no @VerifiesRequirement in the current index.',
    uniqueName: 'LintCode.zuke_missing_test',
    severity: DiagnosticSeverity.WARNING,
  );

  ZukeMissingTestRule()
    : super(
        name: 'zuke_missing_test',
        description:
            'Requires a workspace @VerifiesRequirement for implemented requirements',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final path = context.definingUnit.file.path;
    final state = _indexStateFor(path);
    // Reconciles source-derived verification claims against specification IDs,
    // so either kind of drift leaves this check unable to answer.
    final index = state.indexFor(_needsSpecificationAndSourceFacts);
    if (index != null) {
      // Verification is target-scoped, so the rule has to know which target
      // owns the implementation being judged. An unattributable file resolves
      // to null, which the claim rule treats as "satisfies every target", so
      // missing scoping metadata under-reports rather than inventing a gap.
      final root = state.workspaceRoot;
      final relative = root == null
          ? null
          : ZukeIndex.relativeToRoot(root, path);
      registry.addAnnotation(
        this,
        ZukeMissingTestVisitor(
          index,
          reportAtNode,
          targetId: relative == null ? null : index.targetForPath(relative),
        ),
      );
    }
  }
}

/// The Zuke index state for the workspace owning a file, as resolved by the
/// plugin. Public because the freshness rules expose it in their signatures.
class ZukePluginIndexState {
  final ZukeIndex? index;
  final bool hasWorkspace;
  final ZukeIndexHeader? header;

  /// Why the index is not usable, empty when it is current or when the file
  /// belongs to no Zuke workspace.
  final List<ZukeIndexFreshnessIssue> issues;

  /// A workspace-relative Dart file the index nominated for reporting, or null.
  /// Recorded when the index was generated so every analysis session picks the
  /// same anchor rather than whichever file happened to be visited first.
  final String? anchor;

  /// The single workspace-relative file carrying the freshness notice, or null
  /// when the index is current or the workspace has no existing Dart source.
  final String? noticeOwner;

  bool get incompatible => header?.isIncompatible ?? false;

  /// Whether the index cannot answer correctly, as opposed to merely describing
  /// sources that have moved on. Ordinary editing produces drift and must not be
  /// reported as an error.
  bool get unusable => issues.any((issue) => issue.rendersIndexUnusable);

  /// Whether the index may be used at all. Only an unusable index refuses this.
  ///
  /// Which *facts* survive a drift is answered by
  /// `issues.consultableFacts`, shared with the standalone analyzer so the two
  /// cannot drift apart on this policy.
  bool get consultable => index != null && !incompatible && !unusable;

  /// The index for a rule that needs [fresh], or null when it is not.
  ///
  /// Each rule states which facts it depends on rather than demanding a wholly
  /// current index. That is the whole point of the split: a rule reading
  /// specification IDs keeps working while a workspace is edited, and only a
  /// rule reading claims or implementation sets waits for regeneration.
  ZukeIndex? indexFor(bool Function(ZukePluginIndexState state) fresh) =>
      fresh(this) ? index : null;

  /// The directory holding the `zuke.yaml` this index came from, so a caller
  /// can express an analyzed path relative to the workspace without walking the
  /// tree a second time.
  final String? workspaceRoot;
  const ZukePluginIndexState(
    this.index, {
    required this.hasWorkspace,
    this.workspaceRoot,
    this.header,
    this.issues = const [],
    this.anchor,
    this.noticeOwner,
  });
  bool get isCurrent => index != null && issues.isEmpty;
}

/// Whether a rule needs specification-derived facts only: IDs and spec findings,
/// which editing Dart cannot change.
bool _needsSpecificationFacts(ZukePluginIndexState state) => state.issues
    .consultableFacts(indexReadable: state.consultable)
    .specification;

/// Whether a rule needs source-derived facts: verified claims and implementation
/// sets, which are computed from the Dart that editing has just changed.
bool _needsSourceFacts(ZukePluginIndexState state) =>
    state.issues.consultableFacts(indexReadable: state.consultable).sources;

/// Checks that reconcile claims against declared requirements need both.
bool _needsSpecificationAndSourceFacts(ZukePluginIndexState state) {
  final facts = state.issues.consultableFacts(indexReadable: state.consultable);
  return facts.specification && facts.sources;
}

/// Reports requirement IDs that a generated contract declares but no configured
/// source implements.
///
/// Warning by default, not error: a workspace that is mid-authoring its
/// specifications would otherwise be red on every `dart analyze` before a line
/// of implementation exists, which trains people to ignore the rule. A project
/// that wants the stricter gate sets it to `error` in `analysis_options.yaml`,
/// where it composes with `--fatal-infos` in CI.
///
/// This diagnostic cannot be silenced per line. An earlier version of this
/// comment claimed `// ignore: zuke/zuke_unimplemented_requirement` worked; it
/// does not. Neither `// ignore:` nor `// ignore_for_file:` suppresses a
/// diagnostic produced by an analysis-server plugin in this configuration, and
/// the bare code name is no better. The only supported relief is the
/// `diagnostics:` map in `analysis_options.yaml`, which is per workspace. Treat
/// any single-diagnostic escape hatch here as unproven until it is tested.
class ZukeUnimplementedRequirementRule extends AnalysisRule {
  static const code = LintCode(
    'zuke_unimplemented_requirement',
    'ZUKE-UNIMPLEMENTED-REQUIREMENT: Requirement {0} is unimplemented{1}; '
        'add @ImplementsRequirement or @PresentsRequirement, or narrow the '
        'requirement\'s declared targets.',
    uniqueName: 'LintCode.zuke_unimplemented_requirement',
    severity: DiagnosticSeverity.WARNING,
  );

  ZukeUnimplementedRequirementRule()
    : super(
        name: 'zuke_unimplemented_requirement',
        description:
            'Requires an implementation for every generated requirement ID',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final path = context.definingUnit.file.path;
    final state = _indexStateFor(path);
    // Reconciles source-derived implementation claims against specification
    // requirements and target scopes, so both families must be current.
    final index = state.indexFor(_needsSpecificationAndSourceFacts);
    if (index == null) return;
    // Only generated contracts declare requirement IDs. Hand-written code is
    // free to declare its own constants, and a specification that has not been
    // generated yet is reported by ZukeIndexStaleRule instead.
    if (!path.replaceAll('\\', '/').endsWith('_contracts.g.dart')) return;
    final root = state.workspaceRoot;
    if (root == null) return;
    // Guarded: a path that is not under the workspace root must not be sliced
    // as if it were, or the file is attributed to whatever target the mangled
    // remainder happens to match.
    final relative = ZukeIndex.relativeToRoot(root, path);
    if (relative == null) return;
    final targetId = index.targetForPath(relative);
    final visitor = ZukeUnimplementedRequirementVisitor(
      index: index,
      targetId: targetId,
      report: (anchor, requirementId) => reportAtNode(
        anchor,
        arguments: [
          requirementId,
          // Two different facts must not read as one. With a target, name it.
          // Without one, say *why*: the generated contract can sit outside
          // every configured package -- a shared contracts package belonging to
          // no single target is the ordinary case -- and then the requirement's
          // own scoping is irrelevant, because the file cannot be attributed
          // to anything. "declared for no target" was read as a statement about
          // the requirement's targets when it is a statement about this file.
          //
          // The clause states the cause only. The template already carries the
          // remedy, and restating it here printed the advice twice.
          targetId != null
              ? ' for target $targetId'
              : ', and this contract is outside every configured package so it '
                    'belongs to no target',
        ],
      ),
    );
    if (visitor.unimplemented.isEmpty) return;
    registry.addFieldDeclaration(this, visitor);
  }
}

/// Reports specification findings recorded in the index.
///
/// The reference resolver finds them and `zuke generate` records them; this rule
/// is what makes them visible while editing. Without it a broken cross-reference
/// in a `.feature` file is only discovered by running the CLI.
///
/// The squiggle lands on the generated contract for the feature that owns the
/// finding, because a plugin can only anchor on a Dart node. The
/// specification's own path, line, and column are in the message.
///
/// One rule serves every finding, so its severity is fixed at
/// [DiagnosticSeverity.ERROR] and a finding's own severity cannot change the
/// colour it renders. Today that is exact: the reference resolver emits errors
/// and nothing else. If it ever emits a warning, that finding would render red
/// here — the message says `(warning)`, so it is not misreported, only louder
/// than it should be. Splitting this into one rule per severity is the fix, and
/// it is deliberately not done for a case that cannot occur yet.
class ZukeSpecLintRule extends AnalysisRule {
  static const code = LintCode(
    'zuke_spec_lint',
    'ZUKE-SPEC-LINT: {0} ({1})',
    uniqueName: 'LintCode.zuke_spec_lint',
    severity: DiagnosticSeverity.ERROR,
  );

  ZukeSpecLintRule()
    : super(
        name: 'zuke_spec_lint',
        description: 'Reports specification findings on the generated contract',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final path = context.definingUnit.file.path;
    final state = _indexStateFor(path);
    // Reads spec findings, which come from the specifications. Editing Dart
    // cannot invalidate them, so spec-lint keeps reporting while a workspace is
    // edited — which is most of its value, since that is when it is read.
    final index = state.indexFor(_needsSpecificationFacts);
    if (index == null) return;
    if (index.specDiagnostics.isEmpty) return;
    final root = state.workspaceRoot;
    if (root == null) return;
    final relative = ZukeIndex.relativeToRoot(root, path);
    if (relative == null) return;
    // Only the file generated from the offending feature reports it, so one
    // finding appears once rather than in every contract in the workspace.
    final features = index.featuresAtPath(relative);
    if (features.isEmpty) return;
    final findings = index.specDiagnostics
        .where(
          (finding) =>
              finding.featureId != null && features.contains(finding.featureId),
        )
        .toList(growable: false);
    if (findings.isEmpty) return;
    registry.addCompilationUnit(
      this,
      ZukeSpecLintVisitor(
        findings: findings,
        report: (anchor, finding) => reportAtNode(
          anchor,
          arguments: [
            finding.severity == 'error'
                ? finding.message
                : '${finding.message} (${finding.severity})',
            finding.location,
          ],
        ),
      ),
    );
  }
}

/// Internal test seam for the workspace/index discovery used by analyzer
/// callbacks, which otherwise only run inside the analysis server process.
bool zukeIndexIsCurrentForTesting(String? sourcePath) =>
    _indexStateFor(sourcePath).isCurrent;

/// Whether [ZukeIndexStaleRule] would register a visitor for [sourcePath]:
/// a Zuke workspace was found and its index is missing, malformed, or stale.
bool zukeIndexStaleAppliesForTesting(String? sourcePath) {
  final state = _indexStateFor(sourcePath);
  return state.hasWorkspace && !state.isCurrent && !state.incompatible;
}

/// Whether a rule needing specification-derived facts would run for [sourcePath].
bool zukeSpecificationFactsAvailableForTesting(String? sourcePath) =>
    _indexStateFor(sourcePath).indexFor(_needsSpecificationFacts) != null;

/// Whether a rule needing source-derived facts would run for [sourcePath].
bool zukeSourceFactsAvailableForTesting(String? sourcePath) =>
    _indexStateFor(sourcePath).indexFor(_needsSourceFacts) != null;

/// Whether [ZukeIndexUnusableRule] would register a visitor for [sourcePath]:
/// the index cannot answer correctly, and this file owns the notice.
bool zukeIndexUnusableAppliesForTesting(String? sourcePath) {
  final state = _indexStateFor(sourcePath);
  if (!state.hasWorkspace || state.isCurrent || state.incompatible) {
    return false;
  }
  return state.unusable &&
      _ZukeIndexFreshnessRule._ownsStalenessNotice(state, sourcePath ?? '');
}

/// Whether [ZukeMissingEvidenceTypesRule] would register a visitor for
/// [sourcePath]: the file is inside a Zuke workspace.
///
/// Outside one, a `zukeTest` is an ordinary unit-test helper and the managed
/// `ArgumentError` is unreachable, so reporting it there is noise the developer
/// cannot silence -- an analysis-server plugin diagnostic does not honour
/// `// ignore:`. This is the guard that keeps the framework's own `zuke_runner`
/// suite clean.
bool zukeMissingEvidenceTypesAppliesForTesting(String? sourcePath) =>
    _missingEvidenceTypesApplies(sourcePath);

bool _missingEvidenceTypesApplies(String? sourcePath) {
  final state = _indexStateFor(sourcePath);
  return state.hasWorkspace && !state.incompatible;
}

/// Clears process-local index state between isolated analyzer tests.
void zukeClearIndexCacheForTesting() => _indexCache.clear();

class _IndexCacheEntry {
  final DateTime lastChecked;
  final DateTime? fileModified;
  final ZukePluginIndexState state;
  const _IndexCacheEntry(this.lastChecked, this.fileModified, this.state);
}

final _indexCache = <String, _IndexCacheEntry>{};

ZukePluginIndexState _indexStateFor(String? sourcePath) {
  if (sourcePath == null) {
    return const ZukePluginIndexState(null, hasWorkspace: false);
  }
  var directory = File(sourcePath).parent.absolute;
  while (true) {
    final zukeYaml = File(
      '${directory.path}${Platform.pathSeparator}zuke.yaml',
    );
    if (zukeYaml.existsSync()) {
      final indexFile = File(
        '${directory.path}${Platform.pathSeparator}.zuke${Platform.pathSeparator}analyzer-index.json',
      );
      final key = directory.path;
      final now = DateTime.now();
      final indexExists = indexFile.existsSync();
      final modified = indexExists ? indexFile.lastModifiedSync() : null;

      final cached = _indexCache[key];
      if (cached != null &&
          now.difference(cached.lastChecked) < const Duration(seconds: 2) &&
          cached.fileModified == modified) {
        return cached.state;
      }

      try {
        final header = ZukeIndexHeader.read(indexFile);
        if (header.isIncompatible) {
          final state = ZukePluginIndexState(
            null,
            hasWorkspace: true,
            workspaceRoot: directory.path,
            header: header,
          );
          _indexCache[key] = _IndexCacheEntry(now, modified, state);
          return state;
        }
        final index = ZukeIndex.fromJson(header.json);
        // Read the issues rather than only asking whether there are any. The
        // plugin has to tell drift from an unusable index to choose a severity,
        // and it needs the recorded anchor to report once instead of once per
        // analyzed file. `workspaceRoot` was dropped on the stale branch, so a
        // stale state could not even name its own workspace.
        final issues = index.freshnessIssues(root: directory.path);
        // The parsed index is kept even when stale. A drift leaves most of it
        // true, and discarding it wholesale is what suppressed every rule for a
        // whole editing session. `isCurrent` stays false, so anything requiring
        // a wholly current index still waits.
        final state = ZukePluginIndexState(
          index,
          hasWorkspace: true,
          workspaceRoot: directory.path,
          issues: List.unmodifiable(issues),
          anchor: index.diagnosticAnchor,
          noticeOwner: _freshnessOwnerFor(directory.path, issues, header),
        );
        _indexCache[key] = _IndexCacheEntry(now, modified, state);
        return state;
      } catch (error) {
        final state = ZukePluginIndexState(
          null,
          hasWorkspace: true,
          workspaceRoot: directory.path,
          issues: [
            ZukeIndexFreshnessIssue(
              kind: ZukeIndexFreshnessIssueKind.contractMismatch,
              path: '.zuke/analyzer-index.json',
              message: 'Analyzer index could not be read: $error',
            ),
          ],
          noticeOwner: _freshnessOwnerFor(directory.path, const [], null),
        );
        _indexCache[key] = _IndexCacheEntry(now, modified, state);
        return state;
      }
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      return const ZukePluginIndexState(null, hasWorkspace: false);
    }
    directory = parent;
  }
}

/// Prefer a changed Dart source; otherwise reuse the header's stable anchor
/// discovery, which also works when the index is missing or unparseable.
String? _freshnessOwnerFor(
  String root,
  List<ZukeIndexFreshnessIssue> issues,
  ZukeIndexHeader? header,
) {
  if (header != null && issues.isEmpty) return null;
  final candidates =
      issues
          .where((issue) => issue.path.toLowerCase().endsWith('.dart'))
          .map((issue) => issue.path)
          .toSet()
          .toList()
        ..sort();
  for (final candidate in candidates) {
    final path = '$root${Platform.pathSeparator}$candidate';
    if (File(path).existsSync()) return candidate;
  }
  final owner = (header ?? ZukeIndexHeader(const {})).diagnosticAnchor(root);
  return owner == null ? null : ZukeIndex.relativeToRoot(root, owner);
}

class ZukeAnnotationRule extends AnalysisRule {
  static const code = LintCode(
    'zuke_annotation',
    'Zuke annotations require supported targets and constant identifiers',
    uniqueName: 'LintCode.zuke_annotation',
    severity: DiagnosticSeverity.ERROR,
  );

  ZukeAnnotationRule()
    : super(
        name: 'zuke_annotation',
        description: 'Checks Zuke annotation shape',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (_indexStateFor(context.definingUnit.file.path).incompatible) return;
    final visitor = ZukeAnnotationVisitor(reportAtNode);
    registry
      ..addClassDeclaration(this, visitor)
      ..addMixinDeclaration(this, visitor)
      ..addExtensionTypeDeclaration(this, visitor)
      ..addFunctionDeclaration(this, visitor)
      ..addMethodDeclaration(this, visitor)
      ..addFieldDeclaration(this, visitor);
  }
}
