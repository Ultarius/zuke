import 'package:calculator_contracts/calculator_contracts.dart';
import 'package:calculator_domain/calculator_domain.dart';
import 'package:calculator_mobile/calculator_bindings.dart';
import 'package:calculator_mobile/calculator_controller.dart';
import 'package:calculator_mobile/main.dart' as app;
import 'package:calculator_mobile/calculator_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

final class TestBindings implements FeatCalc001FlutterBindings<Key> {
  @override
  Key get firstOperand => const Key('test.firstOperand');
  @override
  Key get operatorSelector => const Key('test.operatorSelector');
  @override
  Key get secondOperand => const Key('test.secondOperand');
  @override
  Key get calculateAction => const Key('test.calculateAction');
  @override
  Key get display => const Key('test.display');
  @override
  Key get errorMessage => const Key('test.errorMessage');
}

Future<TestBindings> _pumpCalculator(
  WidgetTester tester, {
  CalculatorController? controller,
}) async {
  final bindings = TestBindings();
  await tester.pumpWidget(
    MaterialApp(
      home: CalculatorScreen(
        bindings: bindings,
        controller: controller ?? CalculatorController(),
      ),
    ),
  );
  return bindings;
}

Future<void> _calculate(
  WidgetTester tester,
  TestBindings bindings, {
  required String first,
  required String operator,
  required String second,
}) async {
  await tester.enterText(find.byKey(bindings.firstOperand), first);
  await tester.tap(find.byKey(bindings.operatorSelector));
  await tester.pumpAndSettle();
  await tester.tap(find.text(operator).last);
  await tester.enterText(find.byKey(bindings.secondOperand), second);
  await tester.tap(find.byKey(bindings.calculateAction));
  await tester.pumpAndSettle();
}

