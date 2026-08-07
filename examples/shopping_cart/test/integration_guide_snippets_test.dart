import 'package:flutter_test/flutter_test.dart';

import 'package:shopping_cart/src/shopping_bindings.dart' as bindings;
import 'guide_snippets/executor.dart' as executor;
import 'guide_snippets/profile_filter.dart' as profile_filter;
import 'guide_snippets/registration.dart' as registration;
import 'guide_snippets/vendor_steps.dart' as vendor_steps;
import 'guide_snippets/world.dart' as world;

void main() {
  test('integration-guide snippets compile in the shopping-cart fixture', () {
    expect(bindings.ShoppingBindings, isNotNull);
    expect(world.ShoppingCartWorld, isNotNull);
    expect(vendor_steps.registry, isNotNull);
    expect(executor.executeGuideScenario, isNotNull);
    expect(profile_filter.registerGuideScenario, isNotNull);
    expect(registration.registerGuideProfileScenarios, isNotNull);
  });
}
