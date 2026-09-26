import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:test/test.dart';
import 'package:zuke_cli/editor.dart';
import 'package:zuke_analyzer/main.dart' as analyzer_plugin;
import 'package:zuke_analyzer/src/plugin_visitors.dart';
import 'package:zuke_test_support/src/temporary_directory.dart';

void main() {
  group('Zuke Analyzer Plugin locations', () {
    late Directory tempDir;

    setUp(() {
      analyzer_plugin.zukeClearIndexCacheForTesting();
      tempDir = Directory.systemTemp.createTempSync('zuke-plugin-loc-');
      _writePackageConfig(tempDir);
    });

    tearDown(() => deleteTemporaryDirectory(tempDir));

    test('stale index rule reports the analyzed file at a real line', () async {
      _writeWorkspaceConfig(tempDir);
      final lib = Directory('${tempDir.path}/lib')..createSync(recursive: true);
      final source = File('${lib.path}/app.dart')
        ..writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

class Service {}
''');
      final unit = await _resolveUnit(source);
      final ast = unit.unit;

      final reported = <AstNode>[];
      _walk(ast, _StaleIndexCapture(reportAtNode: reported.add));

      expect(reported, hasLength(1));
      final anchor = reported.single;
      expect(_norm(unit.path), _resolvedNorm(source));
      final location = unit.lineInfo.getLocation(anchor.offset);
      expect(location.lineNumber, 1);
      expect(location.columnNumber, 1);
      expect(anchor, isA<ImportDirective>());
      expect(
        analyzer_plugin.zukeIndexStaleAppliesForTesting(source.absolute.path),
        isTrue,
      );
    });

    test('annotation diagnostics use the annotation line and column', () async {
      final lib = Directory('${tempDir.path}/lib')..createSync(recursive: true);
      final source = File('${lib.path}/app.dart')
        ..writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

class Holder {
  @ImplementsRequirement(['RULE-KNOWN'])
  int quantity = 0;
}
''');
      final unit = await _resolveUnit(source);
      final ast = unit.unit;

      final reported = <Annotation>[];
      _walk(ast, ZukeAnnotationVisitor(reported.add));

      expect(reported, hasLength(1));
      final annotation = reported.single;
      expect(_norm(unit.path), _resolvedNorm(source));
      final location = unit.lineInfo.getLocation(annotation.offset);
      expect(location.lineNumber, 4);
      expect(location.columnNumber, 3);
      expect(
        unit.lineInfo.getLocation(annotation.end).lineNumber,
        4,
        reason: 'annotation must not spill onto the next line',
      );
    });

    test('unknown index ID diagnostics use the annotation location', () async {
      _writeWorkspaceConfig(tempDir);
      final lib = Directory('${tempDir.path}/lib')..createSync(recursive: true);
      final source = File('${lib.path}/app.dart')
        ..writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

@ImplementsRequirement(['RULE-UNKNOWN'])
class Service {}
''');
      _writeCurrentIndex(
        tempDir,
        requirementIds: const [],
        controlIds: const [],
        bindingIds: const [],
      );
      final unit = await _resolveUnit(source);
      final ast = unit.unit;

      const index = ZukeIndex(
        inputDigest: 'input',
        generatedManifestDigest: 'manifest',
        generatedManifestPath: 'manifest.json',
        inputs: [],
        requirementIds: {},
        controlIds: {},
        bindingIds: {},
      );
      final reported = <Annotation>[];
      _walk(ast, ZukeUnknownIdVisitor(index, reported.add));

      expect(reported, hasLength(1));
      final annotation = reported.single;
      expect(_norm(unit.path), _resolvedNorm(source));
      final location = unit.lineInfo.getLocation(annotation.offset);
      expect(location.lineNumber, 3);
      expect(location.columnNumber, 1);
      expect(
        analyzer_plugin.zukeIndexStaleAppliesForTesting(source.absolute.path),
        isFalse,
        reason: 'current index must not also raise stale',
      );
    });

    test('missing-test diagnostics use the annotation location', () async {
      _writeWorkspaceConfig(tempDir);
      final lib = Directory('${tempDir.path}/lib')..createSync(recursive: true);
      final source = File('${lib.path}/app.dart')
        ..writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

class Service {
  @ImplementsRequirement(['RULE-KNOWN'])
  void run() {}
}
''');
      _writeCurrentIndex(
        tempDir,
        requirementIds: const ['RULE-KNOWN'],
        controlIds: const [],
        bindingIds: const [],
        verifiedRequirementIds: const [],
      );
      final unit = await _resolveUnit(source);
      final ast = unit.unit;

      const index = ZukeIndex(
        inputDigest: 'input',
        generatedManifestDigest: 'manifest',
        generatedManifestPath: 'manifest.json',
        inputs: [],
        requirementIds: {'RULE-KNOWN'},
        controlIds: {},
        bindingIds: {},
      );
      final reported = <Annotation>[];
      _walk(ast, ZukeMissingTestVisitor(index, reported.add));

      expect(reported, hasLength(1));
      final annotation = reported.single;
      expect(_norm(unit.path), _resolvedNorm(source));
      final location = unit.lineInfo.getLocation(annotation.offset);
      expect(location.lineNumber, 4);
      expect(location.columnNumber, 3);
    });

    test('non-workspace files never raise stale index diagnostics', () {
      final outside = File('${tempDir.path}/vendor_like/lib/app.dart');
      outside.parent.createSync(recursive: true);
      outside.writeAsStringSync('void main() {}\n');

      expect(
        analyzer_plugin.zukeIndexStaleAppliesForTesting(outside.absolute.path),
        isFalse,
      );
      expect(
        analyzer_plugin.zukeIndexIsCurrentForTesting(outside.absolute.path),
        isFalse,
      );
    });

    test('stale severity is error and missing test is warning', () {
      expect(
        analyzer_plugin.ZukeIndexStaleRule.code.severity,
        DiagnosticSeverity.ERROR,
      );
      expect(
        analyzer_plugin.ZukeAnnotationRule.code.severity,
        DiagnosticSeverity.ERROR,
      );
      expect(
        analyzer_plugin.ZukeUnknownIndexIdRule.code.severity,
        DiagnosticSeverity.ERROR,
      );
      expect(
        analyzer_plugin.ZukeMissingTestRule.code.severity,
        DiagnosticSeverity.WARNING,
      );
    });

    test(
      'dart analyze reports file, line, and column for annotation errors',
      () async {
        final fixture = await _writeAnalyzeFixture();
        addTearDown(() => deleteTemporaryDirectory(fixture));

        final source = File('${fixture.path}/lib/app.dart');
        source.parent.createSync(recursive: true);
        source.writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

class Holder {
  @ImplementsRequirement(['RULE-KNOWN'])
  int quantity = 0;
}
''');

        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            '--disable-dart-dev',
            '--suppress-analytics',
            'analyze',
            source.path,
          ],
          workingDirectory: fixture.path,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        final output = '${result.stdout}\n${result.stderr}'.replaceAll(
          '\\',
          '/',
        );
        final normalizedPath = source.path.replaceAll('\\', '/');

        expect(result.exitCode, isNot(0), reason: output);
        // dart analyze prints the relative path when the target is under cwd.
        expect(
          output,
          contains(
            RegExp(
              r'error\s+-\s+(?:.*[/\\])?'
              'app\\.dart:4:3\\s+-.*zuke_annotation',
            ),
          ),
          reason: 'expected file:line:col for zuke_annotation in:\n$output',
        );
        expect(output, contains(normalizedPath.split('/').last));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

Future<ResolvedUnitResult> _resolveUnit(File source) async {
  final normalizedRoot = source.parent.parent.resolveSymbolicLinksSync();
  final normalizedSource = source.resolveSymbolicLinksSync();
  final collection = AnalysisContextCollection(includedPaths: [normalizedRoot]);
  addTearDown(collection.dispose);
  final resolved = await collection
      .contextFor(normalizedSource)
      .currentSession
      .getResolvedUnit(normalizedSource);
  expect(resolved, isA<ResolvedUnitResult>());
  return resolved as ResolvedUnitResult;
}

void _walk(AstNode node, AstVisitor<void> visitor) {
  node.accept(visitor);
  for (final child in node.childEntities.whereType<AstNode>()) {
    _walk(child, visitor);
  }
}

void _writeWorkspaceConfig(Directory root) {
  File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: loc-test
  root: .
specifications:
  features: []
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: loc_pkg
        path: .
        roots: [lib]
''');
}

void _writeCurrentIndex(
  Directory root, {
  required Iterable<String> requirementIds,
  required Iterable<String> controlIds,
  required Iterable<String> bindingIds,
  Iterable<String> verifiedRequirementIds = const [],
}) {
  final config = File('${root.path}/zuke.yaml');
  final manifest = File('${root.path}/generated-manifest.json')
    ..writeAsStringSync('{"files":[]}');
  final index = ZukeIndex.create(
    root: root.path,
    inputPaths: [config.path],
    generatedManifestContent: manifest.readAsStringSync(),
    generatedManifestPath: 'generated-manifest.json',
    requirementIds: requirementIds,
    controlIds: controlIds,
    bindingIds: bindingIds,
    verifiedRequirementIds: verifiedRequirementIds,
  );
  final indexFile = File('${root.path}/.zuke/analyzer-index.json');
  indexFile.parent.createSync(recursive: true);
  indexFile.writeAsStringSync(jsonEncode(index.toJson()));
  expect(index.freshnessIssues(root: root.path), isEmpty);
}

/// Isolated package that enables the real plugin the way a consumer would.
Future<Directory> _writeAnalyzeFixture() async {
  final workspaceRoot = _findWorkspaceRoot().path;
  final annotationsPath = _posixPath(
    '$workspaceRoot${Platform.pathSeparator}vendor-sdk'
    '${Platform.pathSeparator}zuke_annotations',
  );
  final pluginPath = _posixPath(
    '$workspaceRoot${Platform.pathSeparator}vendor-sdk'
    '${Platform.pathSeparator}zuke_analyzer',
  );
  final fixture = Directory.systemTemp.createTempSync('zuke-analyze-e2e-');
  File('${fixture.path}/pubspec.yaml').writeAsStringSync('''
name: loc_e2e_pkg
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  zuke_annotations:
    path: $annotationsPath
dev_dependencies:
  lints: any
''');
  File('${fixture.path}/analysis_options.yaml').writeAsStringSync('''
include: package:lints/recommended.yaml
plugins:
  zuke_analyzer:
    path: $pluginPath
    diagnostics:
      zuke_annotation: true
      zuke_index_stale: true
      zuke_unknown_index_id: true
      zuke_missing_test: true
''');
  final pubGet = await Process.run(
    Platform.resolvedExecutable,
    ['pub', 'get'],
    workingDirectory: fixture.path,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  expect(
    pubGet.exitCode,
    0,
    reason: 'pub get failed:\n${pubGet.stdout}\n${pubGet.stderr}',
  );
  return fixture;
}

String _norm(String path) => path.replaceAll(r'\', '/');

String _resolvedNorm(File file) =>
    _norm(file.absolute.resolveSymbolicLinksSync());

String _posixPath(String path) => path.replaceAll(r'\', '/');

Directory _findWorkspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(
      '${current.path}${Platform.pathSeparator}pubspec.yaml',
    );
    if (pubspec.existsSync() &&
        RegExp(
          r'^workspace:\s*$',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync())) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Unable to locate the Dart workspace root from ${Directory.current.path}',
      );
    }
    current = parent;
  }
}

