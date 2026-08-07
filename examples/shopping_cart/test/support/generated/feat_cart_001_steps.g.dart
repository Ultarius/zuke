// GENERATED. DO NOT EDIT.
// Source: FEAT-CART-001

import 'dart:async';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

final class FeatCart001GeneratedSteps<W extends ScenarioWorld> {
  const FeatCart001GeneratedSteps();

  List<StepDefinition<W>> build({
    required FutureOr<void> Function(W world, String value1, String value2)
    theCartContainsItemAtPrice,
    required FutureOr<void> Function(W world) theCartIsCompletelyEmpty,
    required FutureOr<void> Function(W world, String value1, String value2)
    theCatalogItemIsListedAtPrice,
    required FutureOr<void> Function(W world)
    theCheckoutButtonStateMustBeDisabled,
    required FutureOr<void> Function(W world, String value1)
    theSemanticsTreeMustContainLabelMatching,
    required FutureOr<void> Function(W world) theShoppingApplicationIsOpen,
    required FutureOr<void> Function(W world) theUserViewsTheCheckoutSummary,
  }) {
    final parameters = StepParameterTypeRegistry.standard();
    return [
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the cart contains item {string} at price {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'flutter',
        action: (world, step, values) => theCartContainsItemAtPrice(
          world,
          values[0] as String,
          values[1] as String,
        ),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the cart is completely empty',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'flutter',
        action: (world, step, values) => theCartIsCompletelyEmpty(world),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the catalog item {string} is listed at price {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'flutter',
        action: (world, step, values) => theCatalogItemIsListedAtPrice(
          world,
          values[0] as String,
          values[1] as String,
        ),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the checkout button state must be disabled',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'flutter',
        action: (world, step, values) =>
            theCheckoutButtonStateMustBeDisabled(world),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the semantics tree must contain label matching {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'flutter',
        action: (world, step, values) =>
            theSemanticsTreeMustContainLabelMatching(
              world,
              values[0] as String,
            ),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the shopping application is open',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'flutter',
        action: (world, step, values) => theShoppingApplicationIsOpen(world),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the user views the checkout summary',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'flutter',
        action: (world, step, values) => theUserViewsTheCheckoutSummary(world),
      ),
    ];
  }
}
