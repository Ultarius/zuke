enum CalculatorOperator { add, subtract, multiply, divide }

class CalculationCommand {
  final String firstOperand;
  final CalculatorOperator operator;
  final String secondOperand;

  const CalculationCommand({
    required this.firstOperand,
    required this.operator,
    required this.secondOperand,
  });
}
