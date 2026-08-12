import 'dart:io';

import 'package:calculator_mobile/calculator_controller.dart';
import 'package:calculator_mobile/calculator_screen.dart';
import 'support/calculator_flutter_driver.dart';
import 'package:calculator_contracts/calculator_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:zuke/assurance.dart';

class _Bindings {
  final first = const Key('test.firstOperand');
  final operator = const Key('test.operatorSelector');
  final second = const Key('test.secondOperand');
  final calculate = const Key('test.calculateAction');
  final display = const Key('test.display');
  final error = const Key('test.errorMessage');
}

void main() {
  final selectedScenarios = scenarioFilterFromEnvironment(Platform.environment);
  final featureFile = File(
    '../../specs/features/calculator_operations.feature',
  );
  final parsed = GherkinParser().parseFile(
    featureFile.readAsStringSync(),
    featureFile.path,
  );
  final feature = parsed.features.single;
  final rule = feature.rules.firstWhere(
    (r) => r.metadata.id == AdditionScenarios.addIntegersUi.requirementId,
  );
  final scenario = rule.scenarios.firstWhere(
    (s) => s.scenarioElement.title == 'Add two positive integers in the UI',
  );
  final bindings = _Bindings();

  testWidgets(
    'Gherkin ${scenario.scenarioElement.title}',
    (tester) async {
      final driver = CalculatorFlutterDriver(
        app: (world) => MaterialApp(
          home: CalculatorScreen(
            bindings: _TestBindings(world),
            controller: CalculatorController(),
          ),
        ),
      );
      final world = await driver.createFor(
        tester,
        firstOperand: bindings.first,
        operatorSelector: bindings.operator,
        secondOperand: bindings.second,
        calculateAction: bindings.calculate,
        display: bindings.display,
        errorMessage: bindings.error,
      );
      final registry = StepRegistry<CalculatorWidgetWorld>()
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the calculator application is ready'),
            action: (world, _, _) async =>
                expect(find.byKey(world.firstOperand), findsOneWidget),
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the remote calculator feature is enabled'),
            action: (world, _, _) async =>
                expect(find.byKey(world.calculateAction), findsOneWidget),
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the first operand is "([^"]+)"'),
            action: (world, _, args) =>
                driver.enterFirstOperand(world, args['1']!),
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the selected operator is "([^"]+)"'),
            action: (world, _, args) =>
                driver.enterOperatorSelector(world, args['1']!),
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the second operand is "([^"]+)"'),
            action: (world, _, args) =>
                driver.enterSecondOperand(world, args['1']!),
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'the user requests the calculation'),
            action: (world, _, _) => driver.tapCalculateAction(world),
          ),
        )
        ..register(
          StepDefinition(
            priority: 300,
            pattern: RegExp(r'element "([^"]+)" must display "([^"]+)"'),
            action: (world, _, args) async =>
                expect(find.text(args['2']!), findsOneWidget),
          ),
        );

      final executor = ScenarioExecutor<CalculatorWidgetWorld>(
        registry: registry,
        evidenceType: 'gherkin-ui',
        target: 'flutter',
        profile: Platform.environment['ZUKE_PROFILE'] ?? 'pullRequest',
        candidateId: AdditionScenarios.addIntegersUi.id,
        runnerId: 'calculator-flutter-tests',
        runnerCompatibilityId: 'calculator-flutter-tests-v1',
        digests: const {'runner': 'zuke-runner-flutter-v1'},
      );
      final result = await executor.executeScenario(
        feature,
        rule,
        scenario,
        () => world,
      );
      if (result.status != ScenarioStatus.passed) {
        // Keep runner diagnostics visible when a generated step fails.
        // ignore: avoid_print
        print(result.toJson());
      }
      expect(result.status, ScenarioStatus.passed);
      const ExecutionResultWriter(
        identity: ExecutionSourceIdentity(
          sourcePackage: 'calculator-mobile',
          sourceAdapter: 'flutter-test',
          sourceCompatibilityId: 'flutter-test-v1',
        ),
      ).writeScenarioToEnvironment(result);
      // The test produces a raw scenario result only. Zuke CLI binds it to
      // current workspace digests before publishing semantic evidence.
      await driver.dispose(world);
    },
    skip: !shouldRunScenario(
      AdditionScenarios.addIntegersUi.id.value,
      selectedScenarios,
    ),
  );
}

class _TestBindings implements FeatCalc001FlutterBindings<Key> {
  final CalculatorWidgetWorld world;
  const _TestBindings(this.world);
  @override
  Key get firstOperand => world.firstOperand;
  @override
  Key get operatorSelector => world.operatorSelector;
  @override
  Key get secondOperand => world.secondOperand;
  @override
  Key get calculateAction => world.calculateAction;
  @override
  Key get display => world.display;
  @override
  Key get errorMessage => world.errorMessage;
}
