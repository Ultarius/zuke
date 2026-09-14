import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuke/assurance.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'support/temporary_directory.dart';

const _testSourceIdentity = ExecutionSourceIdentity(
  sourcePackage: 'zuke-runner-flutter-test',
  sourceAdapter: 'dart-source',
  sourceCompatibilityId: 'dart-source-package-v1',
);

class _World extends ScenarioWorld {
  final WidgetTester tester;
  _World(this.tester);
}

class _DefaultDriver extends BindingDrivenFlutterScenarioDriver<_World, Key> {
  const _DefaultDriver();

  @override
  WidgetTester testerFor(_World world) => world.tester;

  @override
  Widget buildRoot(_World world) => const Text('vendor root');
}

sealed class _Binding implements ZukeBindingDescriptor {
  const _Binding();

  @override
  String get id => switch (this) {
    _InputBinding() => 'input',
    _ActionBinding() => 'action',
    _DisplayBinding() => 'display',
    _CollectionBinding() => 'collection',
    _MissingBinding() => 'missing',
  };

  @override
  BindingInstanceCardinality get instanceCardinality => switch (this) {
    _CollectionBinding() => BindingInstanceCardinality.many,
    _MissingBinding() => BindingInstanceCardinality.zeroOrOne,
    _ => BindingInstanceCardinality.exactlyOne,
  };

  static _Binding fromId(String bindingId) => switch (bindingId) {
    'input' => const _InputBinding(),
    'action' => const _ActionBinding(),
    'display' => const _DisplayBinding(),
    'collection' => const _CollectionBinding(),
    'missing' => const _MissingBinding(),
    _ => throw ArgumentError.value(
      bindingId,
      'bindingId',
      'Unknown test binding',
    ),
  };
}

final class _InputBinding extends _Binding {
  const _InputBinding();
}

final class _ActionBinding extends _Binding {
  const _ActionBinding();
}

final class _DisplayBinding extends _Binding {
  const _DisplayBinding();
}

final class _CollectionBinding extends _Binding {
  const _CollectionBinding();
}

final class _MissingBinding extends _Binding {
  const _MissingBinding();
}

final class _Scenario implements ZukeScenarioContract {
  @override
  final ScenarioId id;

  @override
  final RuleId requirementId;

  @override
  final String title;

  const _Scenario({
    required this.id,
    required this.requirementId,
    required this.title,
  });

  @override
  Set<ControlId> get controlIds => const {};
}

