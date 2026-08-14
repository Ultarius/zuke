import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:calculator_contracts/calculator_contracts.dart';
import 'calculation_command.dart';
import 'calculation_result.dart';
import 'finite_operand_parser.dart';

@ImplementsRequirement([
  FeatCalc001RequirementIds.addition,
  FeatCalc001RequirementIds.subtraction,
  FeatCalc001RequirementIds.multiplication,
  FeatCalc001RequirementIds.division,
  FeatCalc001RequirementIds.validation,
], target: 'flutter')
class Calculator {
  final FiniteOperandParser _parser;

  Calculator({FiniteOperandParser? parser})
    : _parser = parser ?? FiniteOperandParser();

  CalculationResult evaluate(CalculationCommand command) {
    num first;
    num second;
    try {
      first = _parser.parse(command.firstOperand);
      second = _parser.parse(command.secondOperand);
    } catch (_) {
      return CalculationResult.failure('INVALID_OPERAND');
    }

    return switch (command.operator) {
      CalculatorOperator.add => CalculationResult.success(
        _format(first + second),
      ),
      CalculatorOperator.subtract => CalculationResult.success(
        _format(first - second),
      ),
      CalculatorOperator.multiply => CalculationResult.success(
        _format(first * second),
      ),
      CalculatorOperator.divide when second == 0 => CalculationResult.failure(
        'DIVISION_BY_ZERO',
      ),
      CalculatorOperator.divide => CalculationResult.success(
        _format(first / second),
      ),
    };
  }

  String _format(num value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value
        .toStringAsFixed(10)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
