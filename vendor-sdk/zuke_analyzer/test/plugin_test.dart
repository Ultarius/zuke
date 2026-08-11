import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
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

    tearDown(() => _deleteDirectoryWithRetry(tempDir));

    test(
      'analyzer plugin extracts diagnostics from out-of-date index',
      () async {
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
          'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <3.11.0"\n',
        );
        final libDir = Directory('${tempDir.path}/lib')
          ..createSync(recursive: true);
        File('${libDir.path}/app.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

@ImplementsRequirement([])
class MyService {}
''');

        final diagnostics = await ZukeAnalyzer().analyzePackage(tempDir.path);
        expect(diagnostics.any((d) => d.code == 'ZUKE-ANNOTATION-001'), isTrue);
      },
    );

    test('analyzer plugin results agree with CLI extract results', () async {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <3.11.0"\n',
      );
      final libDir = Directory('${tempDir.path}/lib')
        ..createSync(recursive: true);
      File('${libDir.path}/app.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

@ImplementsRequirement(['RULE-TEST-001'])
class ValidService {}

class NoAnnotation {}
''');

      final pluginDiagnostics = await ZukeAnalyzer().analyzePackage(
        tempDir.path,
      );
      final extractOutput = await DartExtractor().extract(
        tempDir.path,
        roots: ['lib'],
      );
      final extractErrors = extractOutput.errors;
      expect(pluginDiagnostics.length, equals(extractErrors.length));
      for (var i = 0; i < pluginDiagnostics.length; i++) {
        expect(pluginDiagnostics[i].message, equals(extractErrors[i]));
      }
    });

    test('reports a missing workspace index as stale', () async {
      File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 2
specifications:
  features: [specs/features/**/*.feature]
''');
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <3.11.0"\n',
      );
      (Directory('${tempDir.path}/lib')..createSync(recursive: true));

      final diagnostics = await ZukeAnalyzer().analyzePackage(tempDir.path);
      expect(diagnostics.any((d) => d.code == 'ZUKE-INDEX-STALE'), isTrue);
    });

    test('current index reports unknown IDs and duplicate bindings', () async {
      final config = File('${tempDir.path}/zuke.yaml')
        ..writeAsStringSync('''
schemaVersion: 2
specifications:
  features: [specs/features/**/*.feature]
''');
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <3.11.0"\n',
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

    test('plugin registers all rules with stable names and diagnostics', () {
      final registry = _RecordingRegistry();

      analyzer_plugin.plugin.register(registry);

      expect(registry.rules, hasLength(3));
      expect(
        registry.rules.map((rule) => rule.name),
        containsAll([
          'zuke_annotation',
          'zuke_index_stale',
          'zuke_unknown_index_id',
        ]),
      );
      expect(
        analyzer_plugin.ZukeAnnotationRule().diagnosticCode.name,
        'zuke_annotation',
      );
      expect(
        analyzer_plugin.ZukeIndexStaleRule().diagnosticCode.name,
        'zuke_index_stale',
      );
      expect(
        analyzer_plugin.ZukeUnknownIndexIdRule().diagnosticCode.name,
        'zuke_unknown_index_id',
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
      },
    );

    test('analysis-server index discovery fails closed at every boundary', () {
      expect(analyzer_plugin.zukeIndexIsCurrentForTesting(null), isFalse);
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
  });
}

/// System-temporary fixtures do not inherit this package's `.dart_tool`
/// directory. Give the analyzer the workspace package graph so resolved
/// annotation visitors exercise real elements after the extractor moved into
/// zuke_cli. A one-package config is insufficient because zuke_annotations
/// re-exports ScenarioId from zuke_core and the analyzer fails closed on any
/// unresolved import.
void _writePackageConfig(Directory root) {
  final workspaceConfig = File(
    '${Directory.current.path}${Platform.pathSeparator}.dart_tool'
    '${Platform.pathSeparator}package_config.json',
  );
  final decoded = jsonDecode(workspaceConfig.readAsStringSync()) as Map;
  final packageConfigDirectory = workspaceConfig.parent.uri;
  final packages = (decoded['packages'] as List).whereType<Map>().map((entry) {
    final copy = Map<String, Object?>.from(entry);
    final rootUri = Uri.parse(copy['rootUri'] as String);
    copy['rootUri'] = (rootUri.isAbsolute
            ? rootUri
            : packageConfigDirectory.resolveUri(rootUri))
        .toString();
    return copy;
  }).toList();
  final config = Directory('${root.path}/.dart_tool')..createSync();
  File('${config.path}/package_config.json').writeAsStringSync(
    jsonEncode({
      'configVersion': 2,
      'packages': packages,
    }),
  );
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  var attempts = 0;
  var delay = const Duration(milliseconds: 25);
  while (DateTime.now().isBefore(deadline)) {
    attempts++;
    if (!directory.existsSync()) return;
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(delay);
      delay = delay * 2;
      if (delay > const Duration(milliseconds: 500)) {
        delay = const Duration(milliseconds: 500);
      }
    }
  }
  throw StateError(
    'Unable to remove plugin fixture after $attempts attempt(s): '
    '${directory.path}',
  );
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
    if (invocation.memberName == #registerLintRule) {
      rules.add(invocation.positionalArguments.single);
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}
