// guide-snippet:controller:start
import 'package:flutter/foundation.dart';
import 'package:shopping_cart/shopping_cart.dart';
import 'package:zuke_annotations/zuke_annotations.dart';

@ImplementsRequirement([
  FeatCart001RequirementIds.promoDiscount,
], target: 'flutter')
@ProvidesControl(
  ['CTRL-PROMO-VALIDATION'],
  kind: ControlProviderKind.applicationValidator,
  layer: EnforcementLayer.presentation,
)
class CartController extends ChangeNotifier {}

// guide-snippet:controller:end
