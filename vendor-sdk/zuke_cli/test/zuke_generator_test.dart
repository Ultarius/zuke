import 'dart:io';

import 'package:zuke_cli/src/generator.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_test_support/zuke_test_support.dart';
import 'package:test/test.dart';

void main() {
  test('GeneratedFile stores path and content', () {
    final file = GeneratedFile(
      path: 'test.dart',
      content: 'void main() {}',
      hash: 'abc',
    );
    expect(file.path, 'test.dart');
    expect(file.content, 'void main() {}');
  });

  test('Manifest creates with entries', () {
    final entry = ManifestEntry(path: 'test.dart', contentHash: 'abc');
    final manifest = Manifest(entries: [entry]);
    expect(manifest.entries, hasLength(1));
    expect(manifest.entries.first.path, 'test.dart');
  });

  test('GenerationResult stores files and manifest', () {
    final result = GenerationResult(files: [], manifest: Manifest());
    expect(result.files, isEmpty);
    expect(result.errors, isEmpty);
  });

  group('DartContractGenerator', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('zuke_gen_test_');
    });

    tearDown(() => deleteTemporaryDirectory(tempDir));

    test(
      'generates Dart contracts and step support for a Flutter workspace',
      () {
        File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 2
workspace:
  name: test-app
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets:
  flutter:
    language: dart
    contractOutput: lib/src/generated
execution:
  runners:
    - id: sample-tests
      kind: gherkin
      target: flutter
      generatedStepsOutput: test/support/generated
''');

        Directory('${tempDir.path}/specs/features').createSync(recursive: true);
        File('${tempDir.path}/specs/features/sample.feature').writeAsStringSync(
          '''
# spec-begin
# schemaVersion: 1
# id: FEAT-SAMPLE-001
# targets:
#   - flutter
# bindings:
#   required:
#     - id: sample.button
#       target: flutter
#       cardinality: exactlyOne
#       instanceCardinality: oneOrMore
#       interaction: action
# spec-end

@FEAT-SAMPLE-001
Feature: Sample Feature
  Background:
    Given the app is open
  # rule-spec-begin
  # id: RULE-SAMPLE-001
  # rule-spec-end
  @RULE-SAMPLE-001
  Rule: Sample Rule
    @SCN-SAMPLE-001
    Scenario: Sample Scenario
      When the user taps "sample.button"
''',
        );

        final discovery = WorkspaceDiscovery().discover(tempDir.path);
        final generator = DartContractGenerator();

        final result = generator.generate(
          workspace: discovery,
          outputDir: '${tempDir.path}/lib/src/generated',
          exportPath: '${tempDir.path}/lib/sample_contracts.dart',
        );

        expect(result.errors, isEmpty);
        expect(result.files.length, greaterThanOrEqualTo(2));
        expect(
          result.files.any(
            (f) => f.path.contains('feat_sample_001_contracts.g.dart'),
          ),
          isTrue,
        );
        expect(
          result.files.any(
            (f) => f.path.contains('feat_sample_001_steps.g.dart'),
          ),
          isTrue,
        );
        final support = result.files.firstWhere(
          (f) => f.path.contains('feat_sample_001_steps.g.dart'),
        );
        expect(
          support.content,
          contains(
            "import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';",
          ),
        );
        expect(support.content, contains('theAppIsOpen'));
        final contracts = result.files.firstWhere(
          (f) => f.path.contains('feat_sample_001_contracts.g.dart'),
        );
        expect(
          contracts.content,
          contains('BindingInstanceCardinality.oneOrMore'),
        );
        expect(
          contracts.content,
          contains('tapButton(W world, Object instanceId)'),
        );
      },
    );

    test('generates pure-Dart step support for a non-Flutter runner', () {
      File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 2
workspace:
  name: test-app
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets:
  backend:
    language: dart
    contractOutput: lib/src/generated
execution:
  runners:
    - id: sample-api-tests
      kind: gherkin
      target: backend
      generatedStepsOutput: test/support/generated
''');

      Directory('${tempDir.path}/specs/features').createSync(recursive: true);
      File('${tempDir.path}/specs/features/sample.feature').writeAsStringSync(
        '''
# spec-begin
# schemaVersion: 1
# id: FEAT-SAMPLE-001
# targets:
#   - backend
# spec-end

@FEAT-SAMPLE-001
Feature: Sample Feature
  # rule-spec-begin
  # id: RULE-SAMPLE-001
  # rule-spec-end
  @RULE-SAMPLE-001
  Rule: Sample Rule
    @SCN-SAMPLE-001
    Scenario: Sample Scenario
      Given the API is healthy
''',
      );

      final discovery = WorkspaceDiscovery().discover(tempDir.path);
      final result = DartContractGenerator().generate(
        workspace: discovery,
        outputDir: '${tempDir.path}/lib/src/generated',
      );

      expect(result.errors, isEmpty);
      final support = result.files.firstWhere(
        (f) => f.path.contains('feat_sample_001_steps.g.dart'),
      );
      expect(support.content, contains("import 'package:zuke/zuke.dart';"));
      expect(support.content, isNot(contains('zuke_runner_flutter')));
      expect(support.content, contains("target: 'backend'"));
    });

    test('detects colliding member names and reports generation errors', () {
      File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 2
workspace:
  name: test-app
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets:
  flutter:
    language: dart
''');

      Directory('${tempDir.path}/specs/features').createSync(recursive: true);
      File('${tempDir.path}/specs/features/bad.feature').writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-BAD-001
# targets:
#   - flutter
# bindings:
#   required:
#     - id: bad.submit-button
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
#     - id: bad.submit_button
#       target: flutter
#       cardinality: exactlyOne
#       interaction: action
# spec-end

@FEAT-BAD-001
Feature: Bad Feature
''');

      final discovery = WorkspaceDiscovery().discover(tempDir.path);
      final generator = DartContractGenerator();

      final result = generator.generate(
        workspace: discovery,
        outputDir: '${tempDir.path}/lib/src/generated',
      );

      expect(result.errors, isNotEmpty);
      expect(result.errors.first, contains('generated invalid Dart'));
    });
  });
}
