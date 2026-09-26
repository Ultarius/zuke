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
    final index = _indexStateFor(context.definingUnit.file.path).index;
    if (index != null) {
      registry.addAnnotation(this, ZukeMissingTestVisitor(index, reportAtNode));
    }
  }
}

class _IndexState {
  final ZukeIndex? index;
  final bool hasWorkspace;
  const _IndexState(this.index, {required this.hasWorkspace});
  bool get isCurrent => index != null;
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
            ? _IndexState(index, hasWorkspace: true)
            : const _IndexState(null, hasWorkspace: true);
        _indexCache[key] = _IndexCacheEntry(now, modified, state);
        return state;
      } catch (_) {
        const state = _IndexState(null, hasWorkspace: true);
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
