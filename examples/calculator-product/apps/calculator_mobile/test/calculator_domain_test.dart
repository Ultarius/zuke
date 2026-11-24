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
  final feature = ZukeFeatureLoader.load('calculator_operations.feature');
  final invalid = resolveScenarioContract(
    feature,
    ValidationScenarios.badOperand,
  );
  void expectInvalidRow(int row) {
    final input = scenarioExampleCaseAt(
      invalid.scenario,
      examplesIndex: 0,
      rowIndex: row,
    ).values['input']!;
    expect(() => FiniteOperandParser().parse(input), throwsFormatException);
  }

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
    () => expectInvalidRow(0),
    scenario: ValidationScenarios.badOperand,
    evidenceTypes: const ['domain-unit'],
    caseId: 'examples-1-row-1',
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(ValidationScenarios.badOperand),
  );
  zukeTest(
    () => expectInvalidRow(1),
    scenario: ValidationScenarios.badOperand,
    evidenceTypes: const ['domain-unit'],
    caseId: 'examples-1-row-2',
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(ValidationScenarios.badOperand),
  );
  zukeTest(
    () => expectInvalidRow(2),
    scenario: ValidationScenarios.badOperand,
    evidenceTypes: const ['domain-unit'],
    caseId: 'examples-1-row-3',
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(ValidationScenarios.badOperand),
  );
  zukeTest(
    () => expectInvalidRow(3),
    scenario: ValidationScenarios.badOperand,
    evidenceTypes: const ['domain-unit'],
    caseId: 'examples-1-row-4',
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(ValidationScenarios.badOperand),
  );
  zukeTest(
    () => expectInvalidRow(4),
    scenario: ValidationScenarios.badOperand,
    evidenceTypes: const ['domain-unit'],
    caseId: 'examples-1-row-5',
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
