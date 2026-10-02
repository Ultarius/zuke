import 'package:zuke_annotations/zuke_annotations.dart';

class LoanRecord {
  final String isbn;
  final String title;
  const LoanRecord({required this.isbn, required this.title});
}

/// Implements the checkout/return rules declared in
/// `specs/features/library_catalog.feature`.
@ImplementsRequirement(['RULE-LIBRARY-CHECKOUT', 'RULE-LIBRARY-BOOK-RETURN'])
@ProvidesControl(
  ['CTRL-LIBRARY-ISBN-VALIDATION'],
  kind: ControlProviderKind.applicationValidator,
  layer: EnforcementLayer.presentation,
)
class CheckoutController {
  static const int maxActiveLoans = 3;
  static const Map<String, String> catalogByIsbn = {
    '9780134685991': 'Effective Dart',
    '9780596517748': 'JavaScript: The Good Parts',
    '9780201616224': 'The Pragmatic Programmer',
    '9780143127550': 'On Writing Well',
  };

  final List<LoanRecord> _loans = [];
  String _errorMessage = '';
  String _statusMessage = '';

  List<LoanRecord> get loans => List.unmodifiable(_loans);
  int get activeLoanCount => _loans.length;
  String get errorMessage => _errorMessage;
  String get statusMessage => _statusMessage;
  String get loanCountDisplay => switch (activeLoanCount) {
    0 => '0 loans',
    1 => '1 loan',
    _ => '$activeLoanCount loans',
  };
  String get loanList => _loans.map((loan) => loan.title).join('\n');

  bool checkout(String rawIsbn) {
    _errorMessage = '';
    _statusMessage = '';
    final isbn = rawIsbn.trim();
    if (!_isValidIsbn(isbn)) {
      _errorMessage = 'ISBN must be 10 or 13 digits';
      return false;
    }
    if (_loans.any((loan) => loan.isbn == isbn)) {
      _errorMessage = 'Book already on loan';
      return false;
    }
    if (_loans.length >= maxActiveLoans) {
      _errorMessage = 'Active loan limit reached';
      return false;
    }
    final title = catalogByIsbn[isbn];
    if (title == null) {
      _errorMessage = 'ISBN not found in catalog';
      return false;
    }
    _loans.add(LoanRecord(isbn: isbn, title: title));
    _statusMessage = 'Checked out $title';
    return true;
  }

  bool returnLoan(String rawIsbn) {
    _errorMessage = '';
    _statusMessage = '';
    final isbn = rawIsbn.trim();
    final index = _loans.indexWhere((loan) => loan.isbn == isbn);
    if (index < 0) {
      _errorMessage = 'No active loan for ISBN';
      return false;
    }
    _loans.removeAt(index);
    _statusMessage = 'Loan returned';
    return true;
  }

  void reset() {
    _loans.clear();
    _errorMessage = '';
    _statusMessage = '';
  }

  static bool _isValidIsbn(String isbn) =>
      RegExp(r'^\d{9}[\dXx]$').hasMatch(isbn) ||
      RegExp(r'^\d{13}$').hasMatch(isbn);
}
