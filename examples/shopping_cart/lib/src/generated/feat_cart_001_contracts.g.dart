// GENERATED. DO NOT EDIT.
// Source: FEAT-CART-001 (specs/features/shopping_cart.feature)

import 'package:zuke_annotations/zuke_annotations.dart';

sealed class FeatCart001FlutterBinding implements ZukeBindingDescriptor {
  const FeatCart001FlutterBinding(this.id);
  @override
  final String id;

  T keyIn<T extends Object>(FeatCart001FlutterBindings<T> bindings);

  static const addToCartHeadphones = FeatCart001AddToCartHeadphonesBinding();
  static const promoInput = FeatCart001PromoInputBinding();
  static const applyPromoButton = FeatCart001ApplyPromoButtonBinding();
  static const checkoutButton = FeatCart001CheckoutButtonBinding();
  static const cartBadge = FeatCart001CartBadgeBinding();
  static const subtotalDisplay = FeatCart001SubtotalDisplayBinding();
  static const discountStatusDisplay =
      FeatCart001DiscountStatusDisplayBinding();
  static const totalDisplay = FeatCart001TotalDisplayBinding();
  static const statusMessageDisplay = FeatCart001StatusMessageDisplayBinding();
  static const catalogItemName = FeatCart001CatalogItemNameBinding();
  static const catalogItemPrice = FeatCart001CatalogItemPriceBinding();

  static FeatCart001FlutterBinding fromId(String bindingId) =>
      switch (bindingId) {
        'shopping.addToCartHeadphones' => addToCartHeadphones,
        'shopping.promoInput' => promoInput,
        'shopping.applyPromoButton' => applyPromoButton,
        'shopping.checkoutButton' => checkoutButton,
        'shopping.cartBadge' => cartBadge,
        'shopping.subtotalDisplay' => subtotalDisplay,
        'shopping.discountStatusDisplay' => discountStatusDisplay,
        'shopping.totalDisplay' => totalDisplay,
        'shopping.statusMessageDisplay' => statusMessageDisplay,
        'shopping.catalogItemName' => catalogItemName,
        'shopping.catalogItemPrice' => catalogItemPrice,
        _ => throw ArgumentError.value(
          bindingId,
          'bindingId',
          'Unknown Flutter binding for FEAT-CART-001',
        ),
      };
}

