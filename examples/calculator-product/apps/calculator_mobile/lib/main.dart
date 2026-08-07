import 'package:flutter/material.dart';
import 'calculator_screen.dart';
import 'calculator_controller.dart';
import 'calculator_bindings.dart';

void main() {
  final bindings = CalculatorBindings();
  final controller = CalculatorController();

  runApp(
    MaterialApp(
      title: 'Calculator',
      home: CalculatorScreen(bindings: bindings, controller: controller),
    ),
  );
}
