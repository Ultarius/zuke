import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke/runner.dart';

class World extends MapScenarioWorld {}

enum _Contract implements ZukeScenarioContract {
  correct(ScenarioId('SCN-CONTRACT-ONE'), 'RULE-CONTRACT-001', 'Correct title'),
  missing(ScenarioId('SCN-CONTRACT-TWO'), 'RULE-CONTRACT-001', 'Correct title'),
  drifted(ScenarioId('SCN-CONTRACT-ONE'), 'RULE-OTHER', 'Drifted title');

  const _Contract(this.id, this.requirementId, this.title);
  @override
  final ScenarioId id;
  @override
  final String requirementId;
  @override
  final String title;
  @override
  Set<String> get controlIds => const {};
}

void main() {
  group('resolveScenarioContract', () {
    final feature = GherkinParser()
        .parseFile('''
# spec-begin
# schemaVersion: 1
# id: FEAT-CONTRACT-001
# spec-end
Feature: Contracts
  # rule-spec-begin
  # id: RULE-CONTRACT-001
  # rule-spec-end
  Rule: Contract rule
    @SCN-CONTRACT-ONE
    Scenario: Correct title
      Given a precondition
''', 'contracts.feature')
        .features
        .single;

    test('resolves a generated ID and verifies its rule and title', () {
      const contract = _Contract.correct;

      final resolved = resolveScenarioContract(feature, contract);

      expect(resolved.rule.metadata.id, contract.requirementId);
      expect(resolved.scenario.scenarioElement.title, contract.title);
    });

    test('rejects missing or drifted generated contracts', () {
      expect(
        () => resolveScenarioContract(feature, _Contract.missing),
        throwsA(isA<StateError>()),
      );
      expect(
        () => resolveScenarioContract(feature, _Contract.drifted),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'matches contracts in declaration order for regexp and glob patterns',
      () {
        final contracts = [_Contract.correct, _Contract.missing];
        expect(
          matchScenarioContracts(
            contracts,
            ZukeScenarioPattern.regExp(RegExp(r'^SCN-CONTRACT-')),
          ),
          contracts,
        );
        expect(
          matchScenarioContracts(
            contracts,
            ZukeScenarioPattern.exact(ScenarioId('SCN-CONTRACT-ONE')),
          ),
          [_Contract.correct],
        );
        expect(
          matchScenarioContracts(
            contracts,
            ZukeScenarioPattern.ruleId('RULE-CONTRACT-001'),
          ),
          contracts,
        );
        expect(() => ZukeScenarioPattern.glob(''), throwsArgumentError);
        expect(() => ZukeScenarioPattern.from(42), throwsArgumentError);
        expect(
          matchScenarioContracts(
            contracts,
            ZukeScenarioPattern.glob('SCN-*-ONE'),
          ),
          [_Contract.correct],
        );
        expect(
          () => matchScenarioContracts(
            contracts,
            ZukeScenarioPattern.glob('SCN-NONE-*'),
          ),
          throwsStateError,
        );
      },
    );
  });

  test('resolves the earliest matching step tier before priority', () {
    final registry = StepRegistry<World>()
      ..register(
        StepDefinition<World>(
          pattern: RegExp(r'^an action$'),
          priority: 999,
          tier: StepTier.vendor,
          action: (_, _, _) {},
        ),
      )
      ..register(
        StepDefinition<World>(
          pattern: RegExp(r'^an action$'),
          priority: 1,
          tier: StepTier.project,
          action: (_, _, _) {},
        ),
      );
    const step = GherkinStep(
      keyword: 'Given',
      text: 'an action',
      source: SourceLocation(file: 'test.feature', line: 1),
    );

    expect(registry.resolve(step).definition.tier, StepTier.project);
  });

  test('retains ambiguity failures within the selected tier', () {
    final registry = StepRegistry<World>()
      ..register(
        StepDefinition<World>(
          pattern: RegExp(r'^ambiguous$'),
          tier: StepTier.vendor,
          action: (_, _, _) {},
        ),
      )
      ..register(
        StepDefinition<World>(
          pattern: RegExp(r'^ambiguous$'),
          tier: StepTier.vendor,
          action: (_, _, _) {},
        ),
      );
    const step = GherkinStep(
      keyword: 'Given',
      text: 'ambiguous',
      source: SourceLocation(file: 'test.feature', line: 1),
    );

    expect(
      () => registry.resolve(step),
      throwsA(isA<AmbiguousStepException>()),
    );
  });

  test('resolves before execution and produces a stable raw result', () async {
    const source = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-RUN-001
# spec-end
Feature: Run
  # rule-spec-begin
  # id: RULE-RUN-001
  # rule-spec-end
  Rule: A rule
    Scenario Outline: add
      Given value <a>
      Then the sum is <b>
    Examples:
      | a | b |
      | one | two |
''';
    final feature = GherkinParser()
        .parseFile(source, 'run.feature')
        .features
        .single;
    final registry = StepRegistry<World>();
    final seen = <String>[];
    registry.register(
      StepDefinition<World>(
        pattern: RegExp(r'^value (.+)$'),
        priority: 300,
        action: (world, step, args) => seen.add(args['1']!),
      ),
    );
    registry.register(
      StepDefinition<World>(
        pattern: RegExp(r'^the sum is (.+)$'),
        priority: 300,
        action: (world, step, args) => seen.add(args['1']!),
      ),
    );
    final executor = ScenarioExecutor<World>(
      registry: registry,
      evidenceType: 'gherkin-api',
      target: 'backend',
    );
    final first = (await executor.executeRule(
      feature,
      feature.rules.single,
      World.new,
    )).single;
    final second = (await executor.executeRule(
      feature,
      feature.rules.single,
      World.new,
    )).single;
    expect(first.status, ScenarioStatus.passed);
    expect(first.executionId, second.executionId);
    expect(first.evidenceType, 'gherkin-api');
    expect(first.requirementId, 'RULE-RUN-001');
    expect(seen, ['one', 'two', 'one', 'two']);

    final releaseExecutor = ScenarioExecutor<World>(
      registry: registry,
      evidenceType: 'gherkin-api',
      target: 'backend',
      profile: 'release',
    );
    final release = (await releaseExecutor.executeRule(
      feature,
      feature.rules.single,
      World.new,
    )).single;
    expect(release.executionId, first.executionId);
    expect(release.profile, 'release');
  });

  test('enumerates every Examples row in source order', () {
    final feature = GherkinParser()
        .parseFile('''
# spec-begin
# schemaVersion: 1
# id: FEAT-OUTLINE-001
# spec-end
Feature: Outline cases
  # rule-spec-begin
  # id: RULE-OUTLINE-001
  # rule-spec-end
  Rule: Cases
    Scenario Outline: all rows
      Given value <value>
    Examples: first values
      | value |
      | one   |
      | two   |
    Examples: second values
      | value |
      | three |
''', 'outline.feature')
        .features
        .single;
    final cases = scenarioExampleCases(
      feature.rules.single.scenarios.single,
    ).toList();

    expect(cases.map((exampleCase) => exampleCase.values['value']), [
      'one',
      'two',
      'three',
    ]);
    expect(cases.map((exampleCase) => exampleCase.displayLabel), [
      'first values row 1',
      'first values row 2',
      'second values row 1',
    ]);
  });

  test('executes every Examples row when a non-first row fails', () async {
    final feature = GherkinParser()
        .parseFile('''
# spec-begin
# schemaVersion: 1
# id: FEAT-OUTLINE-002
# spec-end
Feature: Outline execution
  Background:
    Given setup
  # rule-spec-begin
  # id: RULE-OUTLINE-002
  # rule-spec-end
  Rule: Cases
    Scenario Outline: all rows
      Given value <value>
    Examples:
      | value |
      | good  |
      | bad   |
      | final |
''', 'outline-execution.feature')
        .features
        .single;
    final seen = <String>[];
    final registry = StepRegistry<World>()
      ..register(
        StepDefinition<World>(
          pattern: RegExp(r'^setup$'),
          action: (_, _, _) => seen.add('setup'),
        ),
      )
      ..register(
        StepDefinition<World>(
          pattern: RegExp(r'^value (.+)$'),
          action: (_, _, arguments) {
            if (arguments['1'] == 'bad') {
              throw StateError('intentional row failure');
            }
          },
        ),
      );

    final results = await ScenarioExecutor<World>(
      registry: registry,
      evidenceType: 'gherkin-ui',
    ).executeRule(feature, feature.rules.single, World.new);

    expect(results.map((result) => result.status), [
      ScenarioStatus.passed,
      ScenarioStatus.failed,
      ScenarioStatus.passed,
    ]);
    expect(seen, ['setup', 'setup', 'setup']);
    expect(results.map((result) => result.executionId).toSet(), hasLength(3));
  });

  test('gives duplicate Examples rows distinct execution IDs', () async {
    final feature = GherkinParser()
        .parseFile('''
# spec-begin
# schemaVersion: 1
# id: FEAT-OUTLINE-003
# spec-end
Feature: Duplicate outline rows
  # rule-spec-begin
  # id: RULE-OUTLINE-003
  # rule-spec-end
  Rule: Cases
    Scenario Outline: repeated values
      Given value <value>
    Examples:
      | value |
      | same  |
      | same  |
''', 'duplicate-outline.feature')
        .features
        .single;
    final registry = StepRegistry<World>()
      ..register(
        StepDefinition<World>(
          pattern: RegExp(r'^value (.+)$'),
          action: (_, _, _) {},
        ),
      );

    final results = await ScenarioExecutor<World>(
      registry: registry,
      evidenceType: 'gherkin-ui',
    ).executeRule(feature, feature.rules.single, World.new);

    expect(results, hasLength(2));
    expect(results.map((result) => result.executionId).toSet(), hasLength(2));
  });

  test('fails before running when a step is unresolved', () async {
    const source = '''
# spec-begin
# id: F
# spec-end
Feature: Run
  # rule-spec-begin
  # id: R
  # rule-spec-end
  Rule: A rule
    Scenario: missing
      Given missing
''';
    final feature = GherkinParser()
        .parseFile(source, 'run.feature')
        .features
        .single;
    final result = await ScenarioExecutor<World>(
      registry: StepRegistry<World>(),
      evidenceType: 'gherkin-ui',
    ).executeRule(feature, feature.rules.single, World.new);
    expect(result.single.status, ScenarioStatus.unresolved);
  });

  test('scenario result round-trips through the strict artifact schema', () {
    const result = ScenarioResult(
      executionId: 'execution-1',
      status: ScenarioStatus.passed,
      requirementId: 'RULE-RUN-001',
      evidenceType: 'gherkin-api',
      target: 'backend',
      candidateId: 'SCN-RUN-001',
      profile: 'pullRequest',
      runnerId: 'runner',
      runnerCompatibilityId: 'runner-v1',
      scenarioIds: [ScenarioId('SCN-RUN-001')],
    );
    final decoded = ScenarioResult.fromJson(result.toJson());
    expect(decoded.executionId, result.executionId);
    expect(decoded.status, ScenarioStatus.passed);
    expect(decoded.candidateId, 'SCN-RUN-001');
  });

  test('scenario execution reports ambiguity and action failures', () async {
    const source = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-FAIL-001
# spec-end
Feature: Failures
  # rule-spec-begin
  # id: RULE-FAIL-001
  # rule-spec-end
  Rule: Failure rule
    Scenario: failure scenario
      Given a failing action
''';
    final feature = GherkinParser()
        .parseFile(source, 'failure.feature')
        .features
        .single;
    final scenario = feature.rules.single.scenarios.single;
    final ambiguous = StepRegistry<World>()
      ..register(
        StepDefinition<World>(
          pattern: RegExp('failing action'),
          action: (_, _, _) {},
        ),
      )
      ..register(
        StepDefinition<World>(
          pattern: RegExp('failing action'),
          action: (_, _, _) {},
        ),
      );
    final failed = StepRegistry<World>()
      ..register(
        StepDefinition<World>(
          pattern: RegExp(r'^a (.+) action$'),
          action: (_, _, arguments) =>
              throw StateError(arguments['1'] ?? 'missing'),
        ),
      );

    final ambiguousResult = await ScenarioExecutor<World>(
      registry: ambiguous,
      evidenceType: 'domain-unit',
    ).executeScenario(feature, feature.rules.single, scenario, World.new);
    final failedResult = await ScenarioExecutor<World>(
      registry: failed,
      evidenceType: 'domain-unit',
    ).executeScenario(feature, feature.rules.single, scenario, World.new);

    expect(ambiguousResult.status, ScenarioStatus.ambiguous);
    expect(failedResult.status, ScenarioStatus.failed);
    expect(failedResult.steps.single.status, StepStatus.failed);
    expect(failedResult.steps.single.error, contains('failing'));
  });

  test('strict result schemas reject invalid status and collection shapes', () {
    final scenario = const ScenarioResult(
      executionId: 'execution',
      status: ScenarioStatus.passed,
      requirementId: 'RULE-1',
      evidenceType: 'domain-unit',
      target: 'backend',
      candidateId: 'SCN-1',
      profile: 'pullRequest',
      runnerId: 'runner',
      runnerCompatibilityId: 'runner-v1',
    ).toJson();
    final suite = const SuiteResult(
      executionId: 'suite',
      status: SuiteStatus.skipped,
      requirementId: 'RULE-1',
      evidenceType: 'domain-unit',
      target: 'backend',
      candidateId: 'suite-1',
      profile: 'pullRequest',
      runnerId: 'runner',
      runnerCompatibilityId: 'runner-v1',
      resultDigest: 'sha256:result',
    ).toJson();

    expect(SuiteResult.fromJson(suite).status, SuiteStatus.skipped);
    expect(
      () => ScenarioResult.fromJson({...scenario, 'steps': 'invalid'}),
      throwsFormatException,
    );
    expect(
      () => ScenarioResult.fromJson({...scenario, 'status': 'unknown'}),
      throwsFormatException,
    );
    expect(
      () => SuiteResult.fromJson({
        ...suite,
        'scenarioIds': [1],
      }),
      throwsFormatException,
    );
    expect(
      () => SuiteResult.fromJson({...suite, 'status': 'unknown'}),
      throwsFormatException,
    );
  });

  test('evidence and execution writers replace files atomically', () {
    final root = Directory.systemTemp.createTempSync('zuke-runner-writers-');
    addTearDown(() => root.deleteSync(recursive: true));
    final digests = {
      for (final key in const [
        'source',
        'contract',
        'mapping',
        'specificationIndex',
        'result',
      ])
        key: 'sha256:${List.filled(64, 'a').join()}',
    };
    final evidence = EvidenceRecord(
      requirementId: 'RULE-1',
      evidenceType: 'domain-unit',
      target: 'backend',
      executionId: 'execution',
      digests: digests,
      candidateId: 'candidate',
      runnerId: 'runner',
      runnerCompatibilityId: 'runner-v1',
    );
    const scenario = ScenarioResult(
      executionId: 'execution',
      status: ScenarioStatus.passed,
      requirementId: 'RULE-1',
      evidenceType: 'domain-unit',
      target: 'backend',
      candidateId: 'candidate',
      profile: 'pullRequest',
      runnerId: 'runner',
      runnerCompatibilityId: 'runner-v1',
    );
    const suite = SuiteResult(
      executionId: 'suite',
      status: SuiteStatus.passed,
      requirementId: 'RULE-1',
      evidenceType: 'domain-unit',
      target: 'backend',
      candidateId: 'candidate',
      profile: 'pullRequest',
      runnerId: 'runner',
      runnerCompatibilityId: 'runner-v1',
      resultDigest: 'sha256:result',
    );

    const EvidenceWriter().writeAtomic(root.path, evidence);
    const EvidenceWriter().writeAtomic(root.path, evidence);
    const EvidenceWriter().write('${root.path}/envelopes/results.json', [
      evidence,
    ], buildId: 'build-1');
    final scenarioFile = const ExecutionResultWriter().writeScenario(
      '${root.path}/results',
      scenario,
    );
    final suiteFile = const ExecutionResultWriter().writeSuite(
      '${root.path}/results',
      suite,
    );

    expect(jsonDecode(scenarioFile.readAsStringSync()), scenario.toJson());
    expect(jsonDecode(suiteFile.readAsStringSync()), suite.toJson());
    expect(
      jsonDecode(
        File('${root.path}/envelopes/results.json').readAsStringSync(),
      ),
      hasLength(1),
    );
  });

  test('suite evidence emitter writes one deterministic result per type', () {
    final root = Directory.systemTemp.createTempSync('zuke-runner-emitter-');
    addTearDown(() => root.deleteSync(recursive: true));

    final files = const SuiteEvidenceEmitter().emitPassing(
      requirementId: 'RULE-EMITTER-001',
      scenarioId: const ScenarioId('SCN-EMITTER-ONE'),
      evidenceTypes: const ['flutter-widget', 'gherkin-ui', 'gherkin-ui'],
      target: 'flutter',
      runnerCompatibilityId: 'runner-v1',
      digestInput: 'observed result',
      outputDirectory: root.path,
      profile: 'test',
      runnerId: 'runner',
    );

    expect(files, hasLength(2));
    final results = files
        .map(
          (file) => SuiteResult.fromJson(jsonDecode(file.readAsStringSync())),
        )
        .toList();
    expect(results.map((result) => result.evidenceType).toSet(), {
      'flutter-widget',
      'gherkin-ui',
    });
    expect(results.map((result) => result.resultDigest).toSet(), {
      'sha256:${sha256.convert(utf8.encode('observed result'))}',
    });
  });
}
