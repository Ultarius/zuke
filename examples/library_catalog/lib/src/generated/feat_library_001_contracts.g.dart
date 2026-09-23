// GENERATED. DO NOT EDIT.
// Source: FEAT-LIBRARY-001 (specs/features/library_catalog.feature)

import 'package:zuke_annotations/zuke_annotations.dart';

sealed class FeatLibrary001FlutterBinding implements ZukeBindingDescriptor {
  const FeatLibrary001FlutterBinding(this.id);
  @override
  final String id;

  T keyIn<T extends Object>(FeatLibrary001FlutterBindings<T> bindings);

  static const isbnInput = FeatLibrary001IsbnInputBinding();
  static const checkoutButton = FeatLibrary001CheckoutButtonBinding();
  static const loanList = FeatLibrary001LoanListBinding();
  static const loanCountDisplay = FeatLibrary001LoanCountDisplayBinding();
  static const errorMessage = FeatLibrary001ErrorMessageBinding();
  static const statusMessage = FeatLibrary001StatusMessageBinding();

  static FeatLibrary001FlutterBinding fromId(String bindingId) =>
      switch (bindingId) {
        'library.isbnInput' => isbnInput,
        'library.checkoutButton' => checkoutButton,
        'library.loanList' => loanList,
        'library.loanCountDisplay' => loanCountDisplay,
        'library.errorMessage' => errorMessage,
        'library.statusMessage' => statusMessage,
        _ => throw ArgumentError.value(
          bindingId,
          'bindingId',
          'Unknown Flutter binding for FEAT-LIBRARY-001',
        ),
      };
}

