import 'package:test/test.dart';
import 'package:zuke/zuke.dart';

void main() {
  test('main facade exposes annotations, parser, runner, and runtime APIs', () {
    const annotation = ImplementsRequirement(['RULE-EXAMPLE']);
    expect(annotation.requirementIds, ['RULE-EXAMPLE']);

    final parsed = GherkinParser().parseFile('''
# spec-begin
# schemaVersion: 1
# id: FEAT-EXAMPLE-001
# targets:
#   - backend
# spec-end

@FEAT-EXAMPLE-001
Feature: Example

  # rule-spec-begin
  # id: RULE-EXAMPLE-001
  # rule-spec-end
  @RULE-EXAMPLE-001
  Rule: Example rule

    @SCN-EXAMPLE-001
    Scenario: Example scenario
      Given the example application is ready
''', 'example.feature');

    expect(parsed.features.single.rules.single.scenarios, hasLength(1));

    final flags = ZukeFeatureFlags({'example.flag': true});
    expect(flags.isEnabled('example.flag'), isTrue);

    final events = ZukeEventBus()
      ..emit(const ZukeEvent(id: 'example.event', ruleId: 'RULE-EXAMPLE'));
    expect(events.events.single.id, 'example.event');
  });

  test('main facade can execute a pure-Dart scenario', () async {
    final feature = GherkinParser()
        .parseFile('''
# spec-begin
# schemaVersion: 1
# id: FEAT-EXAMPLE-001
# targets:
#   - backend
# spec-end

@FEAT-EXAMPLE-001
Feature: Example

  # rule-spec-begin
  # id: RULE-EXAMPLE-001
  # rule-spec-end
  @RULE-EXAMPLE-001
  Rule: Example rule

    @SCN-EXAMPLE-001
    Scenario: Example scenario
      Given the example application is ready
''', 'example.feature')
        .features
        .single;
    final rule = feature.rules.single;
    final scenario = rule.scenarios.single;
    final registry = StepRegistry<MapScenarioWorld>()
      ..register(
        StepDefinition(
          pattern: RegExp(r'^the example application is ready$'),
          action: (world, _, __) async => world.values['ready'] = true,
        ),
      );

    final result = await ScenarioExecutor<MapScenarioWorld>(
      registry: registry,
      evidenceType: 'unit',
      target: 'backend',
      runnerId: 'zuke-facade-test',
      runnerCompatibilityId: 'zuke-facade-test-v1',
    ).executeScenario(feature, rule, scenario, MapScenarioWorld.new);

    expect(result.status, ScenarioStatus.passed);
  });
}
