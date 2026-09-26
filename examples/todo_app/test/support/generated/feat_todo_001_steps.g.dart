// GENERATED. DO NOT EDIT.
// Source: FEAT-TODO-001

import 'dart:async';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

final class FeatTodo001GeneratedSteps<W extends ScenarioWorld> {
  const FeatTodo001GeneratedSteps();

  List<StepDefinition<W>> build({
    required FutureOr<void> Function(W world, String value1) taskIsComplete,
    required FutureOr<void> Function(W world) theTodoApplicationIsOpen,
    required FutureOr<void> Function(W world, String value1)
    theTodoListContainsTask,
    required FutureOr<void> Function(W world, String value1)
    theUserMarksTaskAsComplete,
    required FutureOr<void> Function(W world, String value1) theUserReopensTask,
  }) {
    final parameters = StepParameterTypeRegistry.standard();
    return [
      StepDefinition<W>.cucumber(
        expression: CucumberExpression('task {string} is complete', parameters),
        tier: StepTier.generated,
        target: 'flutter',
        action: (world, step, values) =>
            taskIsComplete(world, values[0] as String),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the todo application is open',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'flutter',
        action: (world, step, values) => theTodoApplicationIsOpen(world),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the todo list contains task {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'flutter',
        action: (world, step, values) =>
            theTodoListContainsTask(world, values[0] as String),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the user marks task {string} as complete',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'flutter',
        action: (world, step, values) =>
            theUserMarksTaskAsComplete(world, values[0] as String),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the user reopens task {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'flutter',
        action: (world, step, values) =>
            theUserReopensTask(world, values[0] as String),
      ),
    ];
  }
}
