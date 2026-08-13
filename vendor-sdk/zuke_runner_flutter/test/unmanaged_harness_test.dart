import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

void main() {
  final feature = GherkinParser()
      .parseFile('''
# spec-begin
# schemaVersion: 1
# id: FEAT-UNMANAGED-001
# spec-end

Feature: Unmanaged harness
  # rule-spec-begin
  # id: RULE-UNMANAGED-001
  # rule-spec-end
  @RULE-UNMANAGED-001
  Rule: Ordinary execution
    @SCN-UNMANAGED-001
    Scenario: Runs without a Zuke process
''', 'unmanaged.feature')
      .features
      .single;

  ZukeFlutterHarness<MapScenarioWorld>(
    feature: feature,
    scenarios: [const _ScenarioContract()],
    registryFactory: StepRegistry<MapScenarioWorld>.new,
    worldFactory: (_) => MapScenarioWorld(),
    runnerId: 'unmanaged-test-runner',
    runnerCompatibilityId: 'unmanaged-test-runner-v1',
  ).registerAll();
}

final class _ScenarioContract implements ZukeScenarioContract {
  const _ScenarioContract();

  @override
  final ScenarioId id = const ScenarioId('SCN-UNMANAGED-001');

  @override
  final RuleId requirementId = const RuleId('RULE-UNMANAGED-001');

  @override
  final String title = 'Runs without a Zuke process';

  @override
  Set<ControlId> get controlIds => const {};
}
