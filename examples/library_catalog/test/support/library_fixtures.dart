import 'package:library_catalog/library_catalog.dart';
import 'package:zuke/zuke.dart';

const validIsbn = '9780134685991';
const malformedIsbn = 'not-an-isbn';
const isbnValidationError = 'ISBN must be 10 or 13 digits';
const loanLimitError = 'Active loan limit reached';
const loanReturnedStatus = 'Loan returned';

const loanLimitSeedIsbns = ['9780596517748', '9780201616224', '9780143127550'];

const librarySourceIdentity = ExecutionSourceIdentity(
  sourcePackage: 'library-catalog',
  sourceAdapter: 'dart-source',
  sourceCompatibilityId: 'dart-source-package-v1',
);

CheckoutController openCheckoutDesk() => CheckoutController();

Future<T> withPeerBranches<T>(
  Future<T> Function(BranchPeerServer north, BranchPeerServer south) body,
) async {
  final north = BranchPeerServer('north');
  final south = BranchPeerServer('south');
  try {
    await north.listen();
    await south.listen();
    await north.connectTo(south);
    return await body(north, south);
  } finally {
    await north.close();
    await south.close();
  }
}
