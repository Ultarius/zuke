import 'dart:io';

import 'package:library_catalog/library_catalog.dart';
import 'package:test/test.dart';
import 'package:zuke/zuke.dart';

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

  CheckoutController openDesk() => CheckoutController();

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
      final desk = openDesk();
      expect(desk.checkout('9780134685991'), isTrue);
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
      final desk = openDesk();
      expect(desk.checkout('not-an-isbn'), isFalse);
      expect(desk.errorMessage, 'ISBN must be 10 or 13 digits');
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
      final desk = openDesk();
      expect(desk.checkout(''), isFalse);
      expect(desk.errorMessage, 'ISBN must be 10 or 13 digits');
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
      final desk = openDesk();
      expect(desk.checkout('9780134685991'), isTrue);
      expect(desk.checkout('9780596517748'), isTrue);
      expect(desk.checkout('9780201616224'), isTrue);
      expect(desk.activeLoanCount, CheckoutController.maxActiveLoans);

      expect(desk.checkout('9780143127550'), isFalse);
      expect(desk.errorMessage, 'Active loan limit reached');
      expect(desk.activeLoanCount, CheckoutController.maxActiveLoans);
      expect(
        desk.loans.map((loan) => loan.isbn),
        isNot(contains('9780143127550')),
      );
    },
    scenario: CheckoutScenarios.checkoutLimit,
    evidenceTypes: const ['domain-unit'],
    provedControls: const {isbnValidation},
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(CheckoutScenarios.checkoutLimit),
  );

  zukeTest(
    () {
      final desk = openDesk();
      expect(desk.checkout('9780134685991'), isTrue);
      expect(desk.returnLoan('9780134685991'), isTrue);
      expect(desk.activeLoanCount, 0);
      expect(desk.loanCountDisplay, '0 loans');
      expect(desk.statusMessage, 'Loan returned');
      expect(desk.errorMessage, isEmpty);

      expect(desk.returnLoan('9780134685991'), isFalse);
      expect(desk.errorMessage, 'No active loan for ISBN');
    },
    scenario: BookReturnScenarios.return_,
    evidenceTypes: const ['domain-unit'],
    provedControls: const {isbnValidation},
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(BookReturnScenarios.return_),
  );

  zukeTest(
    () async {
      final north = BranchPeerServer('north');
      final south = BranchPeerServer('south');
      try {
        await north.listen();
        await south.listen();
        await north.connectTo(south);
        expect(north.isConnected, isTrue);
        expect(south.isConnected, isTrue);
      } finally {
        await north.close();
        await south.close();
      }
    },
    scenario: BranchPeerScenarios.peerConnect,
    evidenceTypes: const ['domain-unit'],
    provedControls: const {isbnValidation},
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(BranchPeerScenarios.peerConnect),
  );

  zukeTest(
    () async {
      final north = BranchPeerServer('north');
      final south = BranchPeerServer('south');
      try {
        await north.listen();
        await south.listen();
        await north.connectTo(south);
        north.seedLocalLoan('9780134685991');
        await north.shareLoansWith(south);
        expect(south.peerLoans, contains('9780134685991'));
      } finally {
        await north.close();
        await south.close();
      }
    },
    scenario: BranchPeerScenarios.peerSync,
    evidenceTypes: const ['domain-unit'],
    provedControls: const {isbnValidation},
    provedImplementationSlots: const ['primary'],
    skip: skipScenario(BranchPeerScenarios.peerSync),
  );
}
