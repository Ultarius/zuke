// guide-snippet:bindings:start
import 'package:flutter/foundation.dart';
import 'package:zuke_annotations/zuke_annotations.dart';
import 'generated/feat_cart_001_contracts.g.dart';

class ShoppingBindings implements FeatCart001FlutterBindings<Key> {
  @override
  @ZukeBinding('shopping.addToCartHeadphones')
  Key get addToCartHeadphones => const Key('shopping.addToCartHeadphones');

  @override
  @ZukeBinding('shopping.promoInput')
  Key get promoInput => const Key('shopping.promoInput');

  @override
  @ZukeBinding('shopping.applyPromoButton')
  Key get applyPromoButton => const Key('shopping.applyPromoButton');

  @override
  @ZukeBinding('shopping.checkoutButton')
  Key get checkoutButton => const Key('shopping.checkoutButton');

  @override
  @ZukeBinding('shopping.cartBadge')
  Key get cartBadge => const Key('shopping.cartBadge');

  @override
  @ZukeBinding('shopping.subtotalDisplay')
  Key get subtotalDisplay => const Key('shopping.subtotalDisplay');

  @override
  @ZukeBinding('shopping.discountStatusDisplay')
  Key get discountStatusDisplay => const Key('shopping.discountStatusDisplay');

  @override
  @ZukeBinding('shopping.totalDisplay')
  Key get totalDisplay => const Key('shopping.totalDisplay');

  @override
  @ZukeBinding('shopping.statusMessageDisplay')
  Key get statusMessageDisplay => const Key('shopping.statusMessageDisplay');

  @override
  @ZukeBinding('shopping.catalogItemName')
  Key get catalogItemName => const Key('shopping.catalogItemName');

  @override
  @ZukeBinding('shopping.catalogItemPrice')
  Key get catalogItemPrice => const Key('shopping.catalogItemPrice');
}

// guide-snippet:bindings:end
