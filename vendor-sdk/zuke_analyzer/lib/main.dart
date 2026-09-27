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
    registry.registerLintRule(ZukeAnnotationRule());
    registry.registerLintRule(ZukeIndexStaleRule());
    registry.registerLintRule(ZukeUnknownIndexIdRule());
    registry.registerLintRule(ZukeMissingTestRule());
    registry.registerLintRule(ZukeUnimplementedRequirementRule());
    registry.registerLintRule(ZukeSpecLintRule());
  }
}

class ZukeIndexStaleRule extends AnalysisRule {
  static const code = LintCode(
    'zuke_index_stale',
    'ZUKE-INDEX-STALE: Run zuke generate before analysis.',
    uniqueName: 'LintCode.zuke_index_stale',
    severity: DiagnosticSeverity.ERROR,
  );

  ZukeIndexStaleRule()
    : super(
        name: 'zuke_index_stale',
        description: 'Rejects missing, malformed, or stale Zuke indexes',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final state = _indexStateFor(context.definingUnit.file.path);
    // Only Zuke workspaces (zuke.yaml present) own index freshness. Files
    // outside a workspace are not stale—they are not governed by Zuke.
    if (!state.hasWorkspace || state.isCurrent) return;
    registry.addCompilationUnit(this, _StaleIndexVisitor(this));
  }
}

class _StaleIndexVisitor extends SimpleAstVisitor<void> {
  final ZukeIndexStaleRule rule;
  _StaleIndexVisitor(this.rule);

  @override
  void visitCompilationUnit(CompilationUnit node) {
    // Anchor on the first directive (or declaration) so Problems points at a
    // real line in the analyzed file, not always offset 0 / line 1.
    final AstNode anchor = node.directives.isNotEmpty
        ? node.directives.first
        : node.declarations.isNotEmpty
        ? node.declarations.first
        : node;
    rule.reportAtNode(anchor);
  }
}

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
    final index = _indexStateFor(context.definingUnit.file.path).index;
    if (index != null) {
      registry.addAnnotation(this, ZukeUnknownIdVisitor(index, reportAtNode));
    }
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
    final index = state.index;
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

class _IndexState {
  final ZukeIndex? index;
  final bool hasWorkspace;

  /// The directory holding the `zuke.yaml` this index came from, so a caller
  /// can express an analyzed path relative to the workspace without walking the
  /// tree a second time.
  final String? workspaceRoot;
  const _IndexState(
    this.index, {
    required this.hasWorkspace,
    this.workspaceRoot,
  });
  bool get isCurrent => index != null;
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
/// Suppress a single contract with
/// `// ignore: zuke/zuke_unimplemented_requirement`.
class ZukeUnimplementedRequirementRule extends AnalysisRule {
  static const code = LintCode(
    'zuke_unimplemented_requirement',
    'ZUKE-UNIMPLEMENTED-REQUIREMENT: Requirement {0} is declared for {1}; '
        'nothing implements it. Add @ImplementsRequirement or '
        '@PresentsRequirement, or narrow the requirement\'s declared targets.',
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
    final index = state.index;
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
          // Name the target when there is one. "this target" reads as a dangling
          // reference when the file could not be attributed at all, which is the
          // case the leniency in requirementAppliesTo deliberately allows.
          targetId ?? 'no target',
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
    final index = state.index;
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
  return state.hasWorkspace && !state.isCurrent;
}

/// Clears process-local index state between isolated analyzer tests.
void zukeClearIndexCacheForTesting() => _indexCache.clear();

class _IndexCacheEntry {
  final DateTime lastChecked;
  final DateTime? fileModified;
  final _IndexState state;
  const _IndexCacheEntry(this.lastChecked, this.fileModified, this.state);
}

final _indexCache = <String, _IndexCacheEntry>{};

_IndexState _indexStateFor(String? sourcePath) {
  if (sourcePath == null) {
    return const _IndexState(null, hasWorkspace: false);
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
        final index = ZukeIndex.read(indexFile);
        final state = index.isCurrent(root: directory.path)
            ? _IndexState(
                index,
                hasWorkspace: true,
                workspaceRoot: directory.path,
              )
            : _IndexState(null, hasWorkspace: true);
        _indexCache[key] = _IndexCacheEntry(now, modified, state);
        return state;
      } catch (_) {
        final state = _IndexState(
          null,
          hasWorkspace: true,
          workspaceRoot: directory.path,
        );
        _indexCache[key] = _IndexCacheEntry(now, modified, state);
        return state;
      }
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      return const _IndexState(null, hasWorkspace: false);
    }
    directory = parent;
  }
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
