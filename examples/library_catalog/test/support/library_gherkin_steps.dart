import 'package:library_catalog/library_catalog.dart';
import 'package:zuke/zuke.dart';

import 'generated/feat_library_001_steps.g.dart';
import 'library_fixtures.dart';
import 'library_world.dart';

StepRegistry<LibraryWorld> buildLibraryRegistry() => buildStepRegistry([
  ...const FeatLibrary001GeneratedSteps<LibraryWorld>().build(
    theCheckoutDeskIsOpen: (world) {
      world.controller.reset();
      world.pendingIsbn = '';
    },
    theLoanRegisterIsEmpty: (world) {
      if (world.controller.activeLoanCount != 0) {
        throw StateError(
          'Expected an empty loan register, found '
          '${world.controller.activeLoanCount} loans.',
        );
      }
    },
    theLibrarianEntersISBNInto: (world, isbn, bindingId) {
      if (bindingId != 'library.isbnInput') {
        throw StateError(
          'Expected the ISBN entry binding "library.isbnInput", got '
          '"$bindingId".',
        );
      }
      world.pendingIsbn = isbn;
    },
    theLibrarianTaps: (world, bindingId) {
      if (bindingId != 'library.checkoutButton') {
        throw StateError(
          'Expected the checkout action binding "library.checkoutButton", '
          'got "$bindingId".',
        );
      }
      world.controller.checkout(world.pendingIsbn);
    },
    theLibrarianHas3ActiveLoans: (world) async {
      for (final isbn in loanLimitSeedIsbns) {
        if (!world.controller.checkout(isbn)) {
          throw StateError(
            'Seeding active loan for ISBN $isbn failed: '
            '${world.controller.errorMessage}',
          );
        }
      }
      if (world.controller.activeLoanCount != loanLimitSeedIsbns.length) {
        throw StateError(
          'Expected ${loanLimitSeedIsbns.length} active loans after seeding, '
          'found ${world.controller.activeLoanCount}.',
        );
      }
    },
    theLibrarianHasAnActiveLoanForISBN: (world, isbn) {
      if (!world.controller.checkout(isbn)) {
        throw StateError(
          'Seeding active loan for ISBN $isbn failed: '
          '${world.controller.errorMessage}',
        );
      }
    },
    theLibrarianReturnsTheLoanForISBN: (world, isbn) {
      if (!world.controller.returnLoan(isbn)) {
        throw StateError(
          'Returning loan for ISBN $isbn failed: '
          '${world.controller.errorMessage}',
        );
      }
    },
    branchIsListeningForPeers: (world, branchId) async {
      final server = BranchPeerServer(branchId);
      await server.listen();
      world.branches[branchId] = server;
    },
    branchConnectsToBranch: (world, fromId, toId) async {
      await world.branch(fromId).connectTo(world.branch(toId));
    },
    branchIsConnectedToBranch: (world, fromId, toId) async {
      final from = world.branch(fromId);
      if (from.isConnected) return;
      await from.connectTo(world.branch(toId));
    },
    thePeerConnectionBetweenAndIsEstablished: (world, fromId, toId) {
      final from = world.branch(fromId);
      final to = world.branch(toId);
      if (!from.isConnected || !to.isConnected) {
        throw StateError(
          'Expected peer connection $fromId <-> $toId to be established '
          '(from.connected=${from.isConnected}, '
          'to.connected=${to.isConnected}).',
        );
      }
    },
    branchReportsPeerState: (world, branchId, state) {
      final branch = world.branch(branchId);
      final observed = branch.isConnected ? 'connected' : 'disconnected';
      if (observed != state) {
        throw StateError(
          'Expected branch $branchId peer state "$state", observed '
          '"$observed".',
        );
      }
    },
    branchHasLocalLoanISBN: (world, branchId, isbn) {
      world.branch(branchId).seedLocalLoan(isbn);
    },
    branchSharesItsLoanRegisterWithBranch: (world, fromId, toId) async {
      await world.branch(fromId).shareLoansWith(world.branch(toId));
    },
    branchReceivesLoanISBN: (world, branchId, isbn) {
      final received = world.branch(branchId).peerLoans;
      if (!received.contains(isbn)) {
        throw StateError(
          'Expected branch $branchId to receive loan ISBN $isbn, observed '
          '$received.',
        );
      }
    },
  ),
  StepDefinition.cucumber(
    expression: CucumberExpression(
      'element {string} displays {string}',
      StepParameterTypeRegistry.standard(),
    ),
    tier: StepTier.project,
    target: 'catalog',
    action: (world, step, values) {
      final bindingId = values[0] as String;
      final expected = values[1] as String;
      final observed = world.displayFor(bindingId);
      if (observed != expected) {
        throw StateError(
          'Expected $bindingId to display "$expected", observed '
          '"$observed".',
        );
      }
    },
  ),
]);
