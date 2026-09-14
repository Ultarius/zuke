import 'dart:io';
import 'package:test/test.dart';
import 'package:zuke_cli/zuke_cli.dart';
import 'package:zuke_cli/src/init_preset.dart';

void main() {
  late Directory root;
  late File testFile;
  setUp(() {
    root = Directory.systemTemp.createTempSync('zuke-workspace-audit-');
    File('${root.path}/zuke.yaml').writeAsStringSync(
      InitPreset.dart
          .configuration(root)
          .replaceAll('lib/src/generated', 'lib/contracts'),
    );
    File('${root.path}/specs/features/example.feature')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''# spec-begin
# schemaVersion: 1
# id: FEAT-EXAMPLE-001
# spec-end
@FEAT-EXAMPLE-001
Feature: Example
  # rule-spec-begin
  # id: RULE-EXAMPLE-001
  # requiredEvidence: []
  # rule-spec-end
  @RULE-EXAMPLE-001
  Rule: Example rule
    @SCN-EXAMPLE-001
    Scenario: Example scenario
      Given an example
''');
    File('${root.path}/lib/contracts/example.g.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''enum ExampleScenario {
  first(ScenarioId('SCN-EXAMPLE-001'));
  const ExampleScenario(this.id);
  final ScenarioId id;
}
''');
    testFile = File('${root.path}/test/example_test.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''void main() {
  final example = ExampleScenario.first;
  zukeUnit(() {}, scenario: example);
}
''');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('discovers custom contract output and configured runner identity', () {
    final audit = const WorkspaceRegistrationAudit().inspect(root.path);
    expect(audit.diagnostics, isEmpty);
    expect(audit.registrations.single.scenarioId, 'SCN-EXAMPLE-001');
    expect(audit.registrations.single.target, 'app');
  });

  test('missing and unresolved registrations remain failures', () {
    testFile.writeAsStringSync('void main() {}');
    final missing = const WorkspaceRegistrationAudit().inspect(root.path);
    expect(
      missing.diagnostics.map((item) => item.code),
      contains('ZK-REGISTRATION-EXPECTED-MISSING'),
    );
    testFile.writeAsStringSync(
      'void main() { zukeUnit(() {}, scenario: unknown()); }',
    );
    final unknown = const WorkspaceRegistrationAudit().inspect(root.path);
    expect(unknown.passed, isFalse);
    expect(unknown.registrations.single.scenarioId, isNull);
  });

  test(
    'overlapping runner roots are deduplicated but distinct duplicate cases fail',
    () {
      final config = File('${root.path}/zuke.yaml');
      config.writeAsStringSync(
        config.readAsStringSync().replaceFirst('lock:', '''    - id: other-tests
      target: app
      sourcePackage: app
      sourceAdapter: dart-source
      sourceCompatibilityId: dart-source-package-v1
      runnerCompatibilityId: dart-test-v1
      executable: dart
      args: [test]
      workingDirectory: other
lock:'''),
      );
      final overlapping = const WorkspaceRegistrationAudit().inspect(root.path);
      expect(overlapping.diagnostics, isEmpty);
      expect(overlapping.registrations, hasLength(1));
      File('${root.path}/other/test/duplicate_test.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(testFile.readAsStringSync());
      final duplicate = const WorkspaceRegistrationAudit().inspect(root.path);
      expect(
        duplicate.diagnostics.map((item) => item.code),
        contains('ZK-REGISTRATION-DUPLICATE-IDENTITY'),
      );
    },
  );

  test(
    'malformed specifications cannot silently yield an empty scenario set',
    () {
      File(
        '${root.path}/specs/features/example.feature',
      ).writeAsStringSync('Feature: malformed');
      final result = const WorkspaceRegistrationAudit().inspect(root.path);
      expect(
        result.diagnostics.map((item) => item.code),
        contains('ZK-REGISTRATION-WORKSPACE-INVALID'),
      );
    },
  );
}
