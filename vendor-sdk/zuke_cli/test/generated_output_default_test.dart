import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/configuration_preflight.dart';
import 'package:zuke_cli/src/extraction_service.dart';

import 'cli_test_helper.dart';
import 'support/resolved_workspace.dart';
import 'support/temporary_directory.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('zuke-output-default-');
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: fixture
environment:
  sdk: '>=3.10.0 <4.0.0'
''');
    await configureFixturePackages(root);
    File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: fixture
  root: .
specifications:
  features: [specs/features/*.feature]
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: fixture
        path: .
        roots: [lib]
''');
    final feature = File('${root.path}/specs/features/fixture.feature');
    feature.parent.createSync(recursive: true);
    feature.writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-FIXTURE-001
# spec-end
Feature: Fixture
  # rule-spec-begin
  # id: RULE-FIXTURE-001
  # rule-spec-end
  Rule: Preserves provenance
    @SCN-FIXTURE-001
    Scenario: trivial
      Given a constant input
''');
  });
  tearDown(() => deleteTemporaryDirectory(root));

  Future<void> generate() async {
    final result = await runInProcessCli([
      'generate',
      '--root',
      root.path,
      '--quiet',
    ]);
    expect(result.exitCode, 0, reason: result.stderr);
  }

  Future<String> provenance() async {
    final extraction = await ExtractionService().extract(
      requireCurrentWorkspace(root.path),
      includeEvidence: false,
    );
    expect(extraction.errors, isEmpty);
    return extraction.outputs.single.requirePublishedSourceDigest();
  }

  test('an omitted contractOutput keeps provenance across a rename', () async {
    expect(
      File('${root.path}/zuke.yaml').readAsStringSync(),
      isNot(contains('contractOutput')),
      reason: 'this test is about the default output',
    );
    await generate();
    final contract = File(
      '${root.path}/lib/src/generated/feat_fixture_001_contracts.g.dart',
    );
    final originalContract = contract.readAsStringSync();
    final before = await provenance();

    final feature = File('${root.path}/specs/features/fixture.feature');
    feature.writeAsStringSync(
      feature.readAsStringSync().replaceFirst(
        'Scenario: trivial',
        'Scenario: renamed without changing its steps',
      ),
    );
    await generate();

    expect(contract.readAsStringSync(), isNot(originalContract));
    expect(await provenance(), before);
  });
}
