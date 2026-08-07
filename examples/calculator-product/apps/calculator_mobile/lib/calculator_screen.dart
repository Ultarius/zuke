import 'package:flutter/material.dart';
import 'package:calculator_contracts/calculator_contracts.dart';
import 'package:zuke_annotations/zuke_annotations.dart';
import 'calculator_controller.dart';

@PresentsRequirement([
  FeatCalc001RequirementIds.addition,
  FeatCalc001RequirementIds.subtraction,
  FeatCalc001RequirementIds.multiplication,
  FeatCalc001RequirementIds.division,
  FeatCalc001RequirementIds.uiValidation,
  FeatCalc001RequirementIds.uiFailure,
  FeatCalc001RequirementIds.accessibility,
])
class CalculatorScreen extends StatefulWidget {
  final FeatCalc001FlutterBindings<Key> bindings;
  final CalculatorController controller;

  const CalculatorScreen({
    super.key,
    required this.bindings,
    required this.controller,
  });

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  late final TextEditingController _firstCtrl;
  late final TextEditingController _secondCtrl;
  late final FocusNode _firstFocus;
  late final FocusNode _secondFocus;
  final _operators = ['+', '-', '×', '÷'];
  String? _selectedOperator;

  @override
  void initState() {
    super.initState();
    _firstCtrl = TextEditingController();
    _secondCtrl = TextEditingController();
    _firstFocus = FocusNode();
    _secondFocus = FocusNode();
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    _firstCtrl.dispose();
    _secondCtrl.dispose();
    _firstFocus.dispose();
    _secondFocus.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;

    return Scaffold(
      appBar: AppBar(title: const Text('Calculator')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              key: widget.bindings.firstOperand,
              focusNode: _firstFocus,
              controller: _firstCtrl,
              decoration: const InputDecoration(labelText: 'First operand'),
              onChanged: widget.controller.updateFirstOperand,
            ),
            DropdownButtonFormField<String>(
              key: widget.bindings.operatorSelector,
              initialValue: _selectedOperator,
              items: _operators
                  .map((op) => DropdownMenuItem(value: op, child: Text(op)))
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedOperator = value);
                if (value != null) widget.controller.updateOperator(value);
              },
              decoration: const InputDecoration(labelText: 'Operator'),
            ),
            TextField(
              key: widget.bindings.secondOperand,
              focusNode: _secondFocus,
              controller: _secondCtrl,
              decoration: const InputDecoration(labelText: 'Second operand'),
              onChanged: widget.controller.updateSecondOperand,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: widget.bindings.calculateAction,
              onPressed: () {
                switch (widget.controller.calculate()) {
                  case FirstOperandValidationFailure():
                    FocusScope.of(context).requestFocus(_firstFocus);
                  case SecondOperandValidationFailure():
                    FocusScope.of(context).requestFocus(_secondFocus);
                  case OperatorValidationFailure():
                  case CalculationAccepted():
                    break;
                }
              },
              child: const Text('Calculate'),
            ),
            const SizedBox(height: 24),
            if (state.displayResult != null)
              Semantics(
                liveRegion: true,
                label: 'Result: ${state.displayResult}',
                child: Text(
                  state.displayResult!,
                  key: widget.bindings.display,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            if (state.errorMessageKey != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  state.errorMessageKey!,
                  key: widget.bindings.errorMessage,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
