import 'dart:io';

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:zuke_core/inspection.dart';

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
  }
}

class ZukeIndexStaleRule extends AnalysisRule {
  static const code = LintCode(
    'zuke_index_stale',
    'ZUKE-INDEX-STALE: Run zuke generate before analysis.',
    uniqueName: 'LintCode.zuke_index_stale',
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
    final state = _indexStateFor(context.currentUnit?.file.path);
    if (state.isCurrent) return;
    registry.addCompilationUnit(this, _StaleIndexVisitor(this));
  }
}

class _StaleIndexVisitor extends SimpleAstVisitor<void> {
  final ZukeIndexStaleRule rule;
  _StaleIndexVisitor(this.rule);

  @override
  void visitCompilationUnit(CompilationUnit node) {
    rule.reportAtNode(node);
  }
}

class ZukeUnknownIndexIdRule extends AnalysisRule {
  static const code = LintCode(
    'zuke_unknown_index_id',
    'ZUKE-INDEX-UNKNOWN-ID: Annotation references an ID absent from the current index.',
    uniqueName: 'LintCode.zuke_unknown_index_id',
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
    final index = _indexStateFor(context.currentUnit?.file.path).index;
    if (index != null)
      registry.addAnnotation(this, ZukeUnknownIdVisitor(index, reportAtNode));
  }
}

class _IndexState {
  final ZukeIndex? index;
  const _IndexState(this.index);
  bool get isCurrent => index != null;
}

/// Internal test seam for the workspace/index discovery used by analyzer
/// callbacks, which otherwise only run inside the analysis server process.
bool zukeIndexIsCurrentForTesting(String? sourcePath) =>
    _indexStateFor(sourcePath).isCurrent;

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
  if (sourcePath == null) return const _IndexState(null);
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
            ? _IndexState(index)
            : const _IndexState(null);
        _indexCache[key] = _IndexCacheEntry(now, modified, state);
        return state;
      } catch (_) {
        const state = _IndexState(null);
        _indexCache[key] = _IndexCacheEntry(now, modified, state);
        return state;
      }
    }
    final parent = directory.parent;
    if (parent.path == directory.path) return const _IndexState(null);
    directory = parent;
  }
}

class ZukeAnnotationRule extends AnalysisRule {
  static const code = LintCode(
    'zuke_annotation',
    'Zuke annotations require supported targets and constant identifiers',
    uniqueName: 'LintCode.zuke_annotation',
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