final class FeatCart001AddToCartHeadphonesBinding
    extends FeatCart001FlutterBinding {
  const FeatCart001AddToCartHeadphonesBinding()
    : super('shopping.addToCartHeadphones');

  @override
  T keyIn<T extends Object>(FeatCart001FlutterBindings<T> bindings) =>
      bindings.addToCartHeadphones;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCart001PromoInputBinding extends FeatCart001FlutterBinding {
  const FeatCart001PromoInputBinding() : super('shopping.promoInput');

  @override
  T keyIn<T extends Object>(FeatCart001FlutterBindings<T> bindings) =>
      bindings.promoInput;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCart001ApplyPromoButtonBinding
    extends FeatCart001FlutterBinding {
  const FeatCart001ApplyPromoButtonBinding()
    : super('shopping.applyPromoButton');

  @override
  T keyIn<T extends Object>(FeatCart001FlutterBindings<T> bindings) =>
      bindings.applyPromoButton;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCart001CheckoutButtonBinding extends FeatCart001FlutterBinding {
  const FeatCart001CheckoutButtonBinding() : super('shopping.checkoutButton');

  @override
  T keyIn<T extends Object>(FeatCart001FlutterBindings<T> bindings) =>
      bindings.checkoutButton;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCart001CartBadgeBinding extends FeatCart001FlutterBinding {
  const FeatCart001CartBadgeBinding() : super('shopping.cartBadge');

  @override
  T keyIn<T extends Object>(FeatCart001FlutterBindings<T> bindings) =>
      bindings.cartBadge;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCart001SubtotalDisplayBinding
    extends FeatCart001FlutterBinding {
  const FeatCart001SubtotalDisplayBinding() : super('shopping.subtotalDisplay');

  @override
  T keyIn<T extends Object>(FeatCart001FlutterBindings<T> bindings) =>
      bindings.subtotalDisplay;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCart001DiscountStatusDisplayBinding
    extends FeatCart001FlutterBinding {
  const FeatCart001DiscountStatusDisplayBinding()
    : super('shopping.discountStatusDisplay');

  @override
  T keyIn<T extends Object>(FeatCart001FlutterBindings<T> bindings) =>
      bindings.discountStatusDisplay;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.zeroOrOne;
}

final class FeatCart001TotalDisplayBinding extends FeatCart001FlutterBinding {
  const FeatCart001TotalDisplayBinding() : super('shopping.totalDisplay');

  @override
  T keyIn<T extends Object>(FeatCart001FlutterBindings<T> bindings) =>
      bindings.totalDisplay;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCart001StatusMessageDisplayBinding
    extends FeatCart001FlutterBinding {
  const FeatCart001StatusMessageDisplayBinding()
    : super('shopping.statusMessageDisplay');

  @override
  T keyIn<T extends Object>(FeatCart001FlutterBindings<T> bindings) =>
      bindings.statusMessageDisplay;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.zeroOrOne;
}

final class FeatCart001CatalogItemNameBinding
    extends FeatCart001FlutterBinding {
  const FeatCart001CatalogItemNameBinding() : super('shopping.catalogItemName');

  @override
  T keyIn<T extends Object>(FeatCart001FlutterBindings<T> bindings) =>
      bindings.catalogItemName;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

final class FeatCart001CatalogItemPriceBinding
    extends FeatCart001FlutterBinding {
  const FeatCart001CatalogItemPriceBinding()
    : super('shopping.catalogItemPrice');

  @override
  T keyIn<T extends Object>(FeatCart001FlutterBindings<T> bindings) =>
      bindings.catalogItemPrice;

  @override
  BindingInstanceCardinality get instanceCardinality =>
      BindingInstanceCardinality.exactlyOne;
}

abstract interface class FeatCart001FlutterBindings<T extends Object> {
  T get addToCartHeadphones;
  T get promoInput;
  T get applyPromoButton;
  T get checkoutButton;
  T get cartBadge;
  T get subtotalDisplay;
  T get discountStatusDisplay;
  T get totalDisplay;
  T get statusMessageDisplay;
  T get catalogItemName;
  T get catalogItemPrice;
}

mixin FeatCart001BindingDrivenFlutterDriver<W, T extends Object>
    implements FeatCart001FlutterDriver<W> {
  FeatCart001FlutterBindings<T> bindingsFor(W world);
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
  Future<void> tapAddToCartHeadphones(W world) =>
      zukeTapBinding(world, bindingsFor(world).addToCartHeadphones);
  @override
  Future<void> enterPromoInput(W world, String value) =>
      zukeEnterBinding(world, bindingsFor(world).promoInput, value);
  @override
  Future<void> tapApplyPromoButton(W world) =>
      zukeTapBinding(world, bindingsFor(world).applyPromoButton);
  @override
  Future<void> tapCheckoutButton(W world) =>
      zukeTapBinding(world, bindingsFor(world).checkoutButton);
  @override
  Future<String?> readCartBadge(W world) =>
      zukeReadBinding(world, bindingsFor(world).cartBadge);
  @override
  Future<String?> readSubtotalDisplay(W world) =>
      zukeReadBinding(world, bindingsFor(world).subtotalDisplay);
  @override
  Future<String?> readDiscountStatusDisplay(W world) =>
      zukeReadBinding(world, bindingsFor(world).discountStatusDisplay);
  @override
  Future<String?> readTotalDisplay(W world) =>
      zukeReadBinding(world, bindingsFor(world).totalDisplay);
  @override
  Future<String?> readStatusMessageDisplay(W world) =>
      zukeReadBinding(world, bindingsFor(world).statusMessageDisplay);
  @override
  Future<String?> readCatalogItemName(W world) =>
      zukeReadBinding(world, bindingsFor(world).catalogItemName);
  @override
  Future<String?> readCatalogItemPrice(W world) =>
      zukeReadBinding(world, bindingsFor(world).catalogItemPrice);
}

abstract interface class FeatCart001FlutterDriver<W> {
  Future<void> tapAddToCartHeadphones(W world);
  Future<void> enterPromoInput(W world, String value);
  Future<void> tapApplyPromoButton(W world);
  Future<void> tapCheckoutButton(W world);
  Future<String?> readCartBadge(W world);
  Future<String?> readSubtotalDisplay(W world);
  Future<String?> readDiscountStatusDisplay(W world);
  Future<String?> readTotalDisplay(W world);
  Future<String?> readStatusMessageDisplay(W world);
  Future<String?> readCatalogItemName(W world);
  Future<String?> readCatalogItemPrice(W world);
}

abstract final class FeatCart001RequirementIds {
  static const itemManagement = 'RULE-CART-ITEM-MANAGEMENT';
  static const promoDiscount = 'RULE-CART-PROMO-DISCOUNT';
  static const emptyCheckout = 'RULE-CART-EMPTY-CHECKOUT';
  static const successfulCheckout = 'RULE-CART-SUCCESSFUL-CHECKOUT';
  static const accessibility = 'RULE-CART-ACCESSIBILITY';
}

enum FeatCart001Scenario implements ZukeScenarioContract {
  addItem(
    ScenarioId('SCN-CART-ADD-ITEM'),
    'RULE-CART-ITEM-MANAGEMENT',
    'Add item to cart and verify updated subtotal',
    <String>{'CTRL-CART-VALIDATION'},
  ),
  addSecondItem(
    ScenarioId('SCN-CART-ADD-SECOND-ITEM'),
    'RULE-CART-ITEM-MANAGEMENT',
    'Add same item twice and verify updated quantity and subtotal',
    <String>{'CTRL-CART-VALIDATION'},
  ),
  applyPromo(
    ScenarioId('SCN-CART-APPLY-PROMO'),
    'RULE-CART-PROMO-DISCOUNT',
    'Apply valid discount code and recalculate grand total',
    <String>{'CTRL-PROMO-VALIDATION'},
  ),
  invalidPromo(
    ScenarioId('SCN-CART-INVALID-PROMO'),
    'RULE-CART-PROMO-DISCOUNT',
    'Reject an invalid promo code',
    <String>{'CTRL-PROMO-VALIDATION'},
  ),
  promoEmptyCart(
    ScenarioId('SCN-CART-PROMO-EMPTY-CART'),
    'RULE-CART-PROMO-DISCOUNT',
    'Reject promo code on empty cart',
    <String>{'CTRL-PROMO-VALIDATION'},
  ),
  emptyPromo(
    ScenarioId('SCN-CART-EMPTY-PROMO'),
    'RULE-CART-PROMO-DISCOUNT',
    'Reject submitting an empty promo code',
    <String>{'CTRL-PROMO-VALIDATION'},
  ),
  emptyCheckout(
    ScenarioId('SCN-CART-EMPTY-CHECKOUT'),
    'RULE-CART-EMPTY-CHECKOUT',
    'Prevent checkout when the cart is empty',
    <String>{'CTRL-CART-VALIDATION'},
  ),
  successCheckout(
    ScenarioId('SCN-CART-SUCCESS-CHECKOUT'),
    'RULE-CART-SUCCESSFUL-CHECKOUT',
    'Successfully place order with items in cart and reset promo state',
    <String>{'CTRL-CART-VALIDATION'},
  ),
  accessible(
    ScenarioId('SCN-CART-ACCESSIBLE'),
    'RULE-CART-ACCESSIBILITY',
    'Expose total order summary via semantics handle',
    <String>{'CTRL-CART-ACCESSIBLE'},
  );

  const FeatCart001Scenario(
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

abstract final class FeatCart001Scenarios {
  static const all = FeatCart001Scenario.values;
  static final Map<ScenarioId, FeatCart001Scenario>
  byId = Map.unmodifiable(<ScenarioId, FeatCart001Scenario>{
    ScenarioId('SCN-CART-ADD-ITEM'): FeatCart001Scenario.addItem,
    ScenarioId('SCN-CART-ADD-SECOND-ITEM'): FeatCart001Scenario.addSecondItem,
    ScenarioId('SCN-CART-APPLY-PROMO'): FeatCart001Scenario.applyPromo,
    ScenarioId('SCN-CART-INVALID-PROMO'): FeatCart001Scenario.invalidPromo,
    ScenarioId('SCN-CART-PROMO-EMPTY-CART'): FeatCart001Scenario.promoEmptyCart,
    ScenarioId('SCN-CART-EMPTY-PROMO'): FeatCart001Scenario.emptyPromo,
    ScenarioId('SCN-CART-EMPTY-CHECKOUT'): FeatCart001Scenario.emptyCheckout,
    ScenarioId('SCN-CART-SUCCESS-CHECKOUT'):
        FeatCart001Scenario.successCheckout,
    ScenarioId('SCN-CART-ACCESSIBLE'): FeatCart001Scenario.accessible,
  });
  static final Map<String, List<FeatCart001Scenario>> byRule = Map.unmodifiable(
    <String, List<FeatCart001Scenario>>{
      'RULE-CART-ITEM-MANAGEMENT': List.unmodifiable(<FeatCart001Scenario>[
        FeatCart001Scenario.addItem,
        FeatCart001Scenario.addSecondItem,
      ]),
      'RULE-CART-PROMO-DISCOUNT': List.unmodifiable(<FeatCart001Scenario>[
        FeatCart001Scenario.applyPromo,
        FeatCart001Scenario.invalidPromo,
        FeatCart001Scenario.promoEmptyCart,
        FeatCart001Scenario.emptyPromo,
      ]),
      'RULE-CART-EMPTY-CHECKOUT': List.unmodifiable(<FeatCart001Scenario>[
        FeatCart001Scenario.emptyCheckout,
      ]),
      'RULE-CART-SUCCESSFUL-CHECKOUT': List.unmodifiable(<FeatCart001Scenario>[
        FeatCart001Scenario.successCheckout,
      ]),
      'RULE-CART-ACCESSIBILITY': List.unmodifiable(<FeatCart001Scenario>[
        FeatCart001Scenario.accessible,
      ]),
    },
  );
  static List<FeatCart001Scenario> matching(ZukeScenarioPattern pattern) =>
      all.where(pattern.matches).toList(growable: false);
}

abstract final class ItemManagementScenarios {
  static const addItem = FeatCart001Scenario.addItem;
  static const addSecondItem = FeatCart001Scenario.addSecondItem;
  static const all = <ZukeScenarioContract>[
    FeatCart001Scenario.addItem,
    FeatCart001Scenario.addSecondItem,
  ];
}

abstract final class PromoDiscountScenarios {
  static const applyPromo = FeatCart001Scenario.applyPromo;
  static const invalidPromo = FeatCart001Scenario.invalidPromo;
  static const promoEmptyCart = FeatCart001Scenario.promoEmptyCart;
  static const emptyPromo = FeatCart001Scenario.emptyPromo;
  static const all = <ZukeScenarioContract>[
    FeatCart001Scenario.applyPromo,
    FeatCart001Scenario.invalidPromo,
    FeatCart001Scenario.promoEmptyCart,
    FeatCart001Scenario.emptyPromo,
  ];
}

abstract final class EmptyCheckoutScenarios {
  static const emptyCheckout = FeatCart001Scenario.emptyCheckout;
  static const all = <ZukeScenarioContract>[FeatCart001Scenario.emptyCheckout];
}

abstract final class SuccessfulCheckoutScenarios {
  static const successCheckout = FeatCart001Scenario.successCheckout;
  static const all = <ZukeScenarioContract>[
    FeatCart001Scenario.successCheckout,
  ];
}

abstract final class AccessibilityScenarios {
  static const accessible = FeatCart001Scenario.accessible;
  static const all = <ZukeScenarioContract>[FeatCart001Scenario.accessible];
}
