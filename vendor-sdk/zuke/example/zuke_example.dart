import 'package:zuke/zuke.dart';

@ImplementsRequirement(['RULE-EXAMPLE'])
final class ExampleApplication {
  bool ready = false;
}

Future<void> main() async {
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
    Scenario: Start the application
      Given the example application is ready
''', 'example.feature')
      .features
      .single;
  final application = ExampleApplication();
  final registry = StepRegistry<MapScenarioWorld>()
    ..register(
      StepDefinition(
        pattern: RegExp(r'^the example application is ready$'),
        action: (_, __, ___) async => application.ready = true,
      ),
    );

  final result =
      await ScenarioExecutor<MapScenarioWorld>(
        registry: registry,
        evidenceType: 'unit',
        target: 'backend',
        runnerId: 'zuke-example',
        runnerCompatibilityId: 'zuke-example-v1',
      ).executeScenario(
        feature,
        feature.rules.single,
        feature.rules.single.scenarios.single,
        MapScenarioWorld.new,
      );

  if (result.status != ScenarioStatus.passed || !application.ready) {
    throw StateError('The example scenario did not pass.');
  }
}
