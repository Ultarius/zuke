import 'package:calculator_domain/calculator_domain.dart';
import 'package:test/test.dart';

void main() {
  test('FiniteOperandParser parses valid operands', () {
    final parser = FiniteOperandParser();
    expect(parser.parse('3'), 3);
    expect(parser.parse('0'), 0);
    expect(parser.parse('3.14'), 3.14);
  });

  test('FiniteOperandParser rejects empty input', () {
    final parser = FiniteOperandParser();
    expect(() => parser.parse(''), throwsFormatException);
  });

  test('CalculationResult success stores result', () {
    final result = CalculationResult.success('42');
    expect(result.isSuccess, isTrue);
    expect(result.isFailure, isFalse);
  });

  test('CalculationResult failure stores error', () {
    final result = CalculationResult.failure('ERR-001');
    expect(result.isFailure, isTrue);
    expect(result.isSuccess, isFalse);
  });

  test('CalculationCommand stores operands', () {
    final cmd = CalculationCommand(
      firstOperand: '3',
      operator: CalculatorOperator.add,
      secondOperand: '4',
    );
    expect(cmd.firstOperand, '3');
    expect(cmd.operator, CalculatorOperator.add);
  });
}