void main() {
  final evidenceDirectory = Directory.systemTemp.createTempSync(
    'zuke_flutter_evidence_',
  );
  final filteredEvidenceDirectory = Directory.systemTemp.createTempSync(
    'zuke_flutter_evidence_filtered_',
  );
  final harnessResultDirectory = Directory.systemTemp.createTempSync(
    'zuke_flutter_harness_',
  );
  final evidenceHarness = ZukeFlutterEvidenceHarness(
    runnerCompatibilityId: 'runner-compatibility-v1',
    defaultEvidenceTypes: const ['flutter-widget', 'gherkin-ui'],
    outputDirectory: evidenceDirectory.path,
    sourceIdentity: _testSourceIdentity,
    environment: {
      'ZUKE_RESULT_DIR': evidenceDirectory.path,
      'ZUKE_PROFILE': 'merge',
      'ZUKE_TARGET': 'flutter',
      'ZUKE_RUNNER_ID': 'flutter-harness-test',
      'ZUKE_RUNNER_COMPATIBILITY_ID': 'runner-compatibility-v1',
      'ZUKE_SOURCE_PACKAGE': _testSourceIdentity.sourcePackage,
      'ZUKE_SOURCE_ADAPTER': _testSourceIdentity.sourceAdapter,
      'ZUKE_SOURCE_COMPATIBILITY_ID': _testSourceIdentity.sourceCompatibilityId,
    },
  );
  evidenceHarness.registerAll([
    FlutterEvidenceCase(
      scenario: const _Scenario(
        id: ScenarioId('SCN-EVIDENCE-DEFAULT'),
        requirementId: RuleId('RULE-EVIDENCE-001'),
        title: 'Publishes default evidence',
      ),
      body: (_) => 'default observation',
    ),
    FlutterEvidenceCase(
      scenario: const _Scenario(
        id: ScenarioId('SCN-EVIDENCE-OVERRIDE'),
        requirementId: RuleId('RULE-EVIDENCE-001'),
        title: 'Publishes overridden evidence',
      ),
      evidenceTypes: const [
        'accessibility-integration',
        'accessibility-integration',
      ],
      body: (_) => 'override observation',
    ),
  ]);

  ZukeFlutterEvidenceHarness(
    runnerCompatibilityId: 'runner-compatibility-v1',
    defaultEvidenceTypes: const ['flutter-widget'],
    outputDirectory: filteredEvidenceDirectory.path,
    sourceIdentity: _testSourceIdentity,
    environment: {
      'ZUKE_RESULT_DIR': filteredEvidenceDirectory.path,
      'ZUKE_PROFILE': 'merge',
      'ZUKE_TARGET': 'flutter',
      'ZUKE_SCENARIO_FILTER': 'SCN-EVIDENCE-SELECTED',
      'ZUKE_RUNNER_ID': 'filtered-harness-test',
      'ZUKE_RUNNER_COMPATIBILITY_ID': 'runner-compatibility-v1',
      'ZUKE_SOURCE_PACKAGE': _testSourceIdentity.sourcePackage,
      'ZUKE_SOURCE_ADAPTER': _testSourceIdentity.sourceAdapter,
      'ZUKE_SOURCE_COMPATIBILITY_ID': _testSourceIdentity.sourceCompatibilityId,
    },
  ).registerAll([
    FlutterEvidenceCase(
      scenario: const _Scenario(
        id: ScenarioId('SCN-EVIDENCE-SELECTED'),
        requirementId: RuleId('RULE-EVIDENCE-001'),
        title: 'Selected evidence',
      ),
      body: (_) => 'selected observation',
    ),
    FlutterEvidenceCase(
      scenario: const _Scenario(
        id: ScenarioId('SCN-EVIDENCE-EXCLUDED'),
        requirementId: RuleId('RULE-EVIDENCE-001'),
        title: 'Excluded evidence',
      ),
      body: (_) => 'excluded observation',
    ),
  ]);

  test('scenario filtering treats empty as all and trims IDs', () {
    expect(scenarioFilterFromEnvironment(const {}), isEmpty);
    expect(shouldRunScenario('SCN-ONE', const {}), isTrue);
    final selected = scenarioFilterFromEnvironment({
      'ZUKE_SCENARIO_FILTER': ' SCN-ONE,SCN-TWO,, ',
    });
    expect(selected, {'SCN-ONE', 'SCN-TWO'});
    expect(shouldRunScenario('SCN-ONE', selected), isTrue);
    expect(shouldRunScenario('SCN-THREE', selected), isFalse);
  });

  testWidgets('binding-driven driver supplies root and screenshot defaults', (
    tester,
  ) async {
    final world = _World(tester);
    const driver = _DefaultDriver();

    await driver.open(world);
    expect(find.text('vendor root'), findsOneWidget);
    await driver.captureScreenshot(world, 'capture');
    await expectLater(driver.captureScreenshot(world, ''), throwsArgumentError);
  });

  test('evidence harness writes default and deduplicated override results', () {
    final files = evidenceDirectory.listSync().whereType<File>().toList();
    expect(files, hasLength(3));
    final contents = files.map((file) => file.readAsStringSync()).join('\n');
    expect(contents, contains('flutter-harness-test'));
    expect(contents, contains('"profile": "merge"'));
    final evidenceTypes = files
        .map(
          (file) =>
              (jsonDecode(file.readAsStringSync()) as Map)['evidenceType']
                  as String,
        )
        .toList();
    expect(evidenceTypes, containsAll(['flutter-widget', 'gherkin-ui']));
    expect(
      evidenceTypes.where((type) => type == 'accessibility-integration'),
      hasLength(1),
    );
  });

  test('evidence harness filters registration and rejects empty types', () {
    final files = filteredEvidenceDirectory
        .listSync()
        .whereType<File>()
        .toList();
    expect(files, hasLength(1));
    expect(files.single.readAsStringSync(), contains('SCN-EVIDENCE-SELECTED'));

    final emptyHarness = ZukeFlutterEvidenceHarness(
      runnerCompatibilityId: 'runner-compatibility-v1',
      defaultEvidenceTypes: const [],
      outputDirectory: filteredEvidenceDirectory.path,
      environment: const {},
      sourceIdentity: _testSourceIdentity,
    );
    expect(
      () => emptyHarness.registerAll([
        FlutterEvidenceCase(
          scenario: const _Scenario(
            id: ScenarioId('SCN-EVIDENCE-EMPTY'),
            requirementId: RuleId('RULE-EVIDENCE-001'),
            title: 'Empty evidence types',
          ),
          body: (_) => 'never emitted',
        ),
      ]),
      throwsArgumentError,
    );
  });

  testWidgets('vendor Flutter steps use only project-provided binding lookup', (
    tester,
  ) async {
    final input = GlobalKey();
    final action = GlobalKey();
    final display = GlobalKey();
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Semantics(
                label: 'Calculator input',
                textField: true,
                child: TextField(key: input),
              ),
              Semantics(
                label: 'Calculate action',
                button: true,
                child: FilledButton(
                  key: action,
                  onPressed: () => tapped = true,
                  child: const Text('Calculate'),
                ),
              ),
              Container(key: display, child: const Text('Ready')),
            ],
          ),
        ),
      ),
    );
    final world = _World(tester);
    final registry = StepRegistry<_World>();
    for (final step in flutterVendorSteps<_World, _Binding>(
      testerFor: (world) => world.tester,
      bindingFromId: _Binding.fromId,
      keyFor: (_, binding) => switch (binding) {
        _InputBinding() => input,
        _ActionBinding() => action,
        _DisplayBinding() => display,
        _CollectionBinding() => const FlutterBindingKey.collection(
          'collection',
        ),
        _MissingBinding() => const Key('missing'),
      },
    )) {
      registry.register(step);
    }

    for (final text in [
      'the user enters "42" into "input"',
      'the user enters 3 spaces into "input"',
      'element "input" is focused',
      'the user taps "action"',
      'element "display" displays "Ready"',
      'element "missing" is not present',
      'element "action" has accessible name "Calculate action"',
    ]) {
      final step = GherkinStep(
        keyword: 'Then',
        text: text,
        source: const SourceLocation(file: 'vendor.feature', line: 1),
      );
      final match = registry.resolve(step);
      await match.definition.action(world, step, match.arguments);
      expect(match.definition.tier, StepTier.vendor);
      if (text == 'the user enters 3 spaces into "input"') {
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          '   ',
        );
      }
    }
    expect(tapped, isTrue);
    expect(() => _Binding.fromId('unknown'), throwsArgumentError);

    final missingStep = GherkinStep(
      keyword: 'When',
      text: 'the user taps "missing"',
      source: const SourceLocation(file: 'vendor.feature', line: 2),
    );
    final missingMatch = registry.resolve(missingStep);
    await expectLater(
      () => missingMatch.definition.action(
        world,
        missingStep,
        missingMatch.arguments,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('No Flutter binding for missing'),
        ),
      ),
    );
  });

  testWidgets('BindingDrivenFlutterScenarioDriver binding methods', (
    tester,
  ) async {
    const driver = _DefaultDriver();
    final world = _World(tester);

    expect(() => driver.create(), throwsUnsupportedError);

    await driver.open(world);
    expect(find.text('vendor root'), findsOneWidget);
    await driver.captureSemantics(world);
    await driver.dispose(world);

    await driver.captureScreenshot(world, 'test-screenshot');
    expect(() => driver.captureScreenshot(world, ''), throwsArgumentError);

    // Build interactive widget to test enter, tap, and read
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const TextField(key: Key('input_key')),
              ElevatedButton(
                key: const Key('button_key'),
                onPressed: () {},
                child: const Text('Tap Me'),
              ),
              const Text('Label Value', key: Key('label_key')),
            ],
          ),
        ),
      ),
    );

    await driver.zukeEnterBinding(world, const Key('input_key'), 'Hello World');
    expect(find.text('Hello World'), findsOneWidget);

    await driver.zukeTapBinding(world, const Key('button_key'));

    final readText = await driver.zukeReadBinding(
      world,
      const Key('label_key'),
    );
    expect(readText, 'Label Value');

    final missingRead = await driver.zukeReadBinding(
      world,
      const Key('nonexistent'),
    );
    expect(missingRead, isNull);

    // Test vendor step error branches directly via step definition actions
    final steps = flutterVendorSteps<_World, _Binding>(
      testerFor: (w) => w.tester,
      bindingFromId: _Binding.fromId,
      keyFor: (w, b) => switch (b) {
        _InputBinding() => const Key('input_key'),
        _ActionBinding() => const Key('button_key'),
        _DisplayBinding() => const Key('label_key'),
        _CollectionBinding() => const FlutterBindingKey.collection(
          'collection',
        ),
        _MissingBinding() => const Key('nonexistent'),
      },
    );

    // Test element displays error branch
    final displaysStep = steps.firstWhere(
      (s) => s.pattern.pattern.contains('displays'),
    );
    final displayMatch = GherkinStep(
      keyword: 'Then',
      text: 'element "display" displays "Wrong Text"',
      source: const SourceLocation(file: 'test.feature', line: 1),
    );
    await expectLater(
      () => displaysStep.action(world, displayMatch, {
        '1': 'display',
        '2': 'Wrong Text',
      }),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Expected display to display Wrong Text'),
        ),
      ),
    );

    // Test element is focused error branches
    final focusedStep = steps.firstWhere(
      (s) => s.pattern.pattern.contains('focused'),
    );
    final focusMatch = GherkinStep(
      keyword: 'Then',
      text: 'element "display" is focused',
      source: const SourceLocation(file: 'test.feature', line: 2),
    );
    await expectLater(
      () => focusedStep.action(world, focusMatch, {'1': 'display'}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('does not expose an editable focus target'),
        ),
      ),
    );

    // Test element has accessible name error branches
    final accessibleStep = steps.firstWhere(
      (s) => s.pattern.pattern.contains('accessible name'),
    );
    await expectLater(
      () => accessibleStep.action(world, focusMatch, {
        '1': 'missing',
        '2': 'Name',
      }),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('No Flutter binding for missing'),
        ),
      ),
    );
    await expectLater(
      () => accessibleStep.action(world, focusMatch, {
        '1': 'action',
        '2': 'Nonexistent Name',
      }),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Expected accessible name Nonexistent Name'),
        ),
      ),
    );
  });

  testWidgets('collection bindings match every typed instance for display', (
    tester,
  ) async {
    const family = FlutterBindingKey.collection('todo.taskItemText');
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            Text(
              'Task A',
              key: FlutterBindingInstanceKey('todo.taskItemText', 'a'),
            ),
            Text(
              'Task B',
              key: FlutterBindingInstanceKey('todo.taskItemText', 'b'),
            ),
          ],
        ),
      ),
    );
    expect(findFlutterBinding(family), findsNWidgets(2));
    final world = _World(tester);
    final steps = flutterVendorSteps<_World, _Binding>(
      testerFor: (world) => world.tester,
      bindingFromId: _Binding.fromId,
      keyFor: (_, binding) => switch (binding) {
        _CollectionBinding() => family,
        _ => const Key('unused'),
      },
    );
    final display = steps.firstWhere(
      (step) => step.pattern.pattern.contains('displays'),
    );
    final matching = GherkinStep(
      keyword: 'Then',
      text: 'element "collection" displays "Task B"',
      source: const SourceLocation(file: 'collection.feature', line: 1),
    );
    await display.action(world, matching, {'1': 'collection', '2': 'Task B'});

    final failure = GherkinStep(
      keyword: 'Then',
      text: 'element "collection" displays "Task C"',
      source: const SourceLocation(file: 'collection.feature', line: 2),
    );
    await expectLater(
      () => display.action(world, failure, {'1': 'collection', '2': 'Task C'}),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('Task A'), contains('Task B')),
        ),
      ),
    );
  });

  final harnessRows = <String>{};
  const featureText = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-H-001
