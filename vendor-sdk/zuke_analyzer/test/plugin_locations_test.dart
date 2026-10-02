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

    test('drift is a warning and an unusable index is an error', () {
      // Split by cause, not by convenience: ordinary editing invalidates the
      // index every time, so reporting that as an error put a red squiggle on
      // every open file for the whole of a normal editing session.
      expect(
        analyzer_plugin.ZukeIndexStaleRule.code.severity,
        DiagnosticSeverity.WARNING,
      );
      expect(
        analyzer_plugin.ZukeIndexUnusableRule.code.severity,
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

        final result = await _analyzeSource(fixture, source);
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

    test(
      'fresh plugin resolution diagnoses missing evidence types',
      () async {
        final fixture = await _writeAnalyzeFixture(includeZukeTesting: true);
        addTearDown(() => deleteTemporaryDirectory(fixture));
        _writeWorkspaceConfig(fixture);
        final source = File('${fixture.path}/lib/managed_test.dart')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('''
import 'package:zuke/testing.dart';

void evidenceTypesCallback() {}

void register() {
  zukeTest(evidenceTypesCallback, scenario: null as dynamic);
}
''');

        final result = await _analyzeSource(fixture, source);
        final output = '${result.stdout}\n${result.stderr}';
        expect(
          output,
          contains('zuke_missing_evidence_types'),
          reason:
              'the fresh plugin must inspect the named argument AST:\n$output',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('dart analyze reports an unbound evidence slot on its rule, through the '
        'real plugin', () async {
      // The only link the rest of the suite does not cover: that
      // `registerNodeProcessors` actually registers the visitor and emits a
      // diagnostic, with the workspace-relative feature location in the
      // message. The other binding tests drive the shared decision function
      // and the visitor directly, so a broken registration or a mis-substituted
      // {0} would pass all of them and show nothing in an editor.
      final fixture = await _writeAnalyzeFixture();
      addTearDown(() => deleteTemporaryDirectory(fixture));
      _writeWorkspaceConfig(fixture);

      const contractPath = 'lib/src/generated/feat_gap_001_contracts.g.dart';
      _writeCurrentIndex(
        fixture,
        requirementIds: const ['RULE-E2E-GAP'],
        controlIds: const [],
        bindingIds: const [],
        // Implemented, so the unimplemented-requirement rule stays quiet and
        // this test asserts one rule's behaviour rather than two.
        implementedRequirementIds: const ['RULE-E2E-GAP'],
        // No managed registration, so the slot is a decided gap rather than an
        // unknown: the absence here is real, not unreadable.
        evidenceObligations: const [
          EvidenceObligation(
            featureId: 'FEAT-E2E-GAP-001',
            ruleId: 'RULE-E2E-GAP',
            scenarioIds: ['SCN-E2E-GAP-001'],
            slots: [
              {
                'type': 'flutter-widget',
                'target': 'backend',
                'sourcePackage': 'backend',
                'sourceAdapter': 'dart-source',
                'variant': 'default',
              },
            ],
            location: FeatureLocation(
              file: 'specs/features/gap.feature',
              line: 12,
              column: 3,
            ),
          ),
        ],
        runnerScopes: const [
          RunnerScopeFact(
            target: 'backend',
            sourcePackage: 'backend',
            adapters: ['dart-source'],
          ),
        ],
        featureFiles: const {'FEAT-E2E-GAP-001': contractPath},
      );

      final contract = File('${fixture.path}/$contractPath')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''
class FeatGap001RuleIds {
  static const gap = 'RULE-E2E-GAP';
}
''');

      final result = await _analyzeSource(fixture, contract);
      final output = '${result.stdout}\n${result.stderr}'.replaceAll('\\', '/');

      expect(
        output,
        contains('zuke_binding_unbound'),
        reason: 'the rule must fire in a real plugin build:\n$output',
      );
      // The code travels in the message, which is what the editor shows.
      expect(output, contains('ZUKE-EVIDENCE-BINDING-UNBOUND'));
      // The scenarios identify the affected work; the rule itself is identified
      // by the anchor, so it is deliberately not repeated in the text.
      expect(output, contains('SCN-E2E-GAP-001'));
      // The slot identity, so the reader can see which of several slots is
      // missing rather than only that one of them is.
      expect(output, contains('flutter-widget/backend/backend/dart-source'));
      // And the real location, relative to the workspace, as the CLI reports
      // it. An absolute path here would read differently from `zuke validate`
      // describing the same finding.
      expect(output, contains('specs/features/gap.feature:12:3'));
      // Anchored on the rule's own constant, not the top of the file. Column 16
      // is where `gap` starts in `  static const gap = ...`; anchoring on the
      // string literal instead would point at the value rather than the
      // declaration the reader has to edit.
      expect(
        output,
        contains(
          RegExp(
            r'warning\s+-\s+(?:.*[/\\])?feat_gap_001_contracts\.g\.dart:2:16',
          ),
        ),
        reason: 'expected the rule constant as the anchor in:\n$output',
      );
      // A warning, not an error: a workspace mid-authoring has unbound slots by
      // definition, and an error would train people to ignore the rule.
      expect(result.exitCode, 2, reason: output);
      expect(
        RegExp(r' - zuke_binding_unbound\b').allMatches(output),
        hasLength(1),
        reason: 'one rule/slot must produce exactly one diagnostic:\n$output',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'dart analyze names the unimplemented requirement in the message',
      () async {
        final fixture = await _writeAnalyzeFixture();
        addTearDown(() => deleteTemporaryDirectory(fixture));

        // A workspace whose only requirement has no implementation, mirroring a
        // generated contract that was never acted on.
        _writeWorkspaceConfig(fixture);
        _writeCurrentIndex(
          fixture,
          requirementIds: const ['RULE-E2E-MISSING'],
          controlIds: const [],
          bindingIds: const [],
        );

        final contract =
            File(
                '${fixture.path}/lib/src/generated/feat_demo_001_contracts.g.dart',
              )
              ..parent.createSync(recursive: true)
              ..writeAsStringSync('''
class FeatDemo001RequirementIds {
  static const missing = 'RULE-E2E-MISSING';
}
''');

        final result = await _analyzeSource(fixture, contract);
        final output = '${result.stdout}\n${result.stderr}'.replaceAll(
          '\\',
          '/',
        );

        expect(
          output,
          contains('zuke_unimplemented_requirement'),
          reason:
              'expected the unimplemented-requirement rule to fire in:\n$output',
        );
        // The analyzer substitutes arguments by index, so the template must use
        // {0}. A `$0` template reaches the Problems pane verbatim and names no
        // requirement, which is worse than no message at all: the reader has
        // only the file and line to go on.
        expect(output, isNot(contains(r'$0')));
        expect(output, contains('Requirement RULE-E2E-MISSING'));
        // The cause clause and the template must not both give the remedy. A
        // regression shipped the same advice twice, once from the target-scope
        // clause and once from the template tail.
        expect(
          RegExp('narrow the requirement').allMatches(output).length,
          1,
          reason: 'the remedy must be stated exactly once:\n$output',
        );
        expect(
          output,
          contains('is unimplemented'),
          reason: 'the message states the fact, not a scoping claim:\n$output',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a contract outside every configured package says so, and says it once',
      () async {
        // The shape `calculator-product` has: one contracts package shared by two
        // targets that is listed in neither target's `packages:`. The generated
        // contract therefore belongs to no target, which is a fact about the
        // *file*. Reporting it as "declared for no target" read as a claim about
        // the requirement's scoping, and when the explanation was added to that
        // clause it repeated the template's remedy.
        final fixture = await _writeAnalyzeFixture();
        addTearDown(() => deleteTemporaryDirectory(fixture));

        File('${fixture.path}/zuke.yaml').writeAsStringSync('''
  schemaVersion: 3
  workspace:
    name: loc-shared
    root: .
  specifications:
    features: []
  targets:
    backend:
      language: dart
      framework: dart
      packages:
        - id: api_pkg
          path: apps/api
          roots: [lib]
  ''');
        _writeCurrentIndex(
          fixture,
          requirementIds: const ['RULE-E2E-SHARED'],
          controlIds: const [],
          bindingIds: const [],
          packageTargets: const {'apps/api': 'backend'},
        );

        final contract =
            File(
                '${fixture.path}/packages/contracts/lib/src/generated/'
                'feat_shared_001_contracts.g.dart',
              )
              ..parent.createSync(recursive: true)
              ..writeAsStringSync('''
  class FeatShared001RequirementIds {
    static const shared = 'RULE-E2E-SHARED';
  }
  ''');

        final result = await _analyzeSource(fixture, contract);
        final output = '${result.stdout}\n${result.stderr}';

        expect(
          output,
          contains('outside every configured package'),
          reason: 'the message must name the real cause:\n$output',
        );
        expect(
          RegExp('narrow the requirement').allMatches(output).length,
          1,
          reason: 'the remedy must be stated exactly once:\n$output',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('the calculator performance rule is backend-only and covered', () {
      final workspaceRoot = _findWorkspaceRoot();
      final index = ZukeIndex.read(
        File(
          '${workspaceRoot.path}${Platform.pathSeparator}examples'
          '${Platform.pathSeparator}calculator-product'
          '${Platform.pathSeparator}.zuke${Platform.pathSeparator}'
          'analyzer-index.json',
        ),
      );
      const id = 'RULE-CALC-PERFORMANCE';
      expect(index.requirementTargets[id], ['backend']);
      expect(index.unimplementedRequirementIds(null), isNot(contains(id)));
      expect(index.unimplementedRequirementIds('backend'), isNot(contains(id)));
      expect(
        index.verifiedClaims.any(
          (claim) => claim.id == id && claim.target == 'backend',
        ),
        isTrue,
      );
    });

    test(
      'the calculator-product contract has no unimplemented performance rule',
      () async {
        // The contracts package remains shared and unattributed, but the
        // backend-only performance rule has a backend implementation claim.
        // The shared contract must not report it as unimplemented.
        final workspaceRoot = _findWorkspaceRoot();
        final contract = File(
          '${workspaceRoot.path}${Platform.pathSeparator}examples'
          '${Platform.pathSeparator}calculator-product'
          '${Platform.pathSeparator}packages'
          '${Platform.pathSeparator}calculator_contracts'
          '${Platform.pathSeparator}lib${Platform.pathSeparator}src'
          '${Platform.pathSeparator}generated'
          '${Platform.pathSeparator}feat_calc_001_contracts.g.dart',
        );
        expect(
          contract.existsSync(),
          isTrue,
          reason:
              'the example commits its generated contracts. If this is missing, '
              'run `zuke generate --root examples/calculator-product`.',
        );

        final result = await _analyzeSource(workspaceRoot, contract);
        final output = '${result.stdout}\n${result.stderr}';

        expect(result.exitCode, 0, reason: output);
        expect(
          output,
          isNot(contains('Requirement RULE-CALC-PERFORMANCE')),
          reason:
              'the backend implementation must satisfy the performance rule: '
              '$output',
        );
        expect(
          output,
          isNot(
            contains('An error occurred while executing an analyzer plugin'),
          ),
          reason:
              'a plugin load failure cannot establish that the warning cleared: '
              '$output',
        );
      },
      // A real plugin AOT build plus analysing the example's dependency graph.
      timeout: const Timeout(Duration(minutes: 5)),
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
  Iterable<String> implementedRequirementIds = const [],
  Map<String, String> packageTargets = const {},
  List<EvidenceObligation> evidenceObligations = const [],
  List<ManagedRegistrationFact> managedRegistrations = const [],
  List<RunnerScopeFact> runnerScopes = const [],
  Map<String, String> featureFiles = const {},
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
    implementedRequirementIds: implementedRequirementIds,
    packageTargets: packageTargets,
    evidenceObligations: evidenceObligations,
    managedRegistrations: managedRegistrations,
    runnerScopes: runnerScopes,
    featureFiles: featureFiles,
  );
  final indexFile = File('${root.path}/.zuke/analyzer-index.json');
  indexFile.parent.createSync(recursive: true);
  indexFile.writeAsStringSync(jsonEncode(index.toJson()));
  expect(index.freshnessIssues(root: root.path), isEmpty);
}

/// Isolated package that enables the real plugin the way a consumer would.
Future<Directory> _writeAnalyzeFixture({
  bool includeZukeTesting = false,
}) async {
  final workspaceRoot = _findWorkspaceRoot().path;
  final annotationsPath = _posixPath(
    '$workspaceRoot${Platform.pathSeparator}vendor-sdk'
    '${Platform.pathSeparator}zuke_annotations',
  );
  final pluginPath = _posixPath(
    '$workspaceRoot${Platform.pathSeparator}vendor-sdk'
    '${Platform.pathSeparator}zuke_analyzer',
  );
  final zukePath = _posixPath(
    '$workspaceRoot${Platform.pathSeparator}vendor-sdk'
    '${Platform.pathSeparator}zuke',
  );
  final fixture = Directory.systemTemp.createTempSync('zuke-analyze-e2e-');
  File('${fixture.path}/pubspec.yaml').writeAsStringSync('''
name: loc_e2e_pkg
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
${includeZukeTesting ? '  zuke:\n    path: $zukePath\n' : '  zuke_annotations:\n    path: $annotationsPath\n'}
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
      zuke_missing_evidence_types: true
      zuke_unimplemented_requirement: true
      zuke_binding_unbound: true
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

Future<ProcessResult> _analyzeSource(Directory root, File source) =>
    Process.run(
      Platform.resolvedExecutable,
      ['--disable-dart-dev', '--suppress-analytics', 'analyze', source.path],
      workingDirectory: root.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

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