@VerifiesRequirement(
  [
    FeatCalc001RequirementIds.addition,
    FeatCalc001RequirementIds.subtraction,
    FeatCalc001RequirementIds.multiplication,
    FeatCalc001RequirementIds.division,
    FeatCalc001RequirementIds.uiValidation,
    FeatCalc001RequirementIds.uiFailure,
    FeatCalc001RequirementIds.accessibility,
  ],
  evidenceType: 'flutter-widget',
  target: 'flutter',
  variant: 'default',
)
void main() {
  const evidenceHarness = ZukeFlutterEvidenceHarness(
    runnerCompatibilityId: 'calculator-mobile-runner-v1',
    defaultEvidenceTypes: ['flutter-widget', 'gherkin-ui'],
  );

  evidenceHarness.registerAll([
    for (final testCase
        in <
          ({
            String rule,
            ZukeScenarioContract scenario,
            String operator,
            String first,
            String second,
            String result,
          })
        >[
          (
            rule: FeatCalc001RequirementIds.addition,
            scenario: AdditionScenarios.addIntegersUi,
            operator: '+',
            first: '2',
            second: '3',
            result: '5',
          ),
          (
            rule: FeatCalc001RequirementIds.subtraction,
            scenario: SubtractionScenarios.subtract,
            operator: '-',
            first: '3',
            second: '5',
            result: '-2',
          ),
          (
            rule: FeatCalc001RequirementIds.multiplication,
            scenario: MultiplicationScenarios.multiply,
            operator: '×',
            first: '2.5',
            second: '4',
            result: '10',
          ),
          (
            rule: FeatCalc001RequirementIds.division,
            scenario: DivisionScenarios.divide,
            operator: '÷',
            first: '10',
            second: '2',
            result: '5',
          ),
        ])
      FlutterEvidenceCase(
        scenario: testCase.scenario,
        body: (tester) async {
          final bindings = await _pumpCalculator(tester);
          await _calculate(
            tester,
            bindings,
            first: testCase.first,
            operator: testCase.operator,
            second: testCase.second,
          );
          expect(find.text(testCase.result), findsOneWidget);
          return testCase.result;
        },
      ),
    FlutterEvidenceCase(
      scenario: DivisionScenarios.divideZero,
      body: (tester) async {
        final bindings = await _pumpCalculator(tester);
        await _calculate(
          tester,
          bindings,
          first: '10',
          operator: '÷',
          second: '0',
        );
        expect(find.text('calculator.error.divisionByZero'), findsOneWidget);
        return 'calculator.error.divisionByZero';
      },
    ),
    FlutterEvidenceCase(
      scenario: UiValidationScenarios.missingFirst,
      body: (tester) async {
        final bindings = await _pumpCalculator(tester);
        await tester.enterText(find.byKey(bindings.secondOperand), '3');
        await tester.tap(find.byKey(bindings.calculateAction));
        await tester.pumpAndSettle();
        expect(
          find.text('calculator.error.firstOperandRequired'),
          findsOneWidget,
        );
        return 'calculator.error.firstOperandRequired';
      },
    ),
    FlutterEvidenceCase(
      scenario: UiValidationScenarios.missingOperator,
      body: (tester) async {
        final bindings = await _pumpCalculator(tester);
        await tester.enterText(find.byKey(bindings.firstOperand), '2');
        await tester.enterText(find.byKey(bindings.secondOperand), '3');
        await tester.tap(find.byKey(bindings.calculateAction));
        await tester.pumpAndSettle();
        expect(
          find.text('calculator.error.unsupportedOperator'),
          findsOneWidget,
        );
        return 'calculator.error.unsupportedOperator';
      },
    ),
    FlutterEvidenceCase(
      scenario: UiValidationScenarios.missingSecond,
      body: (tester) async {
        final bindings = await _pumpCalculator(tester);
        await tester.enterText(find.byKey(bindings.firstOperand), '2');
        await tester.tap(find.byKey(bindings.operatorSelector));
        await tester.pumpAndSettle();
        await tester.tap(find.text('+').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(bindings.calculateAction));
        await tester.pumpAndSettle();
        expect(
          find.text('calculator.error.secondOperandRequired'),
          findsOneWidget,
        );
        final field = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(bindings.secondOperand),
            matching: find.byType(EditableText),
          ),
        );
        expect(field.focusNode.hasFocus, isTrue);
        return 'calculator.error.secondOperandRequired';
      },
    ),
    FlutterEvidenceCase(
      scenario: UiFailureScenarios.calculationFailed,
      body: (tester) async {
        final bindings = await _pumpCalculator(
          tester,
          controller: CalculatorController(
            evaluator: (_) => CalculationResult.failure('REMOTE_FAILURE'),
          ),
        );
        await _calculate(
          tester,
          bindings,
          first: '2',
          operator: '+',
          second: '3',
        );
        expect(find.text('calculator.error.calculationFailed'), findsOneWidget);
        return 'calculator.error.calculationFailed';
      },
    ),
    FlutterEvidenceCase(
      scenario: AccessibilityScenarios.accessible,
      evidenceTypes: const [
        'flutter-widget',
        'gherkin-ui',
        'accessibility-integration',
      ],
      body: (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final bindings = await _pumpCalculator(tester);
          await _calculate(
            tester,
            bindings,
            first: '2',
            operator: '+',
            second: '3',
          );
          expect(find.bySemanticsLabel(RegExp(r'Result: 5')), findsOneWidget);
          expect(find.text('Calculate'), findsOneWidget);
          return 'Result: 5';
        } finally {
          semantics.dispose();
        }
      },
    ),
  ]);

  testWidgets('main launches calculator mobile app', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorScreen), findsOneWidget);
    final b = CalculatorBindings();
    expect(b.firstOperand, isNotNull);
    expect(b.operatorSelector, isNotNull);
    expect(b.secondOperand, isNotNull);
    expect(b.calculateAction, isNotNull);
    expect(b.display, isNotNull);
    expect(b.errorMessage, isNotNull);
  });
}
