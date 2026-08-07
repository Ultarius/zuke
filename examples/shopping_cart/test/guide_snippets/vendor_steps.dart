import 'package:shopping_cart/shopping_cart.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

import 'world.dart';

StepRegistry<ShoppingCartWorld> registry() {
  final registry = StepRegistry<ShoppingCartWorld>();
  // guide-snippet:vendor-steps:start
  for (final step
      in flutterVendorSteps<ShoppingCartWorld, FeatCart001FlutterBinding>(
        testerFor: (world) => world.tester,
        bindingFromId: FeatCart001FlutterBinding.fromId,
        keyFor: (world, binding) => binding.keyIn(world.bindings),
      )) {
    registry.register(step);
  }
  // guide-snippet:vendor-steps:end
  return registry;
}
