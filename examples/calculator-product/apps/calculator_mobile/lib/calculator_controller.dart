import 'package:flutter/foundation.dart';
import 'package:calculator_domain/calculator_domain.dart';
import 'package:calculator_contracts/calculator_contracts.dart';
import 'package:zuke/runtime.dart';

class CalculatorState {
  final String firstOperand;
  final String secondOperand;
  final String? selectedOperator;
  final String? displayResult;
  final String? errorMessageKey;

  const CalculatorState({
    this.firstOperand = '',
    this.secondOperand = '',
    this.selectedOperator,
    this.displayResult,
    this.errorMessageKey,
  });

  CalculatorState copyWith({
    String? firstOperand,
    String? secondOperand,
    String? selectedOperator,
    String? displayResult,
    String? errorMessageKey,
    bool clearDisplayResult = false,
    bool clearErrorMessageKey = false,
  }) {
    return CalculatorState(
      firstOperand: firstOperand ?? this.firstOperand,
      secondOperand: secondOperand ?? this.secondOperand,
      selectedOperator: selectedOperator ?? this.selectedOperator,
      displayResult: clearDisplayResult
          ? null
          : (displayResult ?? this.displayResult),
      errorMessageKey: clearErrorMessageKey
          ? null
          : (errorMessageKey ?? this.errorMessageKey),
    );
  }
}

typedef CalculationEvaluator =
    CalculationResult Function(CalculationCommand command);

sealed class CalculatorCalculationOutcome {
  const CalculatorCalculationOutcome();
}

sealed class CalculatorValidationFailure extends CalculatorCalculationOutcome {
  const CalculatorValidationFailure();
}

final class FirstOperandValidationFailure extends CalculatorValidationFailure {
  const FirstOperandValidationFailure();
}

final class SecondOperandValidationFailure extends CalculatorValidationFailure {
  const SecondOperandValidationFailure();
}

final class OperatorValidationFailure extends CalculatorValidationFailure {
  const OperatorValidationFailure();
}

final class CalculationAccepted extends CalculatorCalculationOutcome {
  const CalculationAccepted();
}

class CalculatorController extends ChangeNotifier {
  final CalculationEvaluator _evaluate;
  final ZukeEventBus events;
  CalculatorState _state = const CalculatorState();

  CalculatorController({
    Calculator? calculator,
    CalculationEvaluator? evaluator,
    ZukeEventBus? events,
  }) : assert(calculator == null || evaluator == null),
       _evaluate = evaluator ?? (calculator ?? Calculator()).evaluate,
       events = events ?? ZukeEventBus();

  CalculatorState get state => _state;

  void updateFirstOperand(String value) {
    _state = _state.copyWith(firstOperand: value);
    notifyListeners();
  }

  void updateSecondOperand(String value) {
    _state = _state.copyWith(secondOperand: value);
    notifyListeners();
  }

  void updateOperator(String operator) {
    _state = _state.copyWith(selectedOperator: operator);
    notifyListeners();
  }

  CalculatorCalculationOutcome calculate() {
    if (_state.firstOperand.isEmpty) {
      _state = _state.copyWith(
        errorMessageKey: 'calculator.error.firstOperandRequired',
      );
      notifyListeners();
      return const FirstOperandValidationFailure();
    }

    if (_state.secondOperand.isEmpty) {
      _state = _state.copyWith(
        errorMessageKey: 'calculator.error.secondOperandRequired',
      );
      notifyListeners();
      return const SecondOperandValidationFailure();
    }

    final op = _parseOperator(_state.selectedOperator);
    if (op == null) {
      _state = _state.copyWith(
        errorMessageKey: 'calculator.error.unsupportedOperator',
      );
      notifyListeners();
      return const OperatorValidationFailure();
    }

    _state = _state.copyWith(clearErrorMessageKey: true);
    notifyListeners();

    try {
      final command = CalculationCommand(
        firstOperand: _state.firstOperand,
        operator: op,
        secondOperand: _state.secondOperand,
      );
      final result = _evaluate(command);

      if (result.isFailure) {
        _state = _state.copyWith(
          errorMessageKey: result.errorCode == 'DIVISION_BY_ZERO'
              ? 'calculator.error.divisionByZero'
              : 'calculator.error.calculationFailed',
          displayResult: null,
        );
        events.emit(
          ZukeEvent(
            id: 'calculator.calculation.rejected',
            ruleId: _ruleForOperator(op),
            payload: {'errorCode': result.errorCode},
          ),
        );
      } else {
        _state = _state.copyWith(
          displayResult: result.result,
          clearErrorMessageKey: true,
        );
        events.emit(
          ZukeEvent(
            id: 'calculator.calculation.completed',
            ruleId: _ruleForOperator(op),
            payload: {'result': result.result},
          ),
        );
      }
    } catch (_) {
      _state = _state.copyWith(
        errorMessageKey: 'calculator.error.calculationFailed',
        clearDisplayResult: true,
      );
    }
    notifyListeners();
    return const CalculationAccepted();
  }

  CalculatorOperator? _parseOperator(String? op) {
    switch (op) {
      case '+':
        return CalculatorOperator.add;
      case '-':
        return CalculatorOperator.subtract;
      case '×':
        return CalculatorOperator.multiply;
      case '÷':
        return CalculatorOperator.divide;
      default:
        return null;
    }
  }

  String _ruleForOperator(CalculatorOperator operator) => switch (operator) {
    CalculatorOperator.add => FeatCalc001RequirementIds.addition,
    CalculatorOperator.subtract => FeatCalc001RequirementIds.subtraction,
    CalculatorOperator.multiply => FeatCalc001RequirementIds.multiplication,
    CalculatorOperator.divide => FeatCalc001RequirementIds.division,
  };
}