void _writePackageConfig(Directory root) {
  final workspaceRoot = _findWorkspaceRoot();
  final workspaceConfig = File(
    '${workspaceRoot.path}${Platform.pathSeparator}.dart_tool'
    '${Platform.pathSeparator}package_config.json',
  );
  final decoded = jsonDecode(workspaceConfig.readAsStringSync()) as Map;
  final packageConfigDirectory = workspaceConfig.parent.uri;
  final packages = (decoded['packages'] as List)
      .whereType<Map<Object?, Object?>>()
      .map((entry) {
        final copy = Map<String, Object?>.from(entry);
        final rootUri = Uri.parse(copy['rootUri'] as String);
        copy['rootUri'] =
            (rootUri.isAbsolute
                    ? rootUri
                    : packageConfigDirectory.resolveUri(rootUri))
                .toString();
        return copy;
      })
      .toList();
  final config = Directory('${root.path}/.dart_tool')..createSync();
  File(
    '${config.path}/package_config.json',
  ).writeAsStringSync(jsonEncode({'configVersion': 2, 'packages': packages}));
}

/// Mirrors [analyzer_plugin.ZukeIndexStaleRule]'s anchor choice without
/// needing a live RuleContext.
class _StaleIndexCapture extends SimpleAstVisitor<void> {
  final void Function(AstNode) reportAtNode;
  _StaleIndexCapture({required this.reportAtNode});

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final AstNode anchor = node.directives.isNotEmpty
        ? node.directives.first
        : node.declarations.isNotEmpty
        ? node.declarations.first
        : node;
    reportAtNode(anchor);
  }
}
