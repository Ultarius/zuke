// GENERATED. DO NOT EDIT.
// Source: FEAT-LIBRARY-001

import 'dart:async';
import 'package:zuke/zuke.dart';

final class FeatLibrary001GeneratedSteps<W extends ScenarioWorld> {
  const FeatLibrary001GeneratedSteps();

  List<StepDefinition<W>> build({
    required FutureOr<void> Function(W world, String value1, String value2)
    branchConnectsToBranch,
    required FutureOr<void> Function(W world, String value1, String value2)
    branchHasLocalLoanISBN,
    required FutureOr<void> Function(W world, String value1, String value2)
    branchIsConnectedToBranch,
    required FutureOr<void> Function(W world, String value1)
    branchIsListeningForPeers,
    required FutureOr<void> Function(W world, String value1, String value2)
    branchReceivesLoanISBN,
    required FutureOr<void> Function(W world, String value1, String value2)
    branchReportsPeerState,
    required FutureOr<void> Function(W world, String value1, String value2)
    branchSharesItsLoanRegisterWithBranch,
    required FutureOr<void> Function(W world) theCheckoutDeskIsOpen,
    required FutureOr<void> Function(W world, String value1, String value2)
    theLibrarianEntersISBNInto,
    required FutureOr<void> Function(W world) theLibrarianHas3ActiveLoans,
    required FutureOr<void> Function(W world, String value1)
    theLibrarianHasAnActiveLoanForISBN,
    required FutureOr<void> Function(W world, String value1)
    theLibrarianReturnsTheLoanForISBN,
    required FutureOr<void> Function(W world, String value1) theLibrarianTaps,
    required FutureOr<void> Function(W world) theLoanRegisterIsEmpty,
    required FutureOr<void> Function(W world, String value1, String value2)
    thePeerConnectionBetweenAndIsEstablished,
  }) {
    final parameters = StepParameterTypeRegistry.standard();
    return [
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'branch {string} connects to branch {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) => branchConnectsToBranch(
          world,
          values[0] as String,
          values[1] as String,
        ),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'branch {string} has local loan ISBN {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) => branchHasLocalLoanISBN(
          world,
          values[0] as String,
          values[1] as String,
        ),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'branch {string} is connected to branch {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) => branchIsConnectedToBranch(
          world,
          values[0] as String,
          values[1] as String,
        ),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'branch {string} is listening for peers',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) =>
            branchIsListeningForPeers(world, values[0] as String),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'branch {string} receives loan ISBN {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) => branchReceivesLoanISBN(
          world,
          values[0] as String,
          values[1] as String,
        ),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'branch {string} reports peer state {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) => branchReportsPeerState(
          world,
          values[0] as String,
          values[1] as String,
        ),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'branch {string} shares its loan register with branch {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) => branchSharesItsLoanRegisterWithBranch(
          world,
          values[0] as String,
          values[1] as String,
        ),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression('the checkout desk is open', parameters),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) => theCheckoutDeskIsOpen(world),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the librarian enters ISBN {string} into {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) => theLibrarianEntersISBNInto(
          world,
          values[0] as String,
          values[1] as String,
        ),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the librarian has 3 active loans',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) => theLibrarianHas3ActiveLoans(world),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the librarian has an active loan for ISBN {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) =>
            theLibrarianHasAnActiveLoanForISBN(world, values[0] as String),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the librarian returns the loan for ISBN {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) =>
            theLibrarianReturnsTheLoanForISBN(world, values[0] as String),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the librarian taps {string}',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) =>
            theLibrarianTaps(world, values[0] as String),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the loan register is empty',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) => theLoanRegisterIsEmpty(world),
      ),
      StepDefinition<W>.cucumber(
        expression: CucumberExpression(
          'the peer connection between {string} and {string} is established',
          parameters,
        ),
        tier: StepTier.generated,
        target: 'catalog',
        action: (world, step, values) =>
            thePeerConnectionBetweenAndIsEstablished(
              world,
              values[0] as String,
              values[1] as String,
            ),
      ),
    ];
  }
}
