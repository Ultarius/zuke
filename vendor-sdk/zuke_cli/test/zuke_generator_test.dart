import 'dart:io';

import 'package:zuke_cli/src/generator.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'helpers/schema3_workspace.dart';
import 'support/temporary_directory.dart';
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

    test('generates Dart contracts and step support for a Flutter workspace', () {
      writeSchema3Workspace(
        tempDir,
        name: 'test-app',
        target: 'flutter',
        packageId: 'test-app',
        framework: 'flutter',
        roots: const ['lib', 'test'],
        sourceAdapter: 'dart-source',
        sourceCompatibilityId: 'dart-source-package-v1',
        runnerCompatibilityId: 'flutter-runner-v1',
        contractOutput: 'lib/src/generated',
        generatedStepsOutput: 'test/support/generated',
      );

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
      final barrel = result.files.firstWhere(
        (f) => f.path.endsWith('/sample_contracts.dart'),
      );
      expect(barrel.content, startsWith('// GENERATED. DO NOT EDIT.'));
      expect(barrel.content, isNot(contains('_steps.g.dart')));
      expect(barrel.content, contains('generatedScenarioContracts'));

      final windowsPaths = generator.generate(
        workspace: discovery,
        outputDir: r'lib\custom',
        exportPath: r'lib\api\contracts.dart',
      );
      expect(windowsPaths.errors, isEmpty);
      expect(
        windowsPaths.files.last.content,
        contains("'../custom/feat_sample_001_contracts.g.dart'"),
      );
      final packageImports = generator.generate(
        workspace: discovery,
        outputDir: r'packages\contracts\lib\custom',
        exportPath: r'packages\contracts\lib\api\contracts.dart',
        contractPackage: ContractPackage(
          name: 'actual_contracts',
          libPath: r'packages\contracts\lib',
        ),
      );
      expect(packageImports.errors, isEmpty);
      expect(
        packageImports.files.last.content,
        contains(
          "import 'package:actual_contracts/custom/feat_sample_001_contracts.g.dart' as c0;",
        ),
      );
      expect(
        packageImports.files.last.content,
        contains(
          "export 'package:actual_contracts/custom/feat_sample_001_contracts.g.dart'",
        ),
      );
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
    });

    test('generates pure-Dart step support for a non-Flutter runner', () {
      writeSchema3Workspace(
        tempDir,
        name: 'test-app',
        target: 'backend',
        packageId: 'test-app',
        framework: 'dart',
        roots: const ['lib', 'test'],
        sourceAdapter: 'dart-source',
        sourceCompatibilityId: 'dart-source-package-v1',
        runnerCompatibilityId: 'dart-runner-v1',
        runnerId: 'sample-api-tests',
        contractOutput: 'lib/src/generated',
        generatedStepsOutput: 'test/support/generated',
      );

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
      writeSchema3Workspace(
        tempDir,
        name: 'test-app',
        target: 'flutter',
        packageId: 'test-app',
        framework: 'flutter',
        roots: const ['lib', 'test'],
      );

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

    test('names colliding control constants without duplicate members', () {
      writeSchema3Workspace(
        tempDir,
        name: 'test-app',
        target: 'backend',
        packageId: 'test-app',
        framework: 'dart',
        roots: const ['lib', 'test'],
        contractOutput: 'lib/src/generated',
      );

      Directory('${tempDir.path}/specs/features').createSync(recursive: true);
      File(
        '${tempDir.path}/specs/features/collision.feature',
      ).writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-COLLISION-001
# targets:
#   - backend
# spec-end

@FEAT-COLLISION-001
Feature: Control name collision
  # rule-spec-begin
  # id: RULE-COLLISION-001
  # requires:
  #   - kind: control
  #     id: CTRL-CART-VALIDATION
  #   - kind: control
  #     id: CTRL-PROMO-VALIDATION
  # rule-spec-end
  @RULE-COLLISION-001
  Rule: Control names remain unique
    @SCN-COLLISION-001
    Scenario: The generated constants compile
      Given the API is healthy
''');

      final discovery = WorkspaceDiscovery().discover(tempDir.path);
      final result = DartContractGenerator().generate(
        workspace: discovery,
        outputDir: '${tempDir.path}/lib/src/generated',
      );

      expect(result.errors, isEmpty);
      final contracts = result.files.firstWhere(
        (file) => file.path.contains('feat_collision_001_contracts.g.dart'),
      );
      expect(contracts.content, contains('static const validation ='));
      expect(contracts.content, contains('static const promoValidation ='));
    });
  });
}
