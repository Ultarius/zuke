import 'dart:io';

import 'package:calculator_api/calculator_api.dart';
import 'package:calculator_contracts/calculator_contracts.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_runner/zuke_runner.dart';
import 'package:zuke_runner/http.dart';
import 'package:test/test.dart';

void main() {
  test(
    'calculator API Gherkin scenario executes through the HTTP driver',
    () async {
      final server = CalculatorServer();
      await server.start();
      addTearDown(server.stop);
      final featureFile = File(
        '../../specs/features/calculator_operations.feature',
      );
      final feature = GherkinParser()
          .parseFile(featureFile.readAsStringSync(), featureFile.path)
          .features
          .single;
      final rule = feature.rules.firstWhere(
        (r) => r.metadata.id == AdditionScenarios.addIntegersApi.requirementId,
      );
      final scenario = rule.scenarios.firstWhere(
        (s) =>
            s.scenarioElement.title ==
            'Add two positive integers through the API',
      );
      final driver = JsonHttpDriver(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        endpoints: const {'calculator.evaluate': '/v1/calculations/evaluate'},
      );
      final registry = StepRegistry<MapScenarioWorld>()
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the calculator application is ready'),
            action: (_, __, ___) async => expect(server.port, greaterThan(0)),
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the remote calculator feature is enabled'),
            action: (_, __, ___) async =>
                expect(server.application.registration.routes, isNotEmpty),
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the first operand is "([^"]+)"'),
            action: (world, _, args) async =>
                world.values['firstOperand'] = args['1'],
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the selected operator is "([^"]+)"'),
            action: (world, _, args) async =>
                world.values['operator'] = args['1'],
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the second operand is "([^"]+)"'),
            action: (world, _, args) async =>
                world.values['secondOperand'] = args['1'],
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the user requests the calculation'),
            action: (world, _, __) async {
              world.values['response'] = await driver.request(
                world,
                HttpRequestSpec(
                  endpointId: 'calculator.evaluate',
                  method: 'POST',
                  body: {
                    'firstOperand': world.values['firstOperand'],
                    'secondOperand': world.values['secondOperand'],
                    'operator': world.values['operator'],
                  },
                ),
              );
            },
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'API response status must be (\d+)'),
            action: (world, _, args) async => HttpAssertions.expectStatus(
              world.values['response'] as HttpResponseSpec,
              int.parse(args['1']!),
            ),
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'API result must be "([^"]+)"'),
            action: (world, _, args) async => HttpAssertions.expectJson(
              world.values['response'] as HttpResponseSpec,
              '/result',
              args['1'],
            ),
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'event "([^"]+)" must be emitted once'),
            action: (_, __, args) async => expect(
              server.application.events.where(
                (event) => event['name'] == args['1'],
              ),
              hasLength(1),
            ),
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the event must identify rule "([^"]+)"'),
            action: (_, __, args) async =>
                expect(server.application.events.single['ruleId'], args['1']),
          ),
        );

      final executor = ScenarioExecutor<MapScenarioWorld>(
        registry: registry,
        evidenceType: 'gherkin-api',
        target: 'backend',
        profile: Platform.environment['ZUKE_PROFILE'] ?? 'pullRequest',
        candidateId: AdditionScenarios.addIntegersApi.id,
        runnerId: 'calculator-api-tests',
        runnerCompatibilityId: 'calculator-api-tests-v1',
        digests: const {'runner': 'zuke-runner-http-v1'},
      );
      final results = await executor.executeScenario(
        feature,
        rule,
        scenario,
        MapScenarioWorld.new,
      );
      expect(results.status, ScenarioStatus.passed);
      const ExecutionResultWriter().writeScenarioToEnvironment(results);
      // The test produces a raw scenario result only. Zuke CLI binds it
      // to current workspace digests before publishing semantic evidence.
      await driver.dispose(MapScenarioWorld());
    },
  );
}
