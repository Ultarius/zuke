import 'dart:io';

import 'package:calculator_contracts/calculator_contracts.dart';
import 'package:calculator_domain/calculator_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

@VerifiesRequirement(
  [
    FeatCalc001RequirementIds.addition,
    FeatCalc001RequirementIds.subtraction,
    FeatCalc001RequirementIds.multiplication,
    FeatCalc001RequirementIds.division,
    FeatCalc001RequirementIds.validation,
  ],
  evidenceType: 'domain-unit',
  variant: 'default',
)
void main() {
  final selectedScenarios = scenarioFilterFromEnvironment(Platform.environment);
  bool skipScenario(ZukeScenarioContract scenario) =>
      !shouldRunScenario(scenario.id.value, selectedScenarios);

  Future<void> expectCalculation({
    required String first,
    required CalculatorOperator operator,
    required String second,
    required String expected,
  }) async {
    final result = Calculator().evaluate(
      CalculationCommand(
        firstOperand: first,
        operator: operator,
        secondOperand: second,
      ),
    );
    expect(result.result, expected);
  }

  zukeTest(
    () => expectCalculation(
      first: '2',
      operator: CalculatorOperator.add,
      second: '3',
      expected: '5',
    ),
    scenario: AdditionScenarios.addIntegersApi,
    evidenceTypes: const ['domain-unit'],
    caseId: 'domain',
    skip: skipScenario(AdditionScenarios.addIntegersApi),
  );
  zukeTest(
    () => expectCalculation(
      first: '2',
      operator: CalculatorOperator.add,
      second: '3',
      expected: '5',
    ),
    scenario: AdditionScenarios.addIntegersUi,
    evidenceTypes: const ['domain-unit'],
    caseId: 'domain',
    skip: skipScenario(AdditionScenarios.addIntegersUi),
  );
  zukeTest(
    () => expectCalculation(
      first: '3',
      operator: CalculatorOperator.subtract,
      second: '5',
      expected: '-2',
    ),
    scenario: SubtractionScenarios.subtract,
    evidenceTypes: const ['domain-unit'],
    caseId: 'domain',
    skip: skipScenario(SubtractionScenarios.subtract),
  );
  zukeTest(
    () => expectCalculation(
      first: '2.5',
      operator: CalculatorOperator.multiply,
      second: '4',
      expected: '10',
    ),
    scenario: MultiplicationScenarios.multiply,
    evidenceTypes: const ['domain-unit'],
    caseId: 'domain',
    skip: skipScenario(MultiplicationScenarios.multiply),
  );
  zukeTest(
    () => expectCalculation(
      first: '10',
      operator: CalculatorOperator.divide,
      second: '2',
      expected: '5',
    ),
    scenario: DivisionScenarios.divide,
    evidenceTypes: const ['domain-unit'],
    caseId: 'domain',
    skip: skipScenario(DivisionScenarios.divide),
  );
  zukeTest(
    () async {
      final result = Calculator().evaluate(
        const CalculationCommand(
          firstOperand: '10',
          operator: CalculatorOperator.divide,
          secondOperand: '0',
        ),
      );
      expect(result.errorCode, 'DIVISION_BY_ZERO');
    },
    scenario: DivisionScenarios.divideZero,
    evidenceTypes: const ['domain-unit'],
    caseId: 'domain',
    skip: skipScenario(DivisionScenarios.divideZero),
  );
  zukeTest(
    () async {
      final parser = FiniteOperandParser();
      for (final input in [
        'NaN',
        'Infinity',
        'one',
        '<script>alert(1)</script>',
      ]) {
        expect(() => parser.parse(input), throwsFormatException);
      }
    },
    scenario: ValidationScenarios.badOperand,
    evidenceTypes: const ['domain-unit'],
    caseId: 'domain',
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(ValidationScenarios.badOperand),
  );
  zukeTest(
    () async {
      // The HTTP boundary rejects the raw "exec" input in the backend case.
      // This domain case proves that the calculator core exposes no
      // unregistered operator for a request to evaluate.
      expect(
        CalculatorOperator.values,
        containsAll([
          CalculatorOperator.add,
          CalculatorOperator.subtract,
          CalculatorOperator.multiply,
          CalculatorOperator.divide,
        ]),
      );
      expect(CalculatorOperator.values, hasLength(4));
    },
    scenario: ValidationScenarios.badOperator,
    evidenceTypes: const ['domain-unit'],
    caseId: 'domain',
    skip: skipScenario(ValidationScenarios.badOperator),
  );
}
