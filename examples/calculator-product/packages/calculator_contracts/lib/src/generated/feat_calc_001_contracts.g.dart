// GENERATED. DO NOT EDIT.
// Source: FEAT-CALC-001 (specs/features/calculator_operations.feature)

import 'package:zuke_annotations/zuke_annotations.dart';

sealed class FeatCalc001FlutterBinding implements ZukeBindingDescriptor {
  const FeatCalc001FlutterBinding(this.id);
  @override
  final String id;

  T keyIn<T extends Object>(FeatCalc001FlutterBindings<T> bindings);

  static const firstOperand = FeatCalc001FirstOperandBinding();
  static const operatorSelector = FeatCalc001OperatorSelectorBinding();
  static const secondOperand = FeatCalc001SecondOperandBinding();
  static const calculateAction = FeatCalc001CalculateActionBinding();
  static const display = FeatCalc001DisplayBinding();
  static const errorMessage = FeatCalc001ErrorMessageBinding();

  static FeatCalc001FlutterBinding fromId(String bindingId) =>
      switch (bindingId) {
        'calculator.firstOperand' => firstOperand,
        'calculator.operatorSelector' => operatorSelector,
        'calculator.secondOperand' => secondOperand,
        'calculator.calculateAction' => calculateAction,
        'calculator.display' => display,
        'calculator.errorMessage' => errorMessage,
        _ => throw ArgumentError.value(
          bindingId,
          'bindingId',
          'Unknown Flutter binding for FEAT-CALC-001',
        ),
      };
}

final class FeatCalc001FirstOperandBinding extends FeatCalc001FlutterBinding {
  const FeatCalc001FirstOperandBinding() : super('calculator.firstOperand');

