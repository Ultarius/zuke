import 'dart:convert';
import 'dart:io';

import 'package:zuke_test_support/src/temporary_directory.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart' as analyzer_fs;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:test/test.dart';
import 'package:zuke_cli/tooling.dart';
import 'package:zuke_analyzer/main.dart' as analyzer_plugin;
import 'package:zuke_analyzer/src/plugin_visitors.dart';
import 'package:zuke_analyzer/zuke_analyzer.dart';

void main() {
  group('Zuke Analyzer Plugin', () {
    late Directory tempDir;

    setUp(() {
      analyzer_plugin.zukeClearIndexCacheForTesting();
      tempDir = Directory.systemTemp.createTempSync('zuke-plugin-');
      _writePackageConfig(tempDir);
    });

    tearDown(() => deleteTemporaryDirectory(tempDir));

    test('no index leaves every fact unavailable, whichever a rule needs', () {
      // The split must fail closed. A workspace with no index at all has no
      // specification facts and no source facts, so no rule may consult it —
      // otherwise the split would let a rule run on a missing index.
      _writeCurrentConfig(tempDir);
      final source = File('${tempDir.path}/lib/app.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');
      expect(
        analyzer_plugin.zukeSpecificationFactsAvailableForTesting(
          source.absolute.path,
        ),
        isFalse,
      );
      expect(
        analyzer_plugin.zukeSourceFactsAvailableForTesting(
          source.absolute.path,
        ),
        isFalse,
      );
      expect(
        analyzer_plugin.zukeIndexStaleAppliesForTesting(source.absolute.path),
        isTrue,
        reason: 'and the workspace is reported as behind',
      );
    });

    for (final version in [zukeIndexContract - 1, zukeIndexContract + 1]) {
      test(
        'contract $version suppresses index noise and reports once before parsing',
        () async {
          _writeCurrentConfig(tempDir);
          final barrel = File('${tempDir.path}/lib/zuke_contracts.dart')
            ..createSync(recursive: true)
            ..writeAsStringSync('library;');
          final source = File('${tempDir.path}/lib/app.dart')
            ..writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
@ImplementsRequirement([])
class Invalid {}
''');
          File('${tempDir.path}/.zuke/analyzer-index.json')
            ..createSync(recursive: true)
            // Deliberately lacks the rest of the version-specific schema.
            ..writeAsStringSync(jsonEncode({'contractVersion': version}));
          expect(
            analyzer_plugin.zukePluginStaleMessageForTesting(source.path),
            isNull,
          );
          final message = analyzer_plugin.zukePluginStaleMessageForTesting(
            barrel.path,
          );
          expect(message, contains('this index is $version'));
          expect(message, contains('doctor --fix'));
          expect(
            analyzer_plugin.zukeIndexStaleAppliesForTesting(source.path),
            isFalse,
          );
          expect(
            analyzer_plugin.zukeMissingEvidenceTypesAppliesForTesting(
              source.path,
            ),
            isFalse,
            reason: 'contract mismatch suppresses every other Zuke rule',
          );
          expect(
            analyzer_plugin.zukeIndexIsCurrentForTesting(source.path),
            isFalse,
          );
          final diagnostics = await ZukeAnalyzer().analyzePackage(tempDir.path);
          expect(diagnostics.map((d) => d.code), ['ZUKE-PLUGIN-STALE']);
        },
      );
    }

    test(
      'contract mismatch uses configured barrel and rejects escaping anchors',
      () {
        _writeCurrentConfig(tempDir);
        final barrel = File('${tempDir.path}/lib/public.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync('library;');
        File('${tempDir.path}/lib/other.dart').writeAsStringSync('library;');
        final header = ZukeIndexHeader({
          'contractVersion': zukeIndexContract + 1,
          'diagnosticAnchor': 'lib/public.dart',
        });
        expect(
          header.diagnosticAnchor(tempDir.path)?.replaceAll('\\', '/'),
          barrel.path.replaceAll('\\', '/'),
        );
        final escaped = ZukeIndexHeader({
          'contractVersion': zukeIndexContract + 1,
          'diagnosticAnchor': '../external.dart',
          'featureFiles': {'FEATURE': 'lib/public.dart'},
        });
        expect(
          escaped.diagnosticAnchor(tempDir.path)?.replaceAll('\\', '/'),
          barrel.path.replaceAll('\\', '/'),
        );
      },
    );

    test(
      'analyzer plugin extracts diagnostics from out-of-date index',
      () async {
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
          'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
        );
        final libDir = Directory('${tempDir.path}/lib')
          ..createSync(recursive: true);
        File('${libDir.path}/app.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

@ImplementsRequirement([])
class MyService {}
''');
        _writeCurrentConfig(tempDir);

        final diagnostics = await ZukeAnalyzer().analyzePackage(tempDir.path);
        expect(diagnostics.any((d) => d.code == 'ZUKE-ANNOTATION-001'), isTrue);
      },
    );

    test('analyzer plugin results agree with CLI extract results', () async {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );
      final libDir = Directory('${tempDir.path}/lib')
        ..createSync(recursive: true);
      File('${libDir.path}/app.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

@ImplementsRequirement(['RULE-TEST-001'])
class ValidService {}

class NoAnnotation {}
''');

      final config = _writeCurrentConfig(tempDir);
      final manifest = File('${tempDir.path}/generated-manifest.json')
        ..writeAsStringSync('{"files":[]}');
      final index = ZukeIndex.create(
        root: tempDir.path,
        inputPaths: [config.path],
        generatedManifestContent: manifest.readAsStringSync(),
        generatedManifestPath: 'generated-manifest.json',
        requirementIds: const ['RULE-TEST-001'],
        controlIds: const [],
        bindingIds: const [],
        verifiedRequirementIds: const ['RULE-TEST-001'],
      );
      final indexFile = File('${tempDir.path}/.zuke/analyzer-index.json')
        ..createSync(recursive: true);
      indexFile.writeAsStringSync(jsonEncode(index.toJson()));

      final pluginDiagnostics = await ZukeAnalyzer().analyzePackage(
        tempDir.path,
      );
      final extractOutput = await DartExtractor().extract(
        tempDir.path,
        roots: ['lib'],
        target: 'backend',
      );
      final extractErrors = extractOutput.errors;
      expect(pluginDiagnostics.length, equals(extractErrors.length));
      for (var i = 0; i < pluginDiagnostics.length; i++) {
        expect(pluginDiagnostics[i].message, equals(extractErrors[i]));
      }
    });

    test('reports a missing workspace index as stale', () async {
      _writeCurrentConfig(tempDir);
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );
      (Directory('${tempDir.path}/lib')..createSync(recursive: true));

      final diagnostics = await ZukeAnalyzer().analyzePackage(tempDir.path);
      expect(diagnostics.any((d) => d.code == 'ZUKE-INDEX-STALE'), isTrue);
    });

    test('current index reports unknown IDs and duplicate bindings', () async {
      final config = _writeCurrentConfig(tempDir);
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );
      final lib = Directory('${tempDir.path}/lib')..createSync();
      File('${lib.path}/app.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

@ImplementsRequirement(['RULE-UNKNOWN'])
@ProvidesControl(['CTRL-UNKNOWN'])
class Service {
  @ZukeBinding('binding.unknown')
  String get first => 'first';

  @ZukeBinding('binding.unknown')
  String get second => 'second';
}
''');
      final manifest = File('${tempDir.path}/generated-manifest.json')
        ..writeAsStringSync('{"files":[]}');
      final index = ZukeIndex.create(
        root: tempDir.path,
        inputPaths: [config.path],
        generatedManifestContent: manifest.readAsStringSync(),
        generatedManifestPath: 'generated-manifest.json',
        requirementIds: const [],
        controlIds: const [],
        bindingIds: const [],
      );
      final indexFile = File('${tempDir.path}/.zuke/analyzer-index.json');
      indexFile.parent.createSync(recursive: true);
      indexFile.writeAsStringSync(jsonEncode(index.toJson()));
      expect(index.freshnessIssues(root: tempDir.path), isEmpty);

      final diagnostics = await ZukeAnalyzer().analyzePackage(tempDir.path);

      expect(analyzer_plugin.plugin.name, 'zuke');
      expect(
        analyzer_plugin.zukeIndexIsCurrentForTesting(
          File('${lib.path}/app.dart').absolute.path,
        ),
        isTrue,
      );
      expect(
        diagnostics.where((item) => item.code == 'ZUKE-INDEX-UNKNOWN-ID'),
        hasLength(4),
      );
      expect(
        diagnostics,
        contains(
          isA<ZukeDiagnostic>().having(
            (item) => item.code,
            'code',
            'ZUKE-INDEX-DUPLICATE-BINDING',
          ),
        ),
      );
    });

    test(
      'an unreadable index still registers the diagnostic that explains why',
      () async {
        // A missing or unparseable index carries no recorded anchor and names
        // the index rather than a Dart file, so requiring one of those silently
        // swallowed the only notice explaining why nothing else reports.
        _writeCurrentConfig(tempDir);
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
          'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
        );
        final main = File('${tempDir.path}/lib/main.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync('void main() {}');
        File(
          '${tempDir.path}/lib/other.dart',
        ).writeAsStringSync('void other() {}');
        File('${tempDir.path}/.zuke/analyzer-index.json')
          ..createSync(recursive: true)
          ..writeAsStringSync('{ not json');

        expect(
          analyzer_plugin.zukeIndexUnusableAppliesForTesting(
            main.absolute.path,
          ),
          isTrue,
          reason: 'the owner is the entrypoint the fallback picks',
        );
        expect(
          analyzer_plugin.zukeIndexUnusableAppliesForTesting(
            '${tempDir.path}/lib/other.dart',
          ),
          isFalse,
          reason: 'and only that one file carries the notice',
        );
        expect(
          await ZukeAnalyzer().analyzePackage(tempDir.path),
          isNotEmpty,
          reason: 'and the standalone analyzer reports it too',
        );
      },
    );

    for (final payload in [null, '{ not json', '[]']) {
      test('unreadable index $payload registers on one source', () {
        _writeCurrentConfig(tempDir);
        final source = File('${tempDir.path}/lib/main.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync('void main() {}');
        final other = File('${tempDir.path}/lib/other.dart')
          ..writeAsStringSync('void other() {}');
        if (payload != null) {
          File('${tempDir.path}/.zuke/analyzer-index.json')
            ..createSync(recursive: true)
            ..writeAsStringSync(payload);
        }
        expect(_registeredFreshnessRules(source.path), ['zuke_index_unusable']);
        expect(_registeredFreshnessRules(other.path), isEmpty);
      });
    }

    test('missing index registers in a workspace with nested packages', () {
      _writeCurrentConfig(tempDir);
      final config = File('${tempDir.path}/zuke.yaml');
      config.writeAsStringSync(
        config.readAsStringSync().replaceFirst('path: .', 'path: apps/api'),
      );
      final source = File('${tempDir.path}/apps/api/lib/main.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');
      expect(_registeredFreshnessRules(source.path), ['zuke_index_unusable']);
    });

    test('source drift registers once instead of on each owner candidate', () {
      _writeCurrentConfig(tempDir);
      final anchor = File('${tempDir.path}/lib/zuke_contracts.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('library;');
      final sources = [
        for (final name in ['app', 'other'])
          File('${tempDir.path}/lib/$name.dart')
            ..writeAsStringSync('void $name() {}'),
      ];
      final manifest = File('${tempDir.path}/manifest.json')
        ..writeAsStringSync('{"files":[]}');
      final index = ZukeIndex.create(
        root: tempDir.path,
        diagnosticAnchor: 'lib/zuke_contracts.dart',
        inputPaths: sources.map((source) => source.path),
        generatedManifestContent: manifest.readAsStringSync(),
        generatedManifestPath: 'manifest.json',
        requirementIds: const [],
        controlIds: const [],
        bindingIds: const [],
      );
      File('${tempDir.path}/.zuke/analyzer-index.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(index.toJson()));
      expect(_registeredFreshnessRules(sources.first.path), isEmpty);
      for (final source in sources) {
        source.writeAsStringSync('${source.readAsStringSync()}\n// edit');
      }
      analyzer_plugin.zukeClearIndexCacheForTesting();
      expect(_registeredFreshnessRules(sources.first.path), [
        'zuke_index_stale',
      ]);
      expect(_registeredFreshnessRules(sources.last.path), isEmpty);
      expect(_registeredFreshnessRules(anchor.path), isEmpty);
    });

    for (final drift in ['source', 'specification', 'both', 'missing', '[]']) {
      test(
        'standalone analyzer suppresses unavailable facts for $drift',
        () async {
          final config = _writeCurrentConfig(tempDir);
          File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
            'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
          );
          final source = File('${tempDir.path}/lib/app.dart')
            ..createSync(recursive: true)
            ..writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
@ImplementsRequirement(['RULE-KNOWN'])
void implemented() {}
@ImplementsRequirement(['RULE-UNKNOWN'])
void unknown() {}
class Bindings {
  @ZukeBinding('binding.known')
  String get first => 'first';
  @ZukeBinding('binding.known')
  String get second => 'second';
}
''');
          final manifest = File('${tempDir.path}/manifest.json')
            ..writeAsStringSync('{"files":[]}');
          final index = ZukeIndex.create(
            root: tempDir.path,
            inputPaths: [config.path, source.path],
            generatedManifestContent: manifest.readAsStringSync(),
            generatedManifestPath: 'manifest.json',
            requirementIds: const ['RULE-KNOWN'],
            controlIds: const [],
            bindingIds: const ['binding.known'],
            verifiedClaims: const [
              ZukeImplementationClaim(id: 'RULE-KNOWN', target: 'backend'),
            ],
          );
          final indexFile = File('${tempDir.path}/.zuke/analyzer-index.json')
            ..createSync(recursive: true)
            ..writeAsStringSync(jsonEncode(index.toJson()));
          final before = await ZukeAnalyzer().analyzePackage(tempDir.path);
          expect(
            before.where((d) => d.code == 'ZUKE-INDEX-UNKNOWN-ID'),
            hasLength(1),
          );
          expect(before.where((d) => d.code == 'ZUKE-MISSING-TEST'), isEmpty);
          expect(_registeredIndexRules(source.path), [
            'zuke_missing_test',
            'zuke_unknown_index_id',
          ]);
          if (drift == 'source' || drift == 'both') {
            source.writeAsStringSync('${source.readAsStringSync()}\n// edit');
          }
          if (drift == 'specification' || drift == 'both') {
            config.writeAsStringSync('${config.readAsStringSync()}\n# edit');
          }
          if (drift == 'missing') indexFile.deleteSync();
          if (drift == '[]') indexFile.writeAsStringSync('[]');
          analyzer_plugin.zukeClearIndexCacheForTesting();
          expect(
            _registeredIndexRules(source.path),
            drift == 'source' ? ['zuke_unknown_index_id'] : isEmpty,
          );
          final after = await ZukeAnalyzer().analyzePackage(tempDir.path);
          expect(
            after.where((d) => d.code == 'ZUKE-INDEX-STALE'),
            hasLength(1),
          );
          expect(after.where((d) => d.code == 'ZUKE-MISSING-TEST'), isEmpty);
          expect(
            after.where((d) => d.code == 'ZUKE-INDEX-UNKNOWN-ID'),
            hasLength(drift == 'source' ? 1 : 0),
          );
          expect(
            after.where((d) => d.code == 'ZUKE-INDEX-DUPLICATE-BINDING'),
            hasLength(1),
          );
        },
      );
    }

    test('plugin registers all rules with stable names and diagnostics', () {
      final registry = _RecordingRegistry();

      analyzer_plugin.plugin.register(registry);

      expect(registry.rules, hasLength(9));
      expect(
        registry.rules.map((rule) => rule.name),
        containsAll([
          'zuke_annotation',
          'zuke_plugin_stale',
          'zuke_index_stale',
          'zuke_index_unusable',
          'zuke_unknown_index_id',
          'zuke_missing_test',
          'zuke_missing_evidence_types',
          'zuke_unimplemented_requirement',
          'zuke_spec_lint',
        ]),
      );
      expect(
        analyzer_plugin.ZukeAnnotationRule().diagnosticCode.lowerCaseName,
        'zuke_annotation',
      );
      expect(
        analyzer_plugin.ZukeIndexStaleRule().diagnosticCode.lowerCaseName,
        'zuke_index_stale',
      );
      expect(
        analyzer_plugin.ZukeIndexUnusableRule().diagnosticCode.lowerCaseName,
        'zuke_index_unusable',
      );
      expect(
        analyzer_plugin.ZukeUnknownIndexIdRule().diagnosticCode.lowerCaseName,
        'zuke_unknown_index_id',
      );
      expect(
        analyzer_plugin.ZukeMissingTestRule().diagnosticCode.lowerCaseName,
        'zuke_missing_test',
      );
      expect(
        analyzer_plugin.ZukeUnimplementedRequirementRule()
            .diagnosticCode
            .lowerCaseName,
        'zuke_unimplemented_requirement',
      );
      // A specs-first workspace must not go red on `dart analyze` before any
      // implementation exists, so the default stays a warning.
      expect(
        analyzer_plugin.ZukeUnimplementedRequirementRule()
            .diagnosticCode
            .severity,
        DiagnosticSeverity.WARNING,
      );
      expect(
        analyzer_plugin.ZukeSpecLintRule().diagnosticCode.lowerCaseName,
        'zuke_spec_lint',
      );
      // A broken cross-reference is a defect in the specification, not a gap
      // someone intends to close later, so this one is an error.
      expect(
        analyzer_plugin.ZukeSpecLintRule().diagnosticCode.severity,
        DiagnosticSeverity.ERROR,
      );
    });

    test(
      'resolved plugin visitors enforce targets, constants, and index IDs',
      () async {
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
          'name: visitor_fixture\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
        );
        final lib = Directory('${tempDir.path}/lib')..createSync();
        final source = File('${lib.path}/app.dart')
          ..writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

@ImplementsRequirement(['RULE-KNOWN'])
class ValidClass {
  @ZukeBinding('binding.unknown')
  final String field = '';

  @ZukeBinding('')
  String get invalidBinding => '';
}

@ImplementsRequirement([])
mixin InvalidMixin {}

@ImplementsRequirement(['RULE-KNOWN'])
extension type ValidExtensionType(String value) {}

@PresentsRequirement(['RULE-UNKNOWN'])
void unknownPresentation() {}

@VerifiesRequirement(['RULE-KNOWN'])
void validVerification() {}

@ProvidesControl(['CTRL-UNKNOWN'])
class UnknownProvider {}

class Methods {
  @ImplementsRequirement(['RULE-KNOWN'])
  void validMethod() {}

  @PresentsRequirement(['RULE-UNSUPPORTED'])
  final String unsupportedField = '';
}
''');
        final normalizedRoot = tempDir.resolveSymbolicLinksSync();
        final normalizedSource = source.resolveSymbolicLinksSync();
        final collection = AnalysisContextCollection(
          includedPaths: [normalizedRoot],
        );
        addTearDown(collection.dispose);
        final resolved = await collection
            .contextFor(normalizedSource)
            .currentSession
            .getResolvedUnit(normalizedSource);
        expect(resolved, isA<ResolvedUnitResult>());
        final unit = (resolved as ResolvedUnitResult).unit;

        final annotationFailures = <Object>[];
        _walk(unit, ZukeAnnotationVisitor(annotationFailures.add));
        expect(annotationFailures, hasLength(3));

        const index = ZukeIndex(
          inputDigest: 'input',
          generatedManifestDigest: 'manifest',
          generatedManifestPath: 'manifest.json',
          inputs: [],
          requirementIds: {'RULE-KNOWN'},
          controlIds: {'CTRL-KNOWN'},
          bindingIds: {'binding.known'},
        );
        final unknownIds = <Object>[];
        _walk(unit, ZukeUnknownIdVisitor(index, unknownIds.add));
        expect(unknownIds, hasLength(5));

        const verifiedIndex = ZukeIndex(
          inputDigest: 'input',
          generatedManifestDigest: 'manifest',
          generatedManifestPath: 'manifest.json',
          inputs: [],
          requirementIds: {'RULE-KNOWN'},
          controlIds: {'CTRL-KNOWN'},
          bindingIds: {'binding.known'},
          verifiedRequirementIds: {'RULE-KNOWN'},
          // A hand-built index has to carry the claim itself; only the ZukeIndex
          // factories backfill claims from the flat set.
          verifiedClaims: [ZukeImplementationClaim(id: 'RULE-KNOWN')],
        );
        final missingWhenVerified = <Object>[];
        _walk(
          unit,
          ZukeMissingTestVisitor(verifiedIndex, missingWhenVerified.add),
        );
        expect(missingWhenVerified, isEmpty);

        const unverifiedIndex = ZukeIndex(
          inputDigest: 'input',
          generatedManifestDigest: 'manifest',
          generatedManifestPath: 'manifest.json',
          inputs: [],
          requirementIds: {'RULE-KNOWN'},
          controlIds: {'CTRL-KNOWN'},
          bindingIds: {'binding.known'},
        );
        final missingTests = <Object>[];
        _walk(unit, ZukeMissingTestVisitor(unverifiedIndex, missingTests.add));
        expect(missingTests, hasLength(3));
      },
    );

    test(
      'unimplemented generated requirements are reported per constant',
      () async {
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
          'name: contract_fixture\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
        );
        final generated = Directory('${tempDir.path}/lib/src/generated')
          ..createSync(recursive: true);
        final contract =
            File('${generated.path}/feat_demo_001_contracts.g.dart')
              ..writeAsStringSync('''
abstract final class FeatDemo001RequirementIds {
  static const implemented = 'RULE-DEMO-IMPLEMENTED';
  static const implementedId = 'RULE-DEMO-IMPLEMENTED';
  static const missing = 'RULE-DEMO-MISSING';
  static const missingId = 'RULE-DEMO-MISSING';
  static const notDeclared = 'RULE-DEMO-UNDECLARED';
}
''');
        final normalizedRoot = tempDir.resolveSymbolicLinksSync();
        final normalizedContract = contract.resolveSymbolicLinksSync();
        final collection = AnalysisContextCollection(
          includedPaths: [normalizedRoot],
        );
        addTearDown(collection.dispose);
        final resolved = await collection
            .contextFor(normalizedContract)
            .currentSession
            .getResolvedUnit(normalizedContract);
        final unit = (resolved as ResolvedUnitResult).unit;

        const index = ZukeIndex(
          inputDigest: 'input',
          generatedManifestDigest: 'manifest',
          generatedManifestPath: 'manifest.json',
          inputs: [],
          requirementIds: {'RULE-DEMO-IMPLEMENTED', 'RULE-DEMO-MISSING'},
          controlIds: {},
          bindingIds: {},
          implementedRequirementIds: {'RULE-DEMO-IMPLEMENTED'},
          // A hand-built index has to carry the claim itself; only the
          // ZukeIndex factories backfill claims from the flat set.
          implementationClaims: [
            ZukeImplementationClaim(id: 'RULE-DEMO-IMPLEMENTED'),
          ],
        );

        final reported = <String>[];
        final anchors = <AstNode>[];
        _walk(
          unit,
          ZukeUnimplementedRequirementVisitor(
            index: index,
            targetId: 'backend',
            report: (anchor, id) {
              anchors.add(anchor);
              reported.add(id);
            },
          ),
        );

        // Only the genuinely unimplemented, declared ID. The implemented one, the
        // duplicate constant carrying the same ID, and the ID the workspace never
        // declared are all correctly left alone — and the duplicate must not
        // produce a second finding for one requirement.
        expect(reported, ['RULE-DEMO-MISSING']);
        expect(anchors, hasLength(1));
        // The anchor is the constant itself, so the Problems pane points at the
        // declaration rather than the top of the file.
        expect(anchors.single, isA<VariableDeclaration>());
        expect((anchors.single as VariableDeclaration).name.lexeme, 'missing');
      },
    );

    test('unimplemented requirements are scoped to the analyzed target', () async {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: scoping_fixture\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );
      final generated = Directory('${tempDir.path}/lib/src/generated')
        ..createSync(recursive: true);
      final contract = File('${generated.path}/feat_scope_001_contracts.g.dart')
        ..writeAsStringSync('''
abstract final class FeatScope001RequirementIds {
  static const backendOnly = 'RULE-SCOPE-BACKEND';
  static const bothTargets = 'RULE-SCOPE-BOTH';
}
''');
      final normalizedRoot = tempDir.resolveSymbolicLinksSync();
      final normalizedContract = contract.resolveSymbolicLinksSync();
      final collection = AnalysisContextCollection(
        includedPaths: [normalizedRoot],
      );
      addTearDown(collection.dispose);
      final resolved = await collection
          .contextFor(normalizedContract)
          .currentSession
          .getResolvedUnit(normalizedContract);
      final unit = (resolved as ResolvedUnitResult).unit;

      const index = ZukeIndex(
        inputDigest: 'input',
        generatedManifestDigest: 'manifest',
        generatedManifestPath: 'manifest.json',
        inputs: [],
        requirementIds: {'RULE-SCOPE-BACKEND', 'RULE-SCOPE-BOTH'},
        controlIds: {},
        bindingIds: {},
        requirementTargets: {
          'RULE-SCOPE-BACKEND': ['backend'],
          'RULE-SCOPE-BOTH': ['backend', 'flutter'],
        },
      );

      List<String> reportFor(String? targetId) {
        final found = <String>[];
        _walk(
          unit,
          ZukeUnimplementedRequirementVisitor(
            index: index,
            targetId: targetId,
            report: (_, id) => found.add(id),
          ),
        );
        return found;
      }

      // A Flutter package must not be told it fails to implement a backend-only
      // requirement; a backend package must be told about everything it owns.
      expect(reportFor('flutter'), ['RULE-SCOPE-BOTH']);
      expect(reportFor('backend'), ['RULE-SCOPE-BACKEND', 'RULE-SCOPE-BOTH']);
      // An unattributable target never narrows: under-reporting is recoverable,
      // hiding a requirement because scoping metadata was missing is not.
      expect(reportFor(null), ['RULE-SCOPE-BACKEND', 'RULE-SCOPE-BOTH']);
    });

    test('a requirement claimed by another target is still reported', () async {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: cross_target_fixture\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );
      final generated = Directory('${tempDir.path}/lib/src/generated')
        ..createSync(recursive: true);
      final contract = File('${generated.path}/feat_scope_002_contracts.g.dart')
        ..writeAsStringSync('''
abstract final class FeatScope002RequirementIds {
  static const flutterOnly = 'RULE-SCOPE-FLUTTER';
}
''');
      final normalizedRoot = tempDir.resolveSymbolicLinksSync();
      final normalizedContract = contract.resolveSymbolicLinksSync();
      final collection = AnalysisContextCollection(
        includedPaths: [normalizedRoot],
      );
      addTearDown(collection.dispose);
      final resolved = await collection
          .contextFor(normalizedContract)
          .currentSession
          .getResolvedUnit(normalizedContract);
      final unit = (resolved as ResolvedUnitResult).unit;

      // The flat implemented set contains the ID, because *something*
      // implemented it. Only the claims say which target did.
      const index = ZukeIndex(
        inputDigest: 'input',
        generatedManifestDigest: 'manifest',
        generatedManifestPath: 'manifest.json',
        inputs: [],
        requirementIds: {'RULE-SCOPE-FLUTTER'},
        controlIds: {},
        bindingIds: {},
        implementedRequirementIds: {'RULE-SCOPE-FLUTTER'},
        requirementTargets: {
          'RULE-SCOPE-FLUTTER': ['flutter'],
        },
        packageTargets: {'apps/api': 'backend', 'apps/mobile': 'flutter'},
        implementationClaims: [
          ZukeImplementationClaim(id: 'RULE-SCOPE-FLUTTER', target: 'backend'),
        ],
      );

      List<String> reportFor(String? targetId) {
        final found = <String>[];
        _walk(
          unit,
          ZukeUnimplementedRequirementVisitor(
            index: index,
            targetId: targetId,
            report: (_, id) => found.add(id),
          ),
        );
        return found;
      }

      // The backend package is the only one claiming the requirement, and it
      // does not apply to the backend, so backend is satisfied. A flutter file
      // has implemented nothing that covers its own requirement and must say so:
      // reading the flat set here would suppress the finding entirely, and the
      // editor would disagree with `zuke validate`.
      expect(reportFor('backend'), isEmpty);
      expect(reportFor('flutter'), ['RULE-SCOPE-FLUTTER']);
      // An unpinned claim satisfies every target, so an unattributable file
      // never narrows.
      expect(reportFor(null), isEmpty);
    });

    test('a test verified for another target does not satisfy this one', () async {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: verification_target_fixture\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );
      final generated = Directory('${tempDir.path}/lib/src/generated')
        ..createSync(recursive: true);
      final source = File('${generated.path}/service.dart')
        ..writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

@ImplementsRequirement(['RULE-VERIFY-FLUTTER'])
void service() {}
''');
      final normalizedRoot = tempDir.resolveSymbolicLinksSync();
      final collection = AnalysisContextCollection(
        includedPaths: [normalizedRoot],
      );
      addTearDown(collection.dispose);
      final resolved = await collection
          .contextFor(source.resolveSymbolicLinksSync())
          .currentSession
          .getResolvedUnit(source.resolveSymbolicLinksSync());
      final unit = (resolved as ResolvedUnitResult).unit;

      // The flat verified set contains the ID because the backend package has a
      // test for it. Only the claims say which target that test covers.
      const index = ZukeIndex(
        inputDigest: 'input',
        generatedManifestDigest: 'manifest',
        generatedManifestPath: 'manifest.json',
        inputs: [],
        requirementIds: {'RULE-VERIFY-FLUTTER'},
        controlIds: {},
        bindingIds: {},
        verifiedRequirementIds: {'RULE-VERIFY-FLUTTER'},
        verifiedClaims: [
          ZukeImplementationClaim(id: 'RULE-VERIFY-FLUTTER', target: 'backend'),
        ],
      );

      List<String> reportFor(String? targetId) {
        final found = <String>[];
        _walk(
          unit,
          ZukeMissingTestVisitor(
            index,
            (_) => found.add('reported'),
            targetId: targetId,
          ),
        );
        return found;
      }

      // The only test belongs to the backend, so a flutter file implementing the
      // requirement genuinely has no test and must be told; the backend file's
      // test satisfies the backend.
      expect(reportFor('flutter'), ['reported']);
      expect(reportFor('backend'), isEmpty);
    });

    test('spec findings are reported on the owning feature contract', () async {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: spec_fixture\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );
      final generated = Directory('${tempDir.path}/lib/src/generated')
        ..createSync(recursive: true);
      final contract = File('${generated.path}/feat_dash_001_contracts.g.dart')
        ..writeAsStringSync('''
abstract final class FeatDash001RequirementIds {
  static const one = 'RULE-DASH-ONE';
}
''');
      final normalizedRoot = tempDir.resolveSymbolicLinksSync();
      final normalizedContract = contract.resolveSymbolicLinksSync();
      final collection = AnalysisContextCollection(
        includedPaths: [normalizedRoot],
      );
      addTearDown(collection.dispose);
      final resolved = await collection
          .contextFor(normalizedContract)
          .currentSession
          .getResolvedUnit(normalizedContract);
      final unit = (resolved as ResolvedUnitResult).unit;

      const index = ZukeIndex(
        inputDigest: 'input',
        generatedManifestDigest: 'manifest',
        generatedManifestPath: 'manifest.json',
        inputs: [],
        requirementIds: {'RULE-DASH-ONE'},
        controlIds: {},
        bindingIds: {},
        featureFiles: {
          'FEAT-DASH-001': 'lib/src/generated/feat_dash_001_contracts.g.dart',
        },
        specDiagnostics: [
          ZukeSpecDiagnostic(
            file: 'specs/features/dashboard.feature',
            line: 5,
            column: 5,
            code: 'ZUKE-REF-009',
            severity: 'error',
            message: 'Unknown target "nope"',
            featureId: 'FEAT-DASH-001',
          ),
          ZukeSpecDiagnostic(
            file: 'specs/features/other.feature',
            line: 9,
            column: 1,
            code: 'ZUKE-REF-001',
            severity: 'error',
            message: 'Unknown Epic "EPIC-X"',
            featureId: 'FEAT-OTHER-001',
          ),
        ],
      );

      // Only the findings whose feature generated *this* file are reported, so a
      // broken cross-reference appears once rather than in every contract.
      final findings = index.specDiagnostics
          .where(
            (finding) =>
                finding.featureId != null &&
                index
                    .featuresAtPath(
                      'lib/src/generated/feat_dash_001_contracts.g.dart',
                    )
                    .contains(finding.featureId),
          )
          .toList();
      expect(findings.map((f) => f.code), ['ZUKE-REF-009']);

      final anchors = <AstNode>[];
      final reported = <ZukeSpecDiagnostic>[];
      _walk(
        unit,
        ZukeSpecLintVisitor(
          findings: findings,
          report: (anchor, finding) {
            anchors.add(anchor);
            reported.add(finding);
          },
        ),
      );

      expect(reported, hasLength(1));
      expect(reported.single.message, contains('nope'));
      // The specification's own location is what makes the finding actionable,
      // because the squiggle cannot land on a .feature line.
      expect(reported.single.file, 'specs/features/dashboard.feature');
      expect(reported.single.line, 5);
      expect(reported.single.column, 5);
      // Anchored on the contract's class declaration, a real line in this file.
      expect(anchors.single, isA<ClassDeclaration>());
      expect(
        anchors.single.toSource(),
        startsWith('abstract final class FeatDash001RequirementIds'),
      );
    });

    test('a contract with no spec findings registers nothing', () async {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: clean_fixture\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );
      final generated = Directory('${tempDir.path}/lib/src/generated')
        ..createSync(recursive: true);
      final contract = File('${generated.path}/feat_ok_001_contracts.g.dart')
        ..writeAsStringSync('''
abstract final class FeatOk001RequirementIds {
  static const one = 'RULE-OK-ONE';
}
''');
      final normalizedRoot = tempDir.resolveSymbolicLinksSync();
      final normalizedContract = contract.resolveSymbolicLinksSync();
      final collection = AnalysisContextCollection(
        includedPaths: [normalizedRoot],
      );
      addTearDown(collection.dispose);
      final resolved = await collection
          .contextFor(normalizedContract)
          .currentSession
          .getResolvedUnit(normalizedContract);
      final unit = (resolved as ResolvedUnitResult).unit;

      final reported = <ZukeSpecDiagnostic>[];
      _walk(
        unit,
        ZukeSpecLintVisitor(
          findings: const [],
          report: (_, finding) => reported.add(finding),
        ),
      );
      expect(reported, isEmpty);
    });

    test('analysis-server index discovery fails closed at every boundary', () {
      final source = File('${tempDir.path}/nested/lib/app.dart');
      source.parent.createSync(recursive: true);
      source.writeAsStringSync('void main() {}');
      expect(
        analyzer_plugin.zukeIndexIsCurrentForTesting(source.absolute.path),
        isFalse,
      );

      File('${tempDir.path}/zuke.yaml').writeAsStringSync('schemaVersion: 2\n');
      expect(
        analyzer_plugin.zukeIndexIsCurrentForTesting(source.absolute.path),
        isFalse,
      );
      final malformed = File('${tempDir.path}/.zuke/analyzer-index.json');
      malformed.parent.createSync(recursive: true);
      malformed.writeAsStringSync('{}');
      expect(
        analyzer_plugin.zukeIndexIsCurrentForTesting(source.absolute.path),
        isFalse,
      );
    });

    test(
      'a managed test must declare which evidence types it publishes',
      () async {
        final lib = Directory('${tempDir.path}/lib')
          ..createSync(recursive: true);
        final source = File('${lib.path}/managed_test.dart')
          ..writeAsStringSync('''
import 'package:zuke/testing.dart';
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_core/zuke_core.dart';

final scenario = _Scenario();

void evidenceTypesCallback() {}

void missingArgument() {
  zukeTest(() {}, scenario: scenario);
}

void misleadingPositional() {
  zukeTest(evidenceTypesCallback, scenario: scenario);
}

void emptyList() {
  zukeTest(() {}, scenario: scenario, evidenceTypes: const []);
}

void emptySet() {
  zukeTest(() {}, scenario: scenario, evidenceTypes: <String>{});
}

void declared() {
  zukeTest(() {}, scenario: scenario, evidenceTypes: const ['unit']);
}

void selfEvidencing() {
  zukeUnit(() {}, scenario: scenario);
}

void notManaged() {
  test('plain', () {});
}

class _Scenario implements ZukeScenarioContract {
  @override
  ScenarioId get id => const ScenarioId('SCN-TEST-001');
  @override
  RuleId get requirementId => const RuleId('RULE-TEST-001');
  @override
  String get title => 'Test';
  @override
  Set<ControlId> get controlIds => const {};
}
''');
        final unit = await _resolveUnit(tempDir, source);

        final findings = <String>[];
        _walk(
          unit,
          ZukeMissingEvidenceTypesVisitor((node, declaresEmpty) {
            findings.add(
              '${_enclosingName(node)}:${declaresEmpty ? 'empty' : 'absent'}',
            );
          }),
        );

        // A managed call with no argument, or an empty collection, is the only
        // thing that throws under `zuke test`. Everything else is legitimate.
        expect(
          findings,
          containsAll([
            'missingArgument:absent',
            'misleadingPositional:absent',
            'emptyList:empty',
            'emptySet:empty',
          ]),
        );
        expect(findings, isNot(contains('declared:absent')));
        expect(
          findings,
          isNot(contains('selfEvidencing:absent')),
          reason: 'zukeUnit publishes "unit" itself',
        );
        expect(findings, isNot(contains('notManaged:absent')));
      },
    );

    test('a local zukeTest cannot impersonate the managed entry point', () async {
      // The negative control, committed rather than re-derived by mutating the
      // visitor. An earlier attempt to prove this by stubbing the identity
      // check edited the wrong file and appeared to pass, which is exactly what
      // a committed fixture prevents: if this call ever starts being reported,
      // the identity check has been weakened.
      //
      // It has to be a separate library. A local declaration shadows the
      // import for every unqualified call in the same file, so declaring it
      // beside the real calls would silently redirect *those* too and the
      // positive assertions would stop testing anything.
      final lib = Directory('${tempDir.path}/lib')..createSync(recursive: true);
      final source = File('${lib.path}/impostor.dart')
        ..writeAsStringSync('''
void zukeTest(
  void Function() body, {
  List<String> evidenceTypes = const [],
}) {
  body();
}

void localImpostor() {
  zukeTest(() {});
}
''');
      final unit = await _resolveUnit(tempDir, source);

      final findings = <AstNode>[];
      _walk(
        unit,
        ZukeMissingEvidenceTypesVisitor((node, _) => findings.add(node)),
      );

      expect(
        findings,
        isEmpty,
        reason:
            'library identity, not the spelling, decides what is managed. '
            'This call has no evidenceTypes but is not a managed registration.',
      );
    });

    test('the missing-evidence-types rule registers as a lint rule', () {
      final registry = _RecordingRegistry();
      analyzer_plugin.ZukePlugin().register(registry);
      expect(
        registry.rules
            .whereType<analyzer_plugin.ZukeMissingEvidenceTypesRule>(),
        hasLength(1),
      );
    });

    test('the missing-evidence-types rule only applies inside a workspace', () {
      // The guard that keeps the framework's own `zuke_runner` suite clean. A
      // `zukeTest` outside a Zuke workspace is an ordinary unit-test helper: no
      // managed run can reach the `ArgumentError`, and a plugin diagnostic
      // cannot be silenced with `// ignore:`, so reporting there would leave the
      // developer with no way to act on it.
      final lib = Directory('${tempDir.path}/lib')..createSync(recursive: true);
      final source = File('${lib.path}/app.dart')
        ..writeAsStringSync('void main() {}\n');
      final path = source.absolute.path;

      expect(
        analyzer_plugin.zukeMissingEvidenceTypesAppliesForTesting(path),
        isFalse,
        reason: 'no zuke.yaml yet, so this is not a managed workspace',
      );

      File('${tempDir.path}/zuke.yaml').writeAsStringSync('schemaVersion: 3\n');
      analyzer_plugin.zukeClearIndexCacheForTesting();

      expect(
        analyzer_plugin.zukeMissingEvidenceTypesAppliesForTesting(path),
        isTrue,
        reason: 'a managed registration can only exist in a workspace',
      );
    });
  });
}

Future<CompilationUnit> _resolveUnit(Directory root, File source) async {
  final collection = AnalysisContextCollection(
    includedPaths: [root.resolveSymbolicLinksSync()],
  );
  addTearDown(collection.dispose);
  final resolved = await collection
      .contextFor(source.resolveSymbolicLinksSync())
      .currentSession
      .getResolvedUnit(source.resolveSymbolicLinksSync());
  return (resolved as ResolvedUnitResult).unit;
}

/// The function or method enclosing a call, so findings read by call site.
String _enclosingName(AstNode node) {
  for (var current = node.parent; current != null; current = current.parent) {
    if (current is FunctionDeclaration) return current.name.lexeme;
    if (current is MethodDeclaration) return current.name.lexeme;
  }
  return '<top-level>';
}

/// System-temporary fixtures do not inherit this package's `.dart_tool`
/// directory. Give the analyzer the workspace package graph so resolved
/// annotation visitors exercise real elements after the extractor moved into
/// zuke_cli. A one-package config is insufficient because zuke_annotations
/// re-exports ScenarioId from zuke_core and the analyzer fails closed on any
/// unresolved import.
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

File _writeCurrentConfig(Directory root) {
  final config = File('${root.path}/zuke.yaml')
    ..writeAsStringSync('''
schemaVersion: 3
workspace:
  name: test
  root: .
specifications:
  features: []
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: test_pkg
        path: .
        roots: [lib]
''');
  return config;
}

void _walk(AstNode node, AstVisitor<void> visitor) {
  node.accept(visitor);
  for (final child in node.childEntities.whereType<AstNode>()) {
    _walk(child, visitor);
  }
}

class _RecordingRegistry implements PluginRegistry {
  final List<dynamic> rules = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #registerLintRule ||
        invocation.memberName == #registerWarningRule) {
      rules.add(invocation.positionalArguments.single);
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

List<String> _registeredFreshnessRules(String path) {
  final registry = _RecordingVisitorRegistry();
  final context = _FileRuleContext(path);
  analyzer_plugin.ZukeIndexStaleRule().registerNodeProcessors(
    registry,
    context,
  );
  analyzer_plugin.ZukeIndexUnusableRule().registerNodeProcessors(
    registry,
    context,
  );
  return registry.rules;
}

class _RecordingVisitorRegistry implements RuleVisitorRegistry {
  final rules = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #addCompilationUnit ||
        invocation.memberName == #addAnnotation) {
      rules.add(
        (invocation.positionalArguments.first as AbstractAnalysisRule).name,
      );
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

List<String> _registeredIndexRules(String path) {
  final registry = _RecordingVisitorRegistry();
  final context = _FileRuleContext(path);
  analyzer_plugin.ZukeMissingTestRule().registerNodeProcessors(
    registry,
    context,
  );
  analyzer_plugin.ZukeUnknownIndexIdRule().registerNodeProcessors(
    registry,
    context,
  );
  return registry.rules;
}

class _FileRuleContext implements RuleContext {
  @override
  final RuleContextUnit definingUnit;
  _FileRuleContext(String path) : definingUnit = _FileRuleContextUnit(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FileRuleContextUnit implements RuleContextUnit {
  @override
  final analyzer_fs.File file;
  _FileRuleContextUnit(String path)
    : file = PhysicalResourceProvider.INSTANCE.getFile(
        PhysicalResourceProvider.INSTANCE.pathContext.normalize(path),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
