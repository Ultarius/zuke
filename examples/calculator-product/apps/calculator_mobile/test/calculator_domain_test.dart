import 'dart:convert';
import 'dart:io';

import 'package:calculator_contracts/calculator_contracts.dart';
import 'package:calculator_domain/calculator_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

void _emit(ZukeScenarioContract contract, Object result) {
  const SuiteEvidenceEmitter().emitPassing(
    requirementId: contract.requirementId,
    scenarioId: contract.id,
    evidenceTypes: const ['domain-unit'],
    target: 'flutter',
    runnerCompatibilityId: 'calculator-flutter-tests-v1',
    digestInput: jsonEncode(result),
    runnerId: 'calculator-flutter-tests',
  );
}

@VerifiesRequirement(
  [
    FeatCalc001RequirementIds.addition,
    FeatCalc001RequirementIds.subtraction,
    FeatCalc001RequirementIds.multiplication,
    FeatCalc001RequirementIds.division,
    FeatCalc001RequirementIds.validation,
  ],
  evidenceType: 'domain-unit',
  target: 'flutter',
  variant: 'default',
)
void main() {
  final selectedScenarios = scenarioFilterFromEnvironment(Platform.environment);
  bool skipScenario(ZukeScenarioContract scenario) =>
      !shouldRunScenario(scenario.id.value, selectedScenarios);

  for (final testCase
      in <
        ({
          ZukeScenarioContract contract,
          CalculatorOperator operator,
          String first,
          String second,
          String expected,
        })
      >[
        (
          contract: AdditionScenarios.addIntegersUi,
          operator: CalculatorOperator.add,
          first: '2',
          second: '3',
          expected: '5',
        ),
        (
          contract: SubtractionScenarios.subtract,
          operator: CalculatorOperator.subtract,
          first: '3',
          second: '5',
          expected: '-2',
        ),
        (
          contract: MultiplicationScenarios.multiply,
          operator: CalculatorOperator.multiply,
          first: '2.5',
          second: '4',
          expected: '10',
        ),
        (
          contract: DivisionScenarios.divide,
          operator: CalculatorOperator.divide,
          first: '10',
          second: '2',
          expected: '5',
        ),
      ]) {
    test(
      '${testCase.contract.id}: ${testCase.contract.title}',
      () {
        final result = Calculator().evaluate(
          CalculationCommand(
            firstOperand: testCase.first,
            operator: testCase.operator,
            secondOperand: testCase.second,
          ),
        );
        expect(result.result, testCase.expected);
        _emit(testCase.contract, {'result': result.result});
      },
      skip: skipScenario(testCase.contract),
    );
  }

  test(
    '${DivisionScenarios.divideZero.id}: ${DivisionScenarios.divideZero.title}',
    () {
      final result = Calculator().evaluate(
        const CalculationCommand(
          firstOperand: '10',
          operator: CalculatorOperator.divide,
          secondOperand: '0',
        ),
      );
      expect(result.errorCode, 'DIVISION_BY_ZERO');
      _emit(DivisionScenarios.divideZero, {'errorCode': result.errorCode});
    },
    skip: skipScenario(DivisionScenarios.divideZero),
  );

  test(
    '${ValidationScenarios.badOperand.id}: ${ValidationScenarios.badOperand.title}',
    () {
      final parser = FiniteOperandParser();
      for (final input in [
        'NaN',
        'Infinity',
        'one',
        '<script>alert(1)</script>',
      ]) {
        expect(() => parser.parse(input), throwsFormatException);
      }
      _emit(ValidationScenarios.badOperand, {'rejected': true});
    },
    skip: skipScenario(ValidationScenarios.badOperand),
  );
}