  @override
  T keyIn<T extends Object>(FeatCalc001FlutterBindings<T> bindings) =>
      bindings.firstOperand;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCalc001OperatorSelectorBinding
    extends FeatCalc001FlutterBinding {
  const FeatCalc001OperatorSelectorBinding()
    : super('calculator.operatorSelector');

  @override
  T keyIn<T extends Object>(FeatCalc001FlutterBindings<T> bindings) =>
      bindings.operatorSelector;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCalc001SecondOperandBinding extends FeatCalc001FlutterBinding {
  const FeatCalc001SecondOperandBinding() : super('calculator.secondOperand');

  @override
  T keyIn<T extends Object>(FeatCalc001FlutterBindings<T> bindings) =>
      bindings.secondOperand;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCalc001CalculateActionBinding
    extends FeatCalc001FlutterBinding {
  const FeatCalc001CalculateActionBinding()
    : super('calculator.calculateAction');

  @override
  T keyIn<T extends Object>(FeatCalc001FlutterBindings<T> bindings) =>
      bindings.calculateAction;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCalc001DisplayBinding extends FeatCalc001FlutterBinding {
  const FeatCalc001DisplayBinding() : super('calculator.display');

  @override
  T keyIn<T extends Object>(FeatCalc001FlutterBindings<T> bindings) =>
      bindings.display;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCalc001ErrorMessageBinding extends FeatCalc001FlutterBinding {
  const FeatCalc001ErrorMessageBinding() : super('calculator.errorMessage');

  @override
  T keyIn<T extends Object>(FeatCalc001FlutterBindings<T> bindings) =>
      bindings.errorMessage;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.zeroOrOne;
}

abstract interface class FeatCalc001FlutterBindings<T extends Object> {
  T get firstOperand;
  T get operatorSelector;
  T get secondOperand;
  T get calculateAction;
  T get display;
  T get errorMessage;
}

mixin FeatCalc001BindingDrivenFlutterDriver<W, T extends Object>
    implements FeatCalc001FlutterDriver<W> {
  FeatCalc001FlutterBindings<T> bindingsFor(W world);
  Future<void> zukeEnterBinding(W world, T key, String value);
  Future<void> zukeTapBinding(W world, T key);
  Future<String?> zukeReadBinding(W world, T key);
  Future<void> zukeEnterBindingInstance(
    W world,
    T key,
    Object instanceId,
    String value,
  );
  Future<void> zukeTapBindingInstance(W world, T key, Object instanceId);
  Future<String?> zukeReadBindingInstance(W world, T key, Object instanceId);
  Future<List<String>> zukeReadAllBindings(W world, T key);
  @override
  Future<void> enterFirstOperand(W world, String value) =>
      zukeEnterBinding(world, bindingsFor(world).firstOperand, value);
  @override
  Future<void> enterOperatorSelector(W world, String value) =>
      zukeEnterBinding(world, bindingsFor(world).operatorSelector, value);
  @override
  Future<void> enterSecondOperand(W world, String value) =>
      zukeEnterBinding(world, bindingsFor(world).secondOperand, value);
  @override
  Future<void> tapCalculateAction(W world) =>
      zukeTapBinding(world, bindingsFor(world).calculateAction);
  @override
  Future<String?> readDisplay(W world) =>
      zukeReadBinding(world, bindingsFor(world).display);
  @override
  Future<String?> readErrorMessage(W world) =>
      zukeReadBinding(world, bindingsFor(world).errorMessage);
}

abstract interface class FeatCalc001FlutterDriver<W> {
  Future<void> enterFirstOperand(W world, String value);
  Future<void> enterOperatorSelector(W world, String value);
  Future<void> enterSecondOperand(W world, String value);
  Future<void> tapCalculateAction(W world);
  Future<String?> readDisplay(W world);
  Future<String?> readErrorMessage(W world);
}

abstract final class FeatCalc001RequirementIds {
  static const addition = 'RULE-CALC-ADDITION';
  static const subtraction = 'RULE-CALC-SUBTRACTION';
  static const multiplication = 'RULE-CALC-MULTIPLICATION';
  static const division = 'RULE-CALC-DIVISION';
  static const uiValidation = 'RULE-CALC-UI-VALIDATION';
  static const uiFailure = 'RULE-CALC-UI-FAILURE';
  static const validation = 'RULE-CALC-VALIDATION';
  static const accessibility = 'RULE-CALC-ACCESSIBILITY';
  static const performance = 'RULE-CALC-PERFORMANCE';
}

enum FeatCalc001Scenario implements ZukeScenarioContract {
  addIntegersApi(
    ScenarioId('SCN-CALC-ADD-INTEGERS-API'),
    'RULE-CALC-ADDITION',
    'Add two positive integers through the API',
    <String>{},
  ),
  addIntegersUi(
    ScenarioId('SCN-CALC-ADD-INTEGERS-UI'),
    'RULE-CALC-ADDITION',
    'Add two positive integers in the UI',
    <String>{},
  ),
  addValues(
    ScenarioId('SCN-CALC-ADD-VALUES'),
    'RULE-CALC-ADDITION',
    'Add representative valid operands',
    <String>{},
  ),
  subtract(
    ScenarioId('SCN-CALC-SUBTRACT'),
    'RULE-CALC-SUBTRACTION',
    'Subtract a larger second operand',
    <String>{},
  ),
  multiply(
    ScenarioId('SCN-CALC-MULTIPLY'),
    'RULE-CALC-MULTIPLICATION',
    'Multiply decimal operands',
    <String>{},
  ),
  divide(
    ScenarioId('SCN-CALC-DIVIDE'),
    'RULE-CALC-DIVISION',
    'Divide two exactly divisible integers',
    <String>{'CTRL-CALC-ERROR-REDACTION'},
  ),
  divideDecimal(
    ScenarioId('SCN-CALC-DIVIDE-DECIMAL'),
    'RULE-CALC-DIVISION',
    'Divide operands producing a decimal result',
    <String>{'CTRL-CALC-ERROR-REDACTION'},
  ),
  divideZero(
    ScenarioId('SCN-CALC-DIVIDE-ZERO'),
    'RULE-CALC-DIVISION',
    'Reject division by zero without leaking an internal error',
    <String>{'CTRL-CALC-ERROR-REDACTION'},
  ),
  missingFirst(
    ScenarioId('SCN-CALC-MISSING-FIRST'),
    'RULE-CALC-UI-VALIDATION',
    'Reject a calculation with no first operand in Flutter',
    <String>{},
  ),
  missingOperator(
    ScenarioId('SCN-CALC-MISSING-OPERATOR'),
    'RULE-CALC-UI-VALIDATION',
    'Reject a calculation with no selected operator in Flutter',
    <String>{},
  ),
  missingSecond(
    ScenarioId('SCN-CALC-MISSING-SECOND'),
    'RULE-CALC-UI-VALIDATION',
    'Reject a calculation with no second operand in Flutter',
    <String>{},
  ),
  calculationFailed(
    ScenarioId('SCN-CALC-CALCULATION-FAILED'),
    'RULE-CALC-UI-FAILURE',
    'Show a generic message when the calculator service fails unexpectedly',
    <String>{},
  ),
  badOperator(
    ScenarioId('SCN-CALC-BAD-OPERATOR'),
    'RULE-CALC-VALIDATION',
    'Reject an operator outside the registered operator set',
    <String>{'CTRL-CALC-INPUT-VALIDATION'},
  ),
  badOperand(
    ScenarioId('SCN-CALC-BAD-OPERAND'),
    'RULE-CALC-VALIDATION',
    'Reject non-numeric operand input',
    <String>{'CTRL-CALC-INPUT-VALIDATION'},
  ),
  accessible(
    ScenarioId('SCN-CALC-ACCESSIBLE'),
    'RULE-CALC-ACCESSIBILITY',
    'Complete a calculation using accessible controls',
    <String>{},
  ),
  p95(
    ScenarioId('SCN-CALC-P95'),
    'RULE-CALC-PERFORMANCE',
    'Standard load satisfies the p95 latency budget',
    <String>{},
  );

  const FeatCalc001Scenario(
    this.id,
    this.requirementId,
    this.title,
    this.controlIds,
  );
  @override
  final ScenarioId id;
  @override
  final String requirementId;
  @override
  final String title;
  @override
  final Set<String> controlIds;
}

abstract final class FeatCalc001Scenarios {
  static const all = FeatCalc001Scenario.values;
  static final Map<ScenarioId, FeatCalc001Scenario>
  byId = Map.unmodifiable(<ScenarioId, FeatCalc001Scenario>{
    ScenarioId('SCN-CALC-ADD-INTEGERS-API'): FeatCalc001Scenario.addIntegersApi,
    ScenarioId('SCN-CALC-ADD-INTEGERS-UI'): FeatCalc001Scenario.addIntegersUi,
    ScenarioId('SCN-CALC-ADD-VALUES'): FeatCalc001Scenario.addValues,
    ScenarioId('SCN-CALC-SUBTRACT'): FeatCalc001Scenario.subtract,
    ScenarioId('SCN-CALC-MULTIPLY'): FeatCalc001Scenario.multiply,
    ScenarioId('SCN-CALC-DIVIDE'): FeatCalc001Scenario.divide,
    ScenarioId('SCN-CALC-DIVIDE-DECIMAL'): FeatCalc001Scenario.divideDecimal,
    ScenarioId('SCN-CALC-DIVIDE-ZERO'): FeatCalc001Scenario.divideZero,
    ScenarioId('SCN-CALC-MISSING-FIRST'): FeatCalc001Scenario.missingFirst,
    ScenarioId('SCN-CALC-MISSING-OPERATOR'):
        FeatCalc001Scenario.missingOperator,
    ScenarioId('SCN-CALC-MISSING-SECOND'): FeatCalc001Scenario.missingSecond,
    ScenarioId('SCN-CALC-CALCULATION-FAILED'):
        FeatCalc001Scenario.calculationFailed,
    ScenarioId('SCN-CALC-BAD-OPERATOR'): FeatCalc001Scenario.badOperator,
    ScenarioId('SCN-CALC-BAD-OPERAND'): FeatCalc001Scenario.badOperand,
    ScenarioId('SCN-CALC-ACCESSIBLE'): FeatCalc001Scenario.accessible,
    ScenarioId('SCN-CALC-P95'): FeatCalc001Scenario.p95,
  });
  static final Map<String, List<FeatCalc001Scenario>> byRule = Map.unmodifiable(
    <String, List<FeatCalc001Scenario>>{
      'RULE-CALC-ADDITION': List.unmodifiable(<FeatCalc001Scenario>[
        FeatCalc001Scenario.addIntegersApi,
        FeatCalc001Scenario.addIntegersUi,
        FeatCalc001Scenario.addValues,
      ]),
      'RULE-CALC-SUBTRACTION': List.unmodifiable(<FeatCalc001Scenario>[
        FeatCalc001Scenario.subtract,
      ]),
      'RULE-CALC-MULTIPLICATION': List.unmodifiable(<FeatCalc001Scenario>[
        FeatCalc001Scenario.multiply,
      ]),
      'RULE-CALC-DIVISION': List.unmodifiable(<FeatCalc001Scenario>[
        FeatCalc001Scenario.divide,
        FeatCalc001Scenario.divideDecimal,
        FeatCalc001Scenario.divideZero,
      ]),
      'RULE-CALC-UI-VALIDATION': List.unmodifiable(<FeatCalc001Scenario>[
        FeatCalc001Scenario.missingFirst,
        FeatCalc001Scenario.missingOperator,
        FeatCalc001Scenario.missingSecond,
      ]),
      'RULE-CALC-UI-FAILURE': List.unmodifiable(<FeatCalc001Scenario>[
        FeatCalc001Scenario.calculationFailed,
      ]),
      'RULE-CALC-VALIDATION': List.unmodifiable(<FeatCalc001Scenario>[
        FeatCalc001Scenario.badOperator,
        FeatCalc001Scenario.badOperand,
      ]),
      'RULE-CALC-ACCESSIBILITY': List.unmodifiable(<FeatCalc001Scenario>[
        FeatCalc001Scenario.accessible,
      ]),
      'RULE-CALC-PERFORMANCE': List.unmodifiable(<FeatCalc001Scenario>[
        FeatCalc001Scenario.p95,
      ]),
    },
  );
  static List<FeatCalc001Scenario> matching(ZukeScenarioPattern pattern) =>
      all.where(pattern.matches).toList(growable: false);
}

abstract final class AdditionScenarios {
  static const addIntegersApi = FeatCalc001Scenario.addIntegersApi;
  static const addIntegersUi = FeatCalc001Scenario.addIntegersUi;
  static const addValues = FeatCalc001Scenario.addValues;
  static const all = <ZukeScenarioContract>[
    FeatCalc001Scenario.addIntegersApi,
    FeatCalc001Scenario.addIntegersUi,
    FeatCalc001Scenario.addValues,
  ];
}

abstract final class SubtractionScenarios {
  static const subtract = FeatCalc001Scenario.subtract;
  static const all = <ZukeScenarioContract>[FeatCalc001Scenario.subtract];
}

abstract final class MultiplicationScenarios {
  static const multiply = FeatCalc001Scenario.multiply;
  static const all = <ZukeScenarioContract>[FeatCalc001Scenario.multiply];
}

abstract final class DivisionScenarios {
  static const divide = FeatCalc001Scenario.divide;
  static const divideDecimal = FeatCalc001Scenario.divideDecimal;
  static const divideZero = FeatCalc001Scenario.divideZero;
  static const all = <ZukeScenarioContract>[
    FeatCalc001Scenario.divide,
    FeatCalc001Scenario.divideDecimal,
    FeatCalc001Scenario.divideZero,
  ];
}

abstract final class UiValidationScenarios {
  static const missingFirst = FeatCalc001Scenario.missingFirst;
  static const missingOperator = FeatCalc001Scenario.missingOperator;
  static const missingSecond = FeatCalc001Scenario.missingSecond;
  static const all = <ZukeScenarioContract>[
    FeatCalc001Scenario.missingFirst,
    FeatCalc001Scenario.missingOperator,
    FeatCalc001Scenario.missingSecond,
  ];
}

abstract final class UiFailureScenarios {
  static const calculationFailed = FeatCalc001Scenario.calculationFailed;
  static const all = <ZukeScenarioContract>[
    FeatCalc001Scenario.calculationFailed,
  ];
}

abstract final class ValidationScenarios {
  static const badOperator = FeatCalc001Scenario.badOperator;
  static const badOperand = FeatCalc001Scenario.badOperand;
  static const all = <ZukeScenarioContract>[
    FeatCalc001Scenario.badOperator,
    FeatCalc001Scenario.badOperand,
  ];
}

abstract final class AccessibilityScenarios {
  static const accessible = FeatCalc001Scenario.accessible;
  static const all = <ZukeScenarioContract>[FeatCalc001Scenario.accessible];
}

abstract final class PerformanceScenarios {
  static const p95 = FeatCalc001Scenario.p95;
  static const all = <ZukeScenarioContract>[FeatCalc001Scenario.p95];
}
