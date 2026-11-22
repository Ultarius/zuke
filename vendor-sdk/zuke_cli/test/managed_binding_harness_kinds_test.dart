import 'package:test/test.dart';

import 'support/managed_binding_fixture.dart';

void main() {
  final fixture = ManagedBindingFixture();
  final source = fixture.source;
  final contract = fixture.contract;
  final scan = fixture.scan;
  final harnessKinds = fixture.harnessKinds;
  final twoHarnessKinds = fixture.twoHarnessKinds;

  group('scenario harness evidence kinds', () {
    const oneCase =
        '    FlutterEvidenceCase(scenario: demo, body: (tester) async {}),';

    test('a case inherits the harness default', () async {
      expect(
        await harnessKinds(
          harness: '''
const evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: ['flutter-widget', 'gherkin-ui'],
);
''',
          cases: oneCase,
        ),
        ['flutter-widget', 'gherkin-ui'],
      );
    });

    test(
      'two harnesses declaring the same default are not ambiguous',
      () async {
        // Compared by contents: two equal lists must collapse to one, or the
        // association reads as ambiguous and falls back to a default that
        // describes neither harness.
        expect(
          await harnessKinds(
            harness: '''
const evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: ['flutter-widget', 'gherkin-ui'],
);
const other = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'other-runner-v1',
  defaultEvidenceTypes: ['gherkin-ui', 'flutter-widget'],
);
''',
            cases: oneCase,
          ),
          ['flutter-widget', 'gherkin-ui'],
        );
      },
    );

    test(
      'a second harness with different defaults does not blur this one',
      () async {
        // Attribution follows the `registerAll` receiver, so a sibling harness
        // declaring something else cannot make this case undecidable. Under the
        // previous library-wide reading this was the ambiguity case.
        expect(
          await harnessKinds(
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
          ),
          ['flutter-widget'],
          reason: 'the registering harness decides, not the library',
        );
      },
    );

    test('a case is attributed to the harness that registers it', () async {
      // The case both harnesses could claim is decidable, and the one under the
      // unreadable harness is not. Nothing about the first depends on the second.
      expect(
        await twoHarnessKinds(
          readable: '''
const readableHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'readable-runner-v1',
  defaultEvidenceTypes: ['flutter-widget'],
);
''',
          unreadable: '''
final dynamicHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'dynamic-runner-v1',
  defaultEvidenceTypes: buildKinds(),
);
''',
        ),
        [
          // The readable harness's case keeps its kinds...
          ['flutter-widget'],
          // ...and the dynamic harness's case is unknown, not defaulted.
          isNull,
        ],
      );
    });

    test(
      'a case override that cannot be read is unknown, not the default',
      () async {
        // Falling through to the inherited default here would report coverage the
        // override may well remove.
        expect(
          await harnessKinds(
            harness: '''
const evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: ['flutter-widget', 'gherkin-ui'],
);
''',
            cases:
                '    FlutterEvidenceCase(scenario: demo, body: (t) async {}, '
                'evidenceTypes: buildKinds()),',
          ),
          isNull,
        );
      },
    );

    test('an unreadable harness default stays unknown', () async {
      expect(
        await harnessKinds(
          harness: '''
final evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: buildKinds(),
);
''',
          cases: oneCase,
        ),
        isNull,
      );
    });

    test('an explicitly empty harness default publishes no kinds', () async {
      expect(
        await harnessKinds(
          harness: '''
const evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: [],
);
''',
          cases: oneCase,
        ),
        isEmpty,
      );
    });

    test('an absent harness default does not poison a readable one', () async {
      // The argument is `required`, so this file does not compile. It is still
      // the state the scan sees while a user is part-way through typing the
      // argument, and it declares no default at all: it neither establishes nor
      // contradicts one. Under the previous library-wide reading it made every
      // case in the file undecidable.
      expect(
        await harnessKinds(
          harness: '''
const evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: ['flutter-widget', 'gherkin-ui'],
);
final other = ZukeFlutterEvidenceHarness(runnerCompatibilityId: 'other-runner-v1');
''',
          cases: oneCase,
        ),
        ['flutter-widget', 'gherkin-ui'],
        reason: 'the absent declaration belongs to a harness nobody registers',
      );
    });

    test(
      'an absent harness default alone leaves the case undecidable',
      () async {
        // With nothing readable declared, the case cannot inherit a default, so
        // it stays unknown rather than being credited with the framework's
        // `gherkin-ui`.
        expect(
          await harnessKinds(
            harness: '''
const evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
);
''',
            cases: oneCase,
          ),
          isNull,
        );
      },
    );

    test('a partly readable scenario list remains incomplete', () async {
      contract();
      source('app/test/steps_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';
void main() {
  ZukeFlutterHarness(
    scenarios: [demo, missingScenario()],
    feature: null as dynamic,
    registryFactory: () => [],
    worldFactory: (tester) => null as dynamic,
      runnerId: 'app-tests',
      runnerCompatibilityId: 'app-runner-v1',
    ).registerAll();
  }
  ''');
      final result = await scan();
      expect(result.managedScenarioIds, {'SCN-DEMO-001'});
      expect(result.unresolvedManagedRegistrations, 1);
    });

    test('a scenario spread is not silently omitted', () async {
      contract();
      source('app/test/steps_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';
void main() {
  ZukeFlutterHarness(
    scenarios: [demo, ...moreScenarios()],
    feature: null as dynamic,
    registryFactory: () => [],
    worldFactory: (tester) => null as dynamic,
      runnerId: 'app-tests',
      runnerCompatibilityId: 'app-runner-v1',
    ).registerAll();
  }
  ''');
      final result = await scan();
      expect(result.managedScenarioIds, {'SCN-DEMO-001'});
      expect(result.unresolvedManagedRegistrations, 1);
    });

    test('a literal singular evidenceType reads as a kind', () async {
      contract();
      source('app/test/steps_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';

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

      expect((await scan()).managedScenarios.single.evidenceTypes, [
        'custom-ui',
      ]);
    });
  });
}
