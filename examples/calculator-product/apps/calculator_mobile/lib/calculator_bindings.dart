import 'package:flutter/foundation.dart';
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:calculator_contracts/calculator_contracts.dart';

final class CalculatorBindings implements FeatCalc001FlutterBindings<Key> {
  @override
  @ZukeBinding('calculator.firstOperand')
  Key get firstOperand => const Key('calculator.firstOperand');

  @override
  @ZukeBinding('calculator.operatorSelector')
  Key get operatorSelector => const Key('calculator.operatorSelector');

  @override
  @ZukeBinding('calculator.secondOperand')
  Key get secondOperand => const Key('calculator.secondOperand');

  @override
  @ZukeBinding('calculator.calculateAction')
  Key get calculateAction => const Key('calculator.calculateAction');

  @override
  @ZukeBinding('calculator.display')
  Key get display => const Key('calculator.display');

  @override
  @ZukeBinding('calculator.errorMessage')
  Key get errorMessage => const Key('calculator.errorMessage');
}
