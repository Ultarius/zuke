import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/workspace_annotation_scan.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'support/resolved_workspace.dart';
import 'support/temporary_directory.dart';

/// Fixtures that go through the real resolver.
///
/// Constructing [ManagedScenarioClaim] by hand bypasses exactly the defects
/// that matter here: how a registration's evidence kinds are read, how its
/// provenance is attributed, and whether two registrations of one scenario stay
/// separate. Every test here resolves actual source.
void main() {
  late Directory root;

  File source(String path, String content) {
    final file = File.fromUri(root.uri.resolve(path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('zuke-binding-scan-');
    await configureFixturePackages(root);
    source(
      'pubspec.yaml',
      "name: fixture\nenvironment:\n  sdk: '>=3.10.0 <4.0.0'\n",
    );
  });
  tearDown(() => deleteTemporaryDirectory(root));

  /// A contract declaring one scenario, so registrations can name it.
  void contract({String scenario = 'SCN-DEMO-001'}) =>
      source('lib/demo_contract.dart', '''
import 'package:zuke_annotations/zuke_annotations.dart';

class FakeScenario implements ZukeScenarioContract {
  const FakeScenario(this.id, this.requirementId, this.title, this.controlIds);

  @override
  final ScenarioId id;
  @override
  final RuleId requirementId;
  @override
  final String title;
  @override
  final Set<ControlId> controlIds;
}

const demo = FakeScenario(
  ScenarioId('$scenario'),
  RuleId('RULE-DEMO-001'),
  'A demo scenario',
  <ControlId>{},
);
''');

  /// A workspace with two targets, so provenance can be told apart.
  WorkspaceDiscoveryResult workspace() => WorkspaceDiscoveryResult(
    config: const ZukeConfig(
      workspaceTargets: {
        'app': WorkspaceTarget(
          id: 'app',
          language: 'dart',
          framework: 'flutter',
          packages: [
            WorkspacePackage(
              id: 'app-pkg',
              path: 'app',
              roots: ['lib', 'test'],
            ),
          ],
        ),
        // Declares no path, so `workspacePackageTargets` cannot map it and its
        // files reach the scan unattributed. This is the shape that produces a
        // null target from real source.
        'loose': WorkspaceTarget(
          id: 'loose',
          language: 'dart',
          framework: 'dart',
          packages: [
            WorkspacePackage(id: 'loose-pkg', path: '', roots: ['test']),
          ],
        ),
        'backend': WorkspaceTarget(
          id: 'backend',
          language: 'dart',
          framework: 'dart',
          packages: [
            WorkspacePackage(
              id: 'api-pkg',
              path: 'api',
              roots: ['lib', 'test'],
            ),
          ],
        ),
      },
    ),
    data: const MetadataExtractorResult(),
  );

  Future<WorkspaceAnnotationScan> scan() =>
      scanWorkspaceAnnotations(root.path, workspace());

  /// Registers [declaration] from a file in the app package and returns the
  /// kinds the scan read off it. Null means the scan could not know them.
  Future<List<String>?> kindsOf(String declaration) async {
    contract();
    source('app/test/app_test.dart', '''
import 'package:zuke_runner/zuke_runner.dart';
import 'package:fixture/demo_contract.dart';

const more = ['domain-unit'];

void main() {
  zukeTest(() {}, scenario: demo, evidenceTypes: $declaration);
}
''');
    final claims = (await scan()).managedScenarios;
    return claims.single.evidenceTypes;
  }

  /// Registers one harness case and returns the kinds inherited for it.
  Future<List<String>?> harnessKinds({
    required String harness,
    required String cases,
  }) async {
    contract();
    source('app/test/app_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';

$harness

void main() {
  evidenceHarness.registerAll([
$cases
  ]);
}
''');
    return (await scan()).managedScenarios.single.evidenceTypes;
  }

  /// Registers one case under each of two harnesses and returns their kinds in
  /// registration order, so per-harness attribution is observable.
  Future<List<List<String>?>> twoHarnessKinds({
    required String readable,
    required String unreadable,
  }) async {
    contract();
    source('app/test/app_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';

final otherScenario = FakeScenario(
  ScenarioId('SCN-DEMO-002'),
  RuleId('RULE-DEMO-001'),
  'Another demo scenario',
  <ControlId>{},
);

$readable
$unreadable

void main() {
  readableHarness.registerAll([
    FlutterEvidenceCase(scenario: demo, body: (tester) async {}),
  ]);
  dynamicHarness.registerAll([
    FlutterEvidenceCase(scenario: otherScenario, body: (tester) async {}),
  ]);
}
''');
    final result = await scan();
    final Map<String, ManagedScenarioClaim> byScenario = {
      for (final claim in result.managedScenarios) claim.scenarioId: claim,
    };
    return [
      byScenario['SCN-DEMO-001']?.evidenceTypes,
      byScenario['SCN-DEMO-002']?.evidenceTypes,
    ];
  }

  group('registration provenance', () {
    test('two targets registering one scenario stay two claims', () async {
      // The defect this pins: merging by scenario ID kept the first file and
      // target, so a backend widget registration merged into an app claim and
      // published a kind the app target never declared.
      contract();
      source('app/test/app_test.dart', '''
import 'package:zuke_runner/zuke_runner.dart';
import 'package:fixture/demo_contract.dart';

void main() {
  zukeTest(() {}, scenario: demo, evidenceTypes: const ['unit']);
}
''');
      source('api/test/api_test.dart', '''
import 'package:zuke_runner/zuke_runner.dart';
import 'package:fixture/demo_contract.dart';

void main() {
  zukeTest(() {}, scenario: demo, evidenceTypes: const ['flutter-widget']);
}
''');

      final claims = (await scan()).managedScenarios
          .where((claim) => claim.scenarioId == 'SCN-DEMO-001')
          .toList();

      expect(claims, hasLength(2), reason: 'one claim per registration site');
      expect(
        claims.map((claim) => claim.target).toSet(),
        {'app', 'backend'},
        reason: 'each claim keeps the target its own file resolved to',
      );
      expect(
        claims.map((claim) => claim.evidenceTypes!.single).toSet(),
        {'unit', 'flutter-widget'},
        reason: "neither claim absorbs the other's kinds",
      );
    });

    test('a claim carries the package its own file belongs to', () async {
      contract();
      source('api/test/api_test.dart', '''
import 'package:zuke_runner/zuke_runner.dart';
import 'package:fixture/demo_contract.dart';

void main() {
  zukeTest(() {}, scenario: demo, evidenceTypes: const ['api-contract']);
}
''');

      final claim = (await scan()).managedScenarios.single;
      expect(claim.target, 'backend');
      expect(claim.packageId, 'api-pkg');
    });

    test('a file outside every configured package has no target', () async {
      contract();
      source('test/loose_test.dart', '''
import 'package:zuke_runner/zuke_runner.dart';
import 'package:fixture/demo_contract.dart';

void main() {
  zukeTest(() {}, scenario: demo, evidenceTypes: const ['unit']);
}
''');

      final claim = (await scan()).managedScenarios.single;
      // Null, not a guess: an unattributable registration cannot satisfy a slot
      // that names a target, and must not be reported as absent either.
      expect(claim.target, isNull);
      expect(claim.packageId, isNull);
    });
  });

  group('reading declared evidence kinds', () {
    test('a literal list reads completely', () async {
      expect(await kindsOf("const ['a', 'b']"), ['a', 'b']);
    });

    test('a constant reference reads through the constant', () async {
      expect(await kindsOf('more'), ['domain-unit']);
    });

    test('a spread is unknown, not the elements around it', () async {
      // Returning ['unit'] here would report a complete reading of a list that
      // may also publish other kinds, which could invent a gap or hide one.
      expect(await kindsOf("const ['unit', ...more]"), isNull);
    });

    test('a collection-if is unknown, not the elements around it', () async {
      expect(await kindsOf("const ['unit', if (false) 'x']"), isNull);
    });

    test('a nonconstant expression is unknown', () async {
      expect(await kindsOf('buildKinds()'), isNull);
    });
  });

  group('scenario harnesses', () {
    const oneCase =
        '    FlutterEvidenceCase(scenario: demo, body: (tester) async {}),';

    test('a harness alias retains its registering owner', () async {
      expect(
        await harnessKinds(
          harness: '''
const original = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: ['flutter-widget'],
);
final evidenceHarness = original;
''',
          cases: oneCase,
        ),
        ['flutter-widget'],
      );
    });

    for (final cascade in [false, true]) {
      test('named case lists resolve with cascade=$cascade', () async {
        contract();
        source('app/test/app_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';
void main() {
  final original = FlutterEvidenceCase(scenario: demo, body: (_) async => 'ok');
  final caseAlias = original;
  final cases = [caseAlias];
  ${cascade ? 'ZukeFlutterEvidenceHarness' : 'final harness = ZukeFlutterEvidenceHarness'}(
    runnerCompatibilityId: 'app-runner-v1',
    defaultEvidenceTypes: const ['flutter-widget'],
  )${cascade ? '..registerAll(cases)' : '; harness.registerAll(cases)'};
}
''');
        final result = await scan();
        expect(result.managedScenarios.single.evidenceTypes, [
          'flutter-widget',
        ]);
        expect(result.unresolvedManagedRegistrations, 0);
      });
    }

    test('unused constructions do not register cases', () async {
      contract();
      source('app/test/app_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';
void main() {
  const harness = ZukeFlutterEvidenceHarness(
    runnerCompatibilityId: 'app-runner-v1',
    defaultEvidenceTypes: ['flutter-widget'],
  );
  final unused = FlutterEvidenceCase(scenario: demo, body: (_) async => 'ok');
}
''');
      final result = await scan();
      expect(result.managedScenarios, isEmpty);
      expect(result.unresolvedManagedRegistrations, 0);
    });

    test(
      'a reassigned harness is unresolved rather than its initializer',
      () async {
        contract();
        source('app/test/app_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';
void main() {
  var harness = const ZukeFlutterEvidenceHarness(
    runnerCompatibilityId: 'app-runner-v1',
    defaultEvidenceTypes: ['flutter-widget'],
  );
  harness = buildHarness();
  harness.registerAll([FlutterEvidenceCase(scenario: demo, body: (_) async => 'ok')]);
}
''');
        final result = await scan();
        expect(result.managedScenarios, isEmpty);
        expect(result.unresolvedManagedRegistrations, 1);
      },
    );

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
