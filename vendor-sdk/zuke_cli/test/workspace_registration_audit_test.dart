import 'dart:io';
import 'package:test/test.dart';
import 'package:zuke_cli/zuke_cli.dart';
import 'package:zuke_cli/src/configuration_preflight.dart';
import 'package:zuke_cli/src/init_preset.dart';
import 'package:zuke_cli/src/proof_engine/identity_validator.dart';

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

  test('a caseId column gives rows readable, order-independent identity', () {
    final feature = File('${root.path}/specs/features/example.feature');
    void writeRows(List<String> rows) => feature.writeAsStringSync('''
# spec-begin
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
    Scenario Outline: Example <value>
      Given an example <value>
      Examples: Named rows
        | caseId    | value |
        ${rows.join('\n        ')}
''');
    void writeCases(String first, String second) =>
        testFile.writeAsStringSync('''
void main() {
  zukeTest(() {}, scenario: ExampleScenario.first, caseId: '$first');
  zukeTest(() {}, scenario: ExampleScenario.first, caseId: '$second');
}
''');

    writeCases('trusted', 'untrusted');
    for (final rows in const [
      ['| trusted   | one |', '| untrusted | two |'],
      ['| untrusted | two |', '| trusted   | one |'],
    ]) {
      writeRows(rows);
      final audit = const WorkspaceRegistrationAudit().inspect(root.path);
      expect(audit.diagnostics.map((item) => item.toJson()), isEmpty);
    }

    // A named row is no longer addressable by its position.
    writeCases('examples-1-row-1', 'examples-1-row-2');
    expect(
      const WorkspaceRegistrationAudit()
          .inspect(root.path)
          .diagnostics
          .map((item) => item.code),
      containsAll([
        'ZK-REGISTRATION-CASE-UNKNOWN',
        'ZK-REGISTRATION-CASE-MISSING',
      ]),
    );
  });

  test('Examples-level scenario IDs audit only their own rows', () {
    final feature = File('${root.path}/specs/features/example.feature');
    feature.writeAsStringSync('''
# spec-begin
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
    Scenario Outline: Example <value>
      Given an example <value>
      @SCN-EXAMPLE-001
      Examples: First value
        | value |
        | one   |
      @SCN-EXAMPLE-002
      Examples: Second value
        | value |
        | two   |
        | three |
''');
    final contracts = File('${root.path}/lib/contracts/example.g.dart');
    contracts.writeAsStringSync('''enum ExampleScenario {
  first(ScenarioId('SCN-EXAMPLE-001')), second(ScenarioId('SCN-EXAMPLE-002'));
  const ExampleScenario(this.id);
  final ScenarioId id;
}
abstract final class ExampleScenarios {
  static const all = [ExampleScenario.first, ExampleScenario.second];
}
''');
    testFile.writeAsStringSync('''
void main() {
  ZukeFlutterHarness<Object>(
    scenarios: ExampleScenarios.all,
  ).registerAll();
}
''');

    final workspace = requireCurrentWorkspace(root.path);
    expect(IdentityValidator().validate(workspace).errors, isEmpty);
    final audit = const WorkspaceRegistrationAudit().inspect(root.path);
    expect(audit.diagnostics.map((item) => item.toJson()), isEmpty);
    expect(
      audit.registrations.map((item) => '${item.scenarioId}:${item.caseId}'),
      unorderedEquals([
        'SCN-EXAMPLE-001:examples-1-row-1',
        'SCN-EXAMPLE-002:examples-2-row-1',
        'SCN-EXAMPLE-002:examples-2-row-2',
      ]),
    );

    RegistrationAuditResult directCases(
      String firstCase, {
      bool complete = false,
    }) {
      testFile.writeAsStringSync('''
void main() {
  zukeTest(() {}, scenario: ExampleScenario.first, caseId: 'examples-1-row-1');
  zukeTest(() {}, scenario: ExampleScenario.second, caseId: '$firstCase');
  ${complete ? "zukeTest(() {}, scenario: ExampleScenario.second, caseId: 'examples-2-row-2');" : ''}
}
''');
      return const WorkspaceRegistrationAudit().inspect(root.path);
    }

    expect(
      directCases('examples-1-row-1').diagnostics.map((item) => item.code),
      containsAll([
        'ZK-REGISTRATION-CASE-UNKNOWN',
        'ZK-REGISTRATION-CASE-MISSING',
      ]),
    );
    expect(
      directCases('examples-2-row-1').diagnostics.map((item) => item.code),
      ['ZK-REGISTRATION-CASE-MISSING'],
    );
    expect(
      directCases('examples-2-row-1', complete: true).diagnostics,
      isEmpty,
    );

    feature.writeAsStringSync(
      feature.readAsStringSync().replaceFirst('@SCN-EXAMPLE-002', '@release'),
    );
    final incomplete = requireCurrentWorkspace(root.path);
    expect(
      IdentityValidator().validate(incomplete).errors.map((item) => item.code),
      contains('ZUKE-ID-008'),
    );
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
