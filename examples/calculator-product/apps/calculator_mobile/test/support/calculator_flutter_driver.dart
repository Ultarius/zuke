import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calculator_contracts/calculator_contracts.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

class CalculatorWidgetWorld extends ScenarioWorld {
  final WidgetTester tester;
  final Key firstOperand;
  final Key operatorSelector;
  final Key secondOperand;
  final Key calculateAction;
  final Key display;
  final Key errorMessage;

  CalculatorWidgetWorld({
    required this.tester,
    required this.firstOperand,
    required this.operatorSelector,
    required this.secondOperand,
    required this.calculateAction,
    required this.display,
    required this.errorMessage,
  });
}

class CalculatorFlutterDriver
    extends FlutterScenarioDriver<CalculatorWidgetWorld>
    implements FeatCalc001FlutterDriver<CalculatorWidgetWorld> {
  final Widget Function(CalculatorWidgetWorld world) app;

  const CalculatorFlutterDriver({required this.app});

  @override
  Future<CalculatorWidgetWorld> create() async => throw StateError(
    'Create a CalculatorWidgetWorld from the project-owned testWidgets callback',
  );

  Future<CalculatorWidgetWorld> createFor(
    WidgetTester tester, {
    required Key firstOperand,
    required Key operatorSelector,
    required Key secondOperand,
    required Key calculateAction,
    required Key display,
    required Key errorMessage,
  }) async {
    final world = CalculatorWidgetWorld(
      tester: tester,
      firstOperand: firstOperand,
      operatorSelector: operatorSelector,
      secondOperand: secondOperand,
      calculateAction: calculateAction,
      display: display,
      errorMessage: errorMessage,
    );
    await tester.pumpWidget(app(world));
    return world;
  }

  @override
  Future<void> dispose(CalculatorWidgetWorld world) async {}

  @override
  Future<void> pumpAndSettle(CalculatorWidgetWorld world) =>
      world.tester.pumpAndSettle();

  @override
  Future<void> captureSemantics(CalculatorWidgetWorld world) async {
    final handle = world.tester.ensureSemantics();
    try {
      await world.tester.pump();
      expect(find.byKey(world.display), findsOneWidget);
    } finally {
      handle.dispose();
    }
  }

  @override
  Future<void> captureScreenshot(
    CalculatorWidgetWorld world,
    String name,
  ) async {
    // Screenshot bytes are owned by the Flutter test binding. The runner
    // records the logical attachment name and digest supplied by the binding.
    await world.tester.pump();
    if (name.isEmpty) throw ArgumentError.value(name, 'name');
  }

  @override
  Future<void> enterFirstOperand(
    CalculatorWidgetWorld world,
    String value,
  ) async {
    await world.tester.enterText(find.byKey(world.firstOperand), value);
    await world.tester.pump();
  }

  @override
  Future<void> enterOperatorSelector(
    CalculatorWidgetWorld world,
    String value,
  ) async {
    await world.tester.tap(find.byKey(world.operatorSelector));
    await world.tester.pumpAndSettle();
    await world.tester.tap(find.text(value).last);
    await world.tester.pump();
  }

  @override
  Future<void> enterSecondOperand(
    CalculatorWidgetWorld world,
    String value,
  ) async {
    await world.tester.enterText(find.byKey(world.secondOperand), value);
    await world.tester.pump();
  }

  @override
  Future<void> tapCalculateAction(CalculatorWidgetWorld world) async {
    await world.tester.tap(find.byKey(world.calculateAction));
    await world.tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  @override
  Future<String?> readDisplay(CalculatorWidgetWorld world) =>
      _textFor(world, world.display);

  @override
  Future<String?> readErrorMessage(CalculatorWidgetWorld world) =>
      _textFor(world, world.errorMessage);

  Future<String?> _textFor(CalculatorWidgetWorld world, Key key) async {
    final finder = find.byKey(key);
    if (finder.evaluate().isEmpty) return null;
    final widget = world.tester.widget<Text>(finder);
    return widget.data;
  }
}