final class FeatLibrary001IsbnInputBinding
    extends FeatLibrary001FlutterBinding {
  const FeatLibrary001IsbnInputBinding() : super('library.isbnInput');

  @override
  T keyIn<T extends Object>(FeatLibrary001FlutterBindings<T> bindings) =>
      bindings.isbnInput;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatLibrary001CheckoutButtonBinding
    extends FeatLibrary001FlutterBinding {
  const FeatLibrary001CheckoutButtonBinding() : super('library.checkoutButton');

  @override
  T keyIn<T extends Object>(FeatLibrary001FlutterBindings<T> bindings) =>
      bindings.checkoutButton;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatLibrary001LoanListBinding extends FeatLibrary001FlutterBinding {
  const FeatLibrary001LoanListBinding() : super('library.loanList');

  @override
  T keyIn<T extends Object>(FeatLibrary001FlutterBindings<T> bindings) =>
      bindings.loanList;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatLibrary001LoanCountDisplayBinding
    extends FeatLibrary001FlutterBinding {
  const FeatLibrary001LoanCountDisplayBinding()
    : super('library.loanCountDisplay');

  @override
  T keyIn<T extends Object>(FeatLibrary001FlutterBindings<T> bindings) =>
      bindings.loanCountDisplay;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatLibrary001ErrorMessageBinding
    extends FeatLibrary001FlutterBinding {
  const FeatLibrary001ErrorMessageBinding() : super('library.errorMessage');

  @override
  T keyIn<T extends Object>(FeatLibrary001FlutterBindings<T> bindings) =>
      bindings.errorMessage;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.zeroOrOne;
}

final class FeatLibrary001StatusMessageBinding
    extends FeatLibrary001FlutterBinding {
  const FeatLibrary001StatusMessageBinding() : super('library.statusMessage');

  @override
  T keyIn<T extends Object>(FeatLibrary001FlutterBindings<T> bindings) =>
      bindings.statusMessage;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.zeroOrOne;
}

abstract interface class FeatLibrary001FlutterBindings<T extends Object> {
  T get isbnInput;
  T get checkoutButton;
  T get loanList;
  T get loanCountDisplay;
  T get errorMessage;
  T get statusMessage;
}

mixin FeatLibrary001BindingDrivenFlutterDriver<W, T extends Object>
    implements FeatLibrary001FlutterDriver<W> {
  FeatLibrary001FlutterBindings<T> bindingsFor(W world);
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
  Future<void> enterIsbnInput(W world, String value) =>
      zukeEnterBinding(world, bindingsFor(world).isbnInput, value);
  @override
  Future<void> tapCheckoutButton(W world) =>
      zukeTapBinding(world, bindingsFor(world).checkoutButton);
  @override
  Future<String?> readLoanList(W world) =>
      zukeReadBinding(world, bindingsFor(world).loanList);
  @override
  Future<String?> readLoanCountDisplay(W world) =>
      zukeReadBinding(world, bindingsFor(world).loanCountDisplay);
  @override
  Future<String?> readErrorMessage(W world) =>
      zukeReadBinding(world, bindingsFor(world).errorMessage);
  @override
  Future<String?> readStatusMessage(W world) =>
      zukeReadBinding(world, bindingsFor(world).statusMessage);
}

abstract interface class FeatLibrary001FlutterDriver<W> {
  Future<void> enterIsbnInput(W world, String value);
  Future<void> tapCheckoutButton(W world);
  Future<String?> readLoanList(W world);
  Future<String?> readLoanCountDisplay(W world);
  Future<String?> readErrorMessage(W world);
  Future<String?> readStatusMessage(W world);
}

abstract final class FeatLibrary001RequirementIds {
  static const checkout = 'RULE-LIBRARY-CHECKOUT';
  static const checkoutId = RuleId('RULE-LIBRARY-CHECKOUT');
  static const bookReturn = 'RULE-LIBRARY-BOOK-RETURN';
  static const bookReturnId = RuleId('RULE-LIBRARY-BOOK-RETURN');
  static const branchPeer = 'RULE-LIBRARY-BRANCH-PEER';
  static const branchPeerId = RuleId('RULE-LIBRARY-BRANCH-PEER');
}

abstract final class FeatLibrary001ControlIds {
  static const isbnValidation = ControlId('CTRL-LIBRARY-ISBN-VALIDATION');
}

enum FeatLibrary001Scenario implements ZukeScenarioContract {
  checkoutValid(
    ScenarioId('SCN-LIBRARY-CHECKOUT-VALID'),
    RuleId('RULE-LIBRARY-CHECKOUT'),
    'Check out a book with a valid ISBN',
    <ControlId>{ControlId('CTRL-LIBRARY-ISBN-VALIDATION')},
  ),
  checkoutBadIsbn(
    ScenarioId('SCN-LIBRARY-CHECKOUT-BAD-ISBN'),
    RuleId('RULE-LIBRARY-CHECKOUT'),
    'Reject a malformed ISBN',
    <ControlId>{ControlId('CTRL-LIBRARY-ISBN-VALIDATION')},
  ),
  checkoutEmpty(
    ScenarioId('SCN-LIBRARY-CHECKOUT-EMPTY'),
    RuleId('RULE-LIBRARY-CHECKOUT'),
    'Reject an empty ISBN',
    <ControlId>{ControlId('CTRL-LIBRARY-ISBN-VALIDATION')},
  ),
  checkoutLimit(
    ScenarioId('SCN-LIBRARY-CHECKOUT-LIMIT'),
    RuleId('RULE-LIBRARY-CHECKOUT'),
    'Reject checkout beyond the active loan limit',
    <ControlId>{ControlId('CTRL-LIBRARY-ISBN-VALIDATION')},
  ),
  return_(
    ScenarioId('SCN-LIBRARY-RETURN'),
    RuleId('RULE-LIBRARY-BOOK-RETURN'),
    'Return a checked-out book',
    <ControlId>{ControlId('CTRL-LIBRARY-ISBN-VALIDATION')},
  ),
  peerConnect(
    ScenarioId('SCN-LIBRARY-PEER-CONNECT'),
    RuleId('RULE-LIBRARY-BRANCH-PEER'),
    'Two branches establish a peer connection',
    <ControlId>{ControlId('CTRL-LIBRARY-ISBN-VALIDATION')},
  ),
  peerSync(
    ScenarioId('SCN-LIBRARY-PEER-SYNC'),
    RuleId('RULE-LIBRARY-BRANCH-PEER'),
    'Share active loans across a peer connection',
    <ControlId>{ControlId('CTRL-LIBRARY-ISBN-VALIDATION')},
  );

  const FeatLibrary001Scenario(
    this.id,
    this.requirementId,
    this.title,
    this.controlIds,
  );
  @override
  final ScenarioId id;
  @override
  final RuleId requirementId;
  @override
  final String title;
  @override
  final Set<ControlId> controlIds;
}

abstract final class FeatLibrary001Scenarios {
  static const all = FeatLibrary001Scenario.values;
  static final Map<ScenarioId, FeatLibrary001Scenario> byId =
      Map.unmodifiable(<ScenarioId, FeatLibrary001Scenario>{
        ScenarioId('SCN-LIBRARY-CHECKOUT-VALID'):
            FeatLibrary001Scenario.checkoutValid,
        ScenarioId('SCN-LIBRARY-CHECKOUT-BAD-ISBN'):
            FeatLibrary001Scenario.checkoutBadIsbn,
        ScenarioId('SCN-LIBRARY-CHECKOUT-EMPTY'):
            FeatLibrary001Scenario.checkoutEmpty,
        ScenarioId('SCN-LIBRARY-CHECKOUT-LIMIT'):
            FeatLibrary001Scenario.checkoutLimit,
        ScenarioId('SCN-LIBRARY-RETURN'): FeatLibrary001Scenario.return_,
        ScenarioId('SCN-LIBRARY-PEER-CONNECT'):
            FeatLibrary001Scenario.peerConnect,
        ScenarioId('SCN-LIBRARY-PEER-SYNC'): FeatLibrary001Scenario.peerSync,
      });
  static final Map<String, List<FeatLibrary001Scenario>> byRule =
      Map.unmodifiable(<String, List<FeatLibrary001Scenario>>{
        'RULE-LIBRARY-CHECKOUT': List.unmodifiable(<FeatLibrary001Scenario>[
          FeatLibrary001Scenario.checkoutValid,
          FeatLibrary001Scenario.checkoutBadIsbn,
          FeatLibrary001Scenario.checkoutEmpty,
          FeatLibrary001Scenario.checkoutLimit,
        ]),
        'RULE-LIBRARY-BOOK-RETURN': List.unmodifiable(<FeatLibrary001Scenario>[
          FeatLibrary001Scenario.return_,
        ]),
        'RULE-LIBRARY-BRANCH-PEER': List.unmodifiable(<FeatLibrary001Scenario>[
          FeatLibrary001Scenario.peerConnect,
          FeatLibrary001Scenario.peerSync,
        ]),
      });
  static List<FeatLibrary001Scenario> matching(ZukeScenarioPattern pattern) =>
      all.where(pattern.matches).toList(growable: false);
}

abstract final class CheckoutScenarios {
  static const checkoutValid = FeatLibrary001Scenario.checkoutValid;
  static const checkoutBadIsbn = FeatLibrary001Scenario.checkoutBadIsbn;
  static const checkoutEmpty = FeatLibrary001Scenario.checkoutEmpty;
  static const checkoutLimit = FeatLibrary001Scenario.checkoutLimit;
  static const all = <ZukeScenarioContract>[
    FeatLibrary001Scenario.checkoutValid,
    FeatLibrary001Scenario.checkoutBadIsbn,
    FeatLibrary001Scenario.checkoutEmpty,
    FeatLibrary001Scenario.checkoutLimit,
  ];
}

abstract final class BookReturnScenarios {
  static const return_ = FeatLibrary001Scenario.return_;
  static const all = <ZukeScenarioContract>[FeatLibrary001Scenario.return_];
}

abstract final class BranchPeerScenarios {
  static const peerConnect = FeatLibrary001Scenario.peerConnect;
  static const peerSync = FeatLibrary001Scenario.peerSync;
  static const all = <ZukeScenarioContract>[
    FeatLibrary001Scenario.peerConnect,
    FeatLibrary001Scenario.peerSync,
  ];
}
