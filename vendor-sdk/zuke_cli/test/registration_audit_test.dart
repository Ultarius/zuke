import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke/runner.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_cli/zuke_cli.dart';

void main() {
  test('rejects mutable aliases and restores aliases after nested blocks', () {
    final root = Directory.systemTemp.createTempSync('zuke-alias-scope-');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = File('${root.path}/example_test.dart')
      ..writeAsStringSync('''
enum FixtureScenario {
  first(ScenarioId('SCN-FIRST')), second(ScenarioId('SCN-SECOND'));
  const FixtureScenario(this.id);
  final ScenarioId id;
}
void main() {
  var mutable = FixtureScenario.first;
  mutable = FixtureScenario.second;
  zukeUnit(() {}, scenario: mutable);
  final selected = FixtureScenario.first;
  {
    final selected = FixtureScenario.second;
    zukeUnit(() {}, scenario: selected);
  }
  final callback = (selected) {
    zukeUnit(() {}, scenario: selected);
  };
  callback(FixtureScenario.second);
  zukeUnit(() {}, scenario: selected);
}
''');
    final result = const RegistrationAudit().inspectFiles([source]);
    expect(result.passed, isFalse);
    expect(result.registrations.map((entry) => entry.scenarioId), [
      null,
      'SCN-SECOND',
      null,
      'SCN-FIRST',
    ]);
    expect(result.diagnostics, isNotEmpty);
  });

  test(
    'inspects actual registrations and ignores comments and unused aliases',
    () {
      final root = Directory.systemTemp.createTempSync('zuke-registration-');
      try {
        final generated = File('${root.path}/generated.dart')
          ..writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
enum FeatExampleScenario implements ZukeScenarioContract {
  happy(ScenarioId('SCN-HAPPY'), RuleId('RULE-HAPPY'), 'happy', <ControlId>{});
  const FeatExampleScenario(this.id, this.requirementId, this.title, this.controlIds);
  final ScenarioId id;
  final RuleId requirementId;
  final String title;
  final Set<ControlId> controlIds;
}
''');
        final source = File('${root.path}/example_test.dart')
          ..writeAsStringSync('''enum FixtureScenario {
  id0(ScenarioId('SCN-UNUSED'));
  const FixtureScenario(this.id);
  final ScenarioId id;
}

// zukeTest('SCN-COMMENT', () {}, scenario: unused);
final unused = FixtureScenario.id0;
final scenario = FeatExampleScenario.happy;
void main() {
  zukeTest('happy', () async {}, scenario: scenario, caseId: 'primary');
}
''');

        final result = const RegistrationAudit().inspectFiles(
          [source, generated],
          expectedScenarioIds: {'SCN-HAPPY'},
        );

        expect(result.passed, isTrue);
        expect(result.registrations, hasLength(1));
        expect(result.registrations.single.scenarioId, 'SCN-HAPPY');
        expect(result.registrations.single.caseId, 'primary');
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('recognizes the canonical zukeUnit registration helper', () {
    final file =
        File.fromUri(
          Uri.file(
            '${Directory.systemTemp.path}${Platform.pathSeparator}unit_test.dart',
          ),
        )..writeAsStringSync('''enum FixtureScenario {
  id0(ScenarioId('SCN-UNIT'));
  const FixtureScenario(this.id);
  final ScenarioId id;
}

void main() {
  zukeUnit(() async {}, scenario: FixtureScenario.id0);
}
''');
    try {
      final result = const RegistrationAudit().inspectFiles(
        [file],
        expectedScenarioIds: {'SCN-UNIT'},
      );
      expect(result.passed, isTrue);
      expect(result.registrations.single.runner, 'zukeUnit');
      expect(result.registrations.single.caseId, 'SCN-UNIT');
    } finally {
      file.deleteSync();
    }
  });

  test('does not trust a helper name and scenario-shaped string', () {
    final root = Directory.systemTemp.createTempSync('zuke-forged-contract-');
    try {
      final file = File('${root.path}/forged_test.dart')
        ..writeAsStringSync('''
Object contractFor(String id) => Object();
void main() {
  zukeUnit(() {}, scenario: contractFor('SCN-UNIT'));
}
''');
      final result = const RegistrationAudit().inspectFiles(
        [file],
        expectedScenarioIds: {'SCN-UNIT'},
      );
      expect(result.passed, isFalse);
      expect(result.registrations.single.scenarioId, isNull);
      expect(
        result.diagnostics.map((d) => d.code),
        contains('ZK-REGISTRATION-DYNAMIC'),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('resolves generated public scenario aliases', () {
    final root = Directory.systemTemp.createTempSync(
      'zuke-registration-alias-',
    );
    try {
      final generated = File('${root.path}/generated.dart')
        ..writeAsStringSync('''
enum FeatExampleScenario {
  happy(ScenarioId('SCN-HAPPY'));
  const FeatExampleScenario(this.id);
  final ScenarioId id;
}
abstract final class ExampleScenarios {
  static const happy = FeatExampleScenario.happy;
}
''');
      final source = File('${root.path}/example_test.dart')
        ..writeAsStringSync('''
void main() {
  zukeTest('happy', () async {}, scenario: ExampleScenarios.happy);
}
''');

      final result = const RegistrationAudit().inspectFiles(
        [source, generated],
        expectedScenarioIds: {'SCN-HAPPY'},
      );

      expect(result.passed, isTrue);
      expect(result.registrations.single.scenarioId, 'SCN-HAPPY');
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  for (final declaration in [
    'static var selected = FeatExampleScenario.first;',
    'void unused() { final selected = FeatExampleScenario.first; }',
    'final selected = FeatExampleScenario.first;',
  ]) {
    test('does not trust non-static or mutable aliases: $declaration', () {
      final root = Directory.systemTemp.createTempSync(
        'zuke-registration-mutable-class-alias-',
      );
      try {
        final generated = File('${root.path}/generated.dart')
          ..writeAsStringSync('''
enum FeatExampleScenario {
  first(ScenarioId('SCN-FIRST')),
  second(ScenarioId('SCN-SECOND'));
  const FeatExampleScenario(this.id);
  final ScenarioId id;
}
abstract final class ExampleScenarios {
  $declaration
}
''');
        final source = File('${root.path}/example_test.dart')
          ..writeAsStringSync('''
void main() {
  ExampleScenarios.selected = FeatExampleScenario.second;
  zukeTest('selected', () async {}, scenario: ExampleScenarios.selected);
}
''');

        final result = const RegistrationAudit().inspectFiles(
          [source, generated],
          expectedScenarioIds: {'SCN-SECOND'},
        );

        expect(result.passed, isFalse);
        expect(result.registrations.single.scenarioId, isNull);
        expect(
          result.diagnostics.map((diagnostic) => diagnostic.code),
          contains('ZK-REGISTRATION-DYNAMIC'),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  }

  test('reuses a prepared analyzer snapshot for later runner inspections', () {
    final root = Directory.systemTemp.createTempSync(
      'zuke-registration-snapshot-',
    );
    try {
      final source = File('${root.path}/example_test.dart')
        ..writeAsStringSync('''
enum FixtureScenario { first(ScenarioId('SCN-FIRST')); }
void main() {
  zukeUnit(() {}, scenario: FixtureScenario.first);
}
''');
      final audit = const RegistrationAudit();
      final snapshot = audit.prepareFiles([source]);
      source.writeAsStringSync('''
void main() {
  zukeUnit(() {}, scenario: readScenario());
}
''');

      final result = audit.inspectSnapshot(
        snapshot,
        files: [File(source.path)],
        expectedScenarioIds: {'SCN-FIRST'},
      );
      expect(result.passed, isTrue);
      expect(result.registrations.single.scenarioId, 'SCN-FIRST');
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('reports unsupported dynamic registration with a source location', () {
    final file =
        File.fromUri(
          Uri.file(
            '${Directory.systemTemp.path}${Platform.pathSeparator}dynamic_test.dart',
          ),
        )..writeAsStringSync('''
void main() {
  final scenario = readScenario();
  zukeTest('dynamic', () async {}, scenario: scenario);
}
''');
    try {
      final result = const RegistrationAudit().inspectFiles([file]);
      expect(result.passed, isFalse);
      expect(result.diagnostics.single.code, 'ZK-REGISTRATION-DYNAMIC');
      expect(result.diagnostics.single.line, 3);
    } finally {
      file.deleteSync();
    }
  });

  test('does not count registrations in an unused named helper', () {
    final file =
        File.fromUri(
          Uri.file(
            '${Directory.systemTemp.path}${Platform.pathSeparator}helper_test.dart',
          ),
        )..writeAsStringSync('''enum FixtureScenario {
  id0(ScenarioId('SCN-UNUSED')),
  id1(ScenarioId('SCN-USED'));
  const FixtureScenario(this.id);
  final ScenarioId id;
}

void unusedHelper() {
  zukeTest('unused', () async {}, scenario: FixtureScenario.id0);
}
void main() {
  zukeTest('used', () async {}, scenario: FixtureScenario.id1);
}
''');
    try {
      final result = const RegistrationAudit().inspectFiles(
        [file],
        expectedScenarioIds: {'SCN-USED'},
      );
      expect(result.registrations, hasLength(1));
      expect(
        result.diagnostics.map((diagnostic) => diagnostic.code),
        contains('ZK-REGISTRATION-UNREACHABLE'),
      );
    } finally {
      file.deleteSync();
    }
  });

  test('inspects generated scenarios registered by the Flutter harness', () {
    final root = Directory.systemTemp.createTempSync('zuke-flutter-harness-');
    try {
      final generated = File('${root.path}/generated.dart')
        ..writeAsStringSync('''
enum FeatExampleScenario {
  happy,
  rejected,
}
abstract final class FeatExampleScenarios {
  static const all = <Object>[
    FeatExampleScenario.happy,
    FeatExampleScenario.rejected,
  ];
}
''');
      final source = File('${root.path}/example_widget_test.dart')
        ..writeAsStringSync('''
void main() {
  ZukeFlutterHarness<Object>(
    scenarios: FeatExampleScenarios.all,
  ).registerAll();
}
''');

      // The source fixture uses the same generated enum shape as the real
      // contract output, including ScenarioId literals.
      generated.writeAsStringSync('''
enum FeatExampleScenario {
  happy(ScenarioId('SCN-HAPPY')),
  rejected(ScenarioId('SCN-REJECTED'));
  const FeatExampleScenario(this.id);
  final ScenarioId id;
}
abstract final class FeatExampleScenarios {
  static const all = <FeatExampleScenario>[
    FeatExampleScenario.happy,
    FeatExampleScenario.rejected,
  ];
}
''');

      final result = const RegistrationAudit().inspectFiles(
        [source, generated],
        expectedScenarioIds: {'SCN-HAPPY', 'SCN-REJECTED'},
      );
      expect(result.passed, isTrue);
      expect(result.registrations, hasLength(2));
      expect(
        result.registrations.map((registration) => registration.scenarioId),
        containsAll(<String?>['SCN-HAPPY', 'SCN-REJECTED']),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('inspects static cases registered by the Flutter evidence harness', () {
    final root = Directory.systemTemp.createTempSync(
      'zuke-flutter-evidence-harness-',
    );
    try {
      final generated = File('${root.path}/generated.dart')
        ..writeAsStringSync('''
enum FeatExampleScenario {
  happy(ScenarioId('SCN-HAPPY')),
  rejected(ScenarioId('SCN-REJECTED'));
  const FeatExampleScenario(this.id);
  final ScenarioId id;
}
''');
      final source = File('${root.path}/example_widget_test.dart')
        ..writeAsStringSync('''
void main() {
  const evidenceHarness = ZukeFlutterEvidenceHarness();
  evidenceHarness.registerAll([
    FlutterEvidenceCase(scenario: FeatExampleScenario.happy, body: (_) async => 'happy'),
    FlutterEvidenceCase(scenario: FeatExampleScenario.rejected, body: (_) async => 'rejected'),
  ]);
}
''');

      final result = const RegistrationAudit().inspectFiles(
        [source, generated],
        expectedScenarioIds: {'SCN-HAPPY', 'SCN-REJECTED'},
      );

      expect(result.passed, isTrue);
      expect(result.registrations, hasLength(2));
      expect(
        result.registrations.map((registration) => registration.scenarioId),
        containsAll(<String?>['SCN-HAPPY', 'SCN-REJECTED']),
      );
      expect(
        result.registrations.every(
          (registration) => registration.runner == 'zukeTestWidgets',
        ),
        isTrue,
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('reports a commented-out registration as missing', () {
    final file =
        File.fromUri(
          Uri.file(
            '${Directory.systemTemp.path}${Platform.pathSeparator}commented_test.dart',
          ),
        )..writeAsStringSync('''enum FixtureScenario {
  id0(ScenarioId('SCN-MISSING'));
  const FixtureScenario(this.id);
  final ScenarioId id;
}

// zukeTest('missing', () async {}, scenario: FixtureScenario.id0);
void main() {}
''');
    try {
      final result = const RegistrationAudit().inspectFiles(
        [file],
        expectedScenarioIds: {'SCN-MISSING'},
      );
      expect(
        result.diagnostics.single.code,
        'ZK-REGISTRATION-EXPECTED-MISSING',
      );
      expect(result.registrations, isEmpty);
    } finally {
      file.deleteSync();
    }
  });

  test('reports duplicate default identities while allowing distinct cases', () {
    final file =
        File.fromUri(
          Uri.file(
            '${Directory.systemTemp.path}${Platform.pathSeparator}duplicate_test.dart',
          ),
        )..writeAsStringSync('''enum FixtureScenario {
  id0(ScenarioId('SCN-DUPLICATE'));
  const FixtureScenario(this.id);
  final ScenarioId id;
}

void main() {
  zukeTest('one', () async {}, scenario: FixtureScenario.id0);
  zukeTest('duplicate', () async {}, scenario: FixtureScenario.id0);
  zukeTest('two', () async {}, scenario: FixtureScenario.id0, caseId: 'two');
}
''');
    try {
      final result = const RegistrationAudit().inspectFiles(
        [file],
        expectedScenarioIds: {'SCN-DUPLICATE'},
      );
      expect(
        result.diagnostics.map((diagnostic) => diagnostic.code),
        contains('ZK-REGISTRATION-DUPLICATE-IDENTITY'),
      );
      expect(result.registrations, hasLength(3));
    } finally {
      file.deleteSync();
    }
  });

  test('allows valid registrations excluded by the selected profile', () {
    final file =
        File.fromUri(
          Uri.file(
            '${Directory.systemTemp.path}${Platform.pathSeparator}profile_test.dart',
          ),
        )..writeAsStringSync('''enum FixtureScenario {
  id0(ScenarioId('SCN-NIGHTLY')),
  id1(ScenarioId('SCN-SELECTED'));
  const FixtureScenario(this.id);
  final ScenarioId id;
}

void main() {
  zukeTest('selected', () async {}, scenario: FixtureScenario.id1);
  zukeTest('nightly', () async {}, scenario: FixtureScenario.id0);
}
''');
    try {
      final result = const RegistrationAudit().inspectFiles(
        [file],
        expectedScenarioIds: {'SCN-SELECTED'},
        knownScenarioIds: {'SCN-SELECTED', 'SCN-NIGHTLY'},
      );
      expect(result.passed, isTrue);
      expect(result.registrations, hasLength(2));
    } finally {
      file.deleteSync();
    }
  });

  test('rejects blanket control proofs', () {
    final file =
        File.fromUri(
          Uri.file(
            '${Directory.systemTemp.path}${Platform.pathSeparator}blanket_controls.dart',
          ),
        )..writeAsStringSync('''enum FixtureScenario {
  id0(ScenarioId('SCN-CONTROL'));
  const FixtureScenario(this.id);
  final ScenarioId id;
}

void main() {
  final scenario = FixtureScenario.id0;
  zukeTest(
    'control',
    () async {},
    scenario: scenario,
    provedControls: scenario.controlIds,
  );
  zukeTest(
    'helper',
    () async {},
    scenario: scenario,
    caseId: 'helper',
    provedControls: controlsFor(scenario),
  );
}
''');
    try {
      final result = const RegistrationAudit().inspectFiles(
        [file],
        expectedScenarioIds: {'SCN-CONTROL'},
      );
      expect(
        result.diagnostics.map((diagnostic) => diagnostic.code),
        containsAll([
          'ZK-REGISTRATION-CONTROLS-BLANKET',
          'ZK-REGISTRATION-CONTROLS-BLANKET',
        ]),
      );
    } finally {
      file.deleteSync();
    }
  });

  test('reconciles registrations with fresh case-aware execution results', () {
    final registration = ZukeRegistration(
      file: 'test/example_test.dart',
      line: 4,
      column: 3,
      runner: 'zukeTest',
      target: 'backend',
      scenarioId: 'SCN-CASE',
      caseId: 'primary',
    );
    final execution = SuiteResult(
      executionId: 'exec-case',
      status: SuiteStatus.passed,
      requirementId: 'RULE-CASE',
      evidenceType: 'unit',
      target: 'backend',
      candidateId: 'SCN-CASE',
      caseId: 'primary',
      profile: 'pullRequest',
      runnerId: 'runner',
      runnerCompatibilityId: 'runner-v1',
      sourcePackage: 'app',
      sourceAdapter: 'dart-source',
      sourceCompatibilityId: 'dart-source-v1',
      resultDigest: 'sha256:${List.filled(64, 'a').join()}',
      scenarioIds: [ScenarioId('SCN-CASE')],
    );

    final passed = const RegistrationExecutionAudit().reconcile(
      registrations: [registration],
      executions: [execution],
      selectedScenarioIds: {'SCN-CASE'},
      target: 'backend',
    );
    expect(passed.passed, isTrue);

    final missing = const RegistrationExecutionAudit().reconcile(
      registrations: [registration],
      executions: const [],
      selectedScenarioIds: {'SCN-CASE'},
      target: 'backend',
    );
    expect(missing.diagnostics.single.code, 'ZK-EXECUTION-MISSING-CASE');
  });
}
