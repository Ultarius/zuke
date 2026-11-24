import 'package:test/test.dart';

import 'support/managed_binding_fixture.dart';

void main() {
  group('scenario harness evidence kinds', () {
    final batch = ManagedHarnessCases();
    const oneCase =
        '    FlutterEvidenceCase(scenario: demo, body: (tester) async {}),';
    const defaultHarness = '''
const evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: ['flutter-widget', 'gherkin-ui'],
);
''';

    batch.testKinds(
      'a case inherits the harness default',
      harness: defaultHarness,
      cases: oneCase,
      expected: ['flutter-widget', 'gherkin-ui'],
    );

    batch.testKinds(
      'two harnesses declaring the same default are not ambiguous',
      harness:
          '''
$defaultHarness
const other = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'other-runner-v1',
  defaultEvidenceTypes: ['gherkin-ui', 'flutter-widget'],
);
''',
      cases: oneCase,
      expected: ['flutter-widget', 'gherkin-ui'],
    );

    batch.testKinds(
      'a second harness with different defaults does not blur this one',
      harness: '''
const evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: ['flutter-widget'],
);
const other = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'other-runner-v1',
  defaultEvidenceTypes: ['gherkin-api'],
);
''',
      cases: oneCase,
      expected: ['flutter-widget'],
    );

    final attributed = batch.add('''
const otherScenario = FakeScenario(
  ScenarioId('SCN-DEMO-002'),
  RuleId('RULE-DEMO-001'),
  'Another demo scenario',
  <ControlId>{},
);

const readableHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'readable-runner-v1',
  defaultEvidenceTypes: ['flutter-widget'],
);
final dynamicHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'dynamic-runner-v1',
  defaultEvidenceTypes: buildKinds(),
);

void main() {
  readableHarness.registerAll([
    FlutterEvidenceCase(scenario: demo, body: (tester) async {}),
  ]);
  dynamicHarness.registerAll([
    FlutterEvidenceCase(scenario: otherScenario, body: (tester) async {}),
  ]);
}
''');
    test('a case is attributed to the harness that registers it', () async {
      expect(
        {
          for (final claim in await attributed())
            claim.scenarioId: claim.evidenceTypes,
        },
        {
          'SCN-DEMO-001': ['flutter-widget'],
          'SCN-DEMO-002': null,
        },
      );
    });

    batch.testKinds(
      'a case override that cannot be read is unknown, not the default',
      harness: defaultHarness,
      cases:
          '    FlutterEvidenceCase(scenario: demo, body: (t) async {}, '
          'evidenceTypes: buildKinds()),',
      expected: isNull,
    );

    batch.testKinds(
      'an unreadable harness default stays unknown',
      harness: '''
final evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: buildKinds(),
);
''',
      cases: oneCase,
      expected: isNull,
    );

    batch.testKinds(
      'an explicitly empty harness default publishes no kinds',
      harness: '''
const evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: [],
);
''',
      cases: oneCase,
      expected: isEmpty,
    );

    // A required argument can be temporarily missing while editing.
    batch.testKinds(
      'an absent harness default does not poison a readable one',
      harness:
          '''
$defaultHarness
final other = ZukeFlutterEvidenceHarness(runnerCompatibilityId: 'other-runner-v1');
''',
      cases: oneCase,
      expected: ['flutter-widget', 'gherkin-ui'],
    );

    batch.testKinds(
      'an absent harness default alone leaves the case undecidable',
      harness: '''
const evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
);
''',
      cases: oneCase,
      expected: isNull,
    );

    group('unresolved scenario lists', () {
      final fixture = ManagedBindingFixture();
      for (final (description, expression) in const [
        (
          'a partly readable scenario list remains incomplete',
          'missingScenario()',
        ),
        ('a scenario spread is not silently omitted', '...moreScenarios()'),
      ]) {
        test(description, () async {
          fixture.contract();
          fixture.source('app/test/steps_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';

void main() {
  ZukeFlutterHarness(
    scenarios: [demo, $expression],
    feature: null as dynamic,
    registryFactory: () => [],
    worldFactory: (tester) => null as dynamic,
    runnerId: 'app-tests',
    runnerCompatibilityId: 'app-runner-v1',
  ).registerAll();
}
''');
          final result = await fixture.scan();
          expect(result.managedScenarioIds, {'SCN-DEMO-001'});
          expect(result.unresolvedManagedRegistrations, 1);
        });
      }
    });

    final singular = batch.add('''
class DemoWorld {}

void main() {
  ZukeFlutterHarness<DemoWorld>(
    feature: null as dynamic,
    scenarios: [demo],
    registryFactory: () => <DemoWorld, Object>[],
    worldFactory: (tester) => DemoWorld(),
    runnerId: 'app-tests',
    runnerCompatibilityId: 'app-runner-v1',
    evidenceType: 'custom-ui',
  ).registerAll();
}
''');
    test('a literal singular evidenceType reads as a kind', () async {
      expect((await singular()).single.evidenceTypes, ['custom-ui']);
    });
  });
}