# targets:
#   - flutter
# spec-end

@FEAT-H-001
Feature: Harness Feature
  # rule-spec-begin
  # id: RULE-H-001
  # rule-spec-end
  @RULE-H-001
  Rule: Harness Rule
    @SCN-H-001
    Scenario Outline: Harness Scenario
      Given a step "<value>"

      Examples: first values
        | value |
        | one   |
        | two   |

      Examples: second values
        | value |
        | three |
''';

  final harnessFeature = GherkinParser()
      .parseFile(featureText, 'harness.feature')
      .features
      .first;

  ZukeFlutterHarness<_World>(
    feature: harnessFeature,
    scenarios: [
      _TestScenarioContract(
        id: ScenarioId('SCN-H-001'),
        title: 'Harness Scenario',
        requirementId: RuleId('RULE-H-001'),
        controlIds: {ControlId('CTRL-H-001')},
      ),
    ],
    registryFactory: () => StepRegistry<_World>()
      ..register(
        StepDefinition.cucumber(
          expression: CucumberExpression(
            'a step {string}',
            StepParameterTypeRegistry.standard(),
          ),
          tier: StepTier.project,
          target: 'flutter',
          action: (world, step, values) async {
            harnessRows.add(values.single as String);
          },
        ),
      ),
    worldFactory: (tester) async => _World(tester),
    runnerId: 'test-runner',
    runnerCompatibilityId: 'test-runner-v1',
    resultDirectory: harnessResultDirectory.path,
    sourceIdentity: _testSourceIdentity,
  ).registerAll();

  tearDownAll(() async {
    try {
      expect(harnessRows, {'one', 'two', 'three'});
      final files = harnessResultDirectory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('scenario-'))
          .toList();
      expect(files, hasLength(3));
      final executionIds = files
          .map(
            (file) =>
                (jsonDecode(file.readAsStringSync()) as Map)['executionId'],
          )
          .toSet();
      expect(executionIds, hasLength(3));
      final caseIds = files
          .map((file) => (jsonDecode(file.readAsStringSync()) as Map)['caseId'])
          .toSet();
      expect(caseIds, {
        'examples-1-row-1',
        'examples-1-row-2',
        'examples-2-row-1',
      });
    } finally {
      await Future.wait([
        deleteTemporaryDirectory(evidenceDirectory),
        deleteTemporaryDirectory(filteredEvidenceDirectory),
        deleteTemporaryDirectory(harnessResultDirectory),
      ]);
    }
  });
}

final class _TestScenarioContract implements ZukeScenarioContract {
  @override
  final ScenarioId id;
  @override
  final String title;
  @override
  final RuleId requirementId;
  @override
  final Set<ControlId> controlIds;

  const _TestScenarioContract({
    required this.id,
    required this.title,
    required this.requirementId,
    required this.controlIds,
  });
}
