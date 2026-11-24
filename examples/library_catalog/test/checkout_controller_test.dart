import 'dart:io';

import 'package:library_catalog/library_catalog.dart';
import 'package:test/test.dart';
import 'package:zuke/zuke.dart';

import 'support/library_fixtures.dart';

@VerifiesRequirement(
  [
    FeatLibrary001RequirementIds.checkout,
    FeatLibrary001RequirementIds.bookReturn,
    FeatLibrary001RequirementIds.branchPeer,
  ],
  evidenceType: 'domain-unit',
  variant: 'default',
)
void main() {
  final selectedScenarios = scenarioFilterFromEnvironment(Platform.environment);
  bool skipScenario(ZukeScenarioContract scenario) =>
      !shouldRunScenario(scenario.id.value, selectedScenarios);

  const isbnValidation = ControlId('CTRL-LIBRARY-ISBN-VALIDATION');

  group('generated contracts', () {
    test('exposes stable requirement and scenario identities', () {
      // zuke: allow-raw-id -- these asserts pin the generated contract literals.
      expect(FeatLibrary001RequirementIds.checkout, 'RULE-LIBRARY-CHECKOUT');
      expect(
        FeatLibrary001RequirementIds.bookReturn,
        // zuke: allow-raw-id -- these asserts pin the generated contract literals.
        'RULE-LIBRARY-BOOK-RETURN',
      );
      expect(
        FeatLibrary001Scenarios.all.map((s) => s.id.value),
        containsAll([
          CheckoutScenarios.checkoutValid.id.value,
          CheckoutScenarios.checkoutBadIsbn.id.value,
          CheckoutScenarios.checkoutEmpty.id.value,
          CheckoutScenarios.checkoutLimit.id.value,
          BookReturnScenarios.return_.id.value,
        ]),
      );
    });

    test('binding catalog matches the feature header', () {
      final bindings = CatalogBindings();
      expect(bindings.isbnInput.id, 'library.isbnInput');
      expect(bindings.checkoutButton.id, 'library.checkoutButton');
      expect(bindings.loanList.id, 'library.loanList');
      expect(bindings.loanCountDisplay.id, 'library.loanCountDisplay');
      expect(bindings.errorMessage.id, 'library.errorMessage');
      expect(bindings.statusMessage.id, 'library.statusMessage');
      expect(
        FeatLibrary001FlutterBinding.fromId('library.isbnInput'),
        FeatLibrary001FlutterBinding.isbnInput,
      );
    });
  });

  zukeTest(
    () {
      final desk = openCheckoutDesk();
      expect(desk.checkout(validIsbn), isTrue);
      expect(desk.activeLoanCount, 1);
      expect(desk.loanCountDisplay, '1 loan');
      expect(desk.loanList, 'Effective Dart');
      expect(desk.errorMessage, isEmpty);
    },
    scenario: CheckoutScenarios.checkoutValid,
    evidenceTypes: const ['domain-unit'],
    provedControls: const {isbnValidation},
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(CheckoutScenarios.checkoutValid),
  );

  zukeTest(
    () {
      final desk = openCheckoutDesk();
      expect(desk.checkout(malformedIsbn), isFalse);
      expect(desk.errorMessage, isbnValidationError);
      expect(desk.loanCountDisplay, '0 loans');
      expect(desk.loans, isEmpty);
    },
    scenario: CheckoutScenarios.checkoutBadIsbn,
    evidenceTypes: const ['domain-unit'],
    provedControls: const {isbnValidation},
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(CheckoutScenarios.checkoutBadIsbn),
  );

  zukeTest(
    () {
      final desk = openCheckoutDesk();
      expect(desk.checkout(''), isFalse);
      expect(desk.errorMessage, isbnValidationError);
      expect(desk.loans, isEmpty);
    },
    scenario: CheckoutScenarios.checkoutEmpty,
    evidenceTypes: const ['domain-unit'],
    provedControls: const {isbnValidation},
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(CheckoutScenarios.checkoutEmpty),
  );

  zukeTest(
    () {
      final desk = openCheckoutDesk();
      for (final isbn in loanLimitSeedIsbns) {
        expect(desk.checkout(isbn), isTrue);
      }
      expect(desk.activeLoanCount, CheckoutController.maxActiveLoans);

      expect(desk.checkout(validIsbn), isFalse);
      expect(desk.errorMessage, loanLimitError);
      expect(desk.activeLoanCount, CheckoutController.maxActiveLoans);
      expect(desk.loans.map((loan) => loan.isbn), isNot(contains(validIsbn)));
    },
    scenario: CheckoutScenarios.checkoutLimit,
    evidenceTypes: const ['domain-unit'],
    provedControls: const {isbnValidation},
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(CheckoutScenarios.checkoutLimit),
  );

  zukeTest(
    () {
      final desk = openCheckoutDesk();
      expect(desk.checkout(validIsbn), isTrue);
      expect(desk.returnLoan(validIsbn), isTrue);
      expect(desk.activeLoanCount, 0);
      expect(desk.loanCountDisplay, '0 loans');
      expect(desk.statusMessage, loanReturnedStatus);
      expect(desk.errorMessage, isEmpty);

      expect(desk.returnLoan(validIsbn), isFalse);
      expect(desk.errorMessage, 'No active loan for ISBN');
    },
    scenario: BookReturnScenarios.return_,
    evidenceTypes: const ['domain-unit'],
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(BookReturnScenarios.return_),
  );

  zukeTest(
    () async {
      await withPeerBranches((north, south) async {
        expect(north.isConnected, isTrue);
        expect(south.isConnected, isTrue);
      });
    },
    scenario: BranchPeerScenarios.peerConnect,
    evidenceTypes: const ['domain-unit'],
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(BranchPeerScenarios.peerConnect),
  );

  zukeTest(
    () async {
      await withPeerBranches((north, south) async {
        north.seedLocalLoan(validIsbn);
        await north.shareLoansWith(south);
        expect(south.peerLoans, contains(validIsbn));
      });
    },
    scenario: BranchPeerScenarios.peerSync,
    evidenceTypes: const ['domain-unit'],
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(BranchPeerScenarios.peerSync),
  );

  test('peer loan share can be repeated over the same connection', () async {
    await withPeerBranches((north, south) async {
      north.seedLocalLoan(validIsbn);
      await north.shareLoansWith(south);
      expect(south.peerLoans, contains(validIsbn));
      north.seedLocalLoan(loanLimitSeedIsbns.first);
      await north.shareLoansWith(south);
      expect(
        south.peerLoans,
        containsAll([validIsbn, loanLimitSeedIsbns.first]),
      );
    });
  });
}
