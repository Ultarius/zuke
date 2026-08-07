import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_cart/shopping_cart.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

class ShoppingCartWorld extends ScenarioWorld {
  final WidgetTester tester;
  final CartController controller;
  final ShoppingBindings bindings;

  ShoppingCartWorld({
    required this.tester,
    required this.controller,
    required this.bindings,
  });
}

/// Project-owned implementation of the generated, interaction-aware driver.
class ShoppingCartFlutterDriver
    extends BindingDrivenFlutterScenarioDriver<ShoppingCartWorld, Key>
    with FeatCart001BindingDrivenFlutterDriver<ShoppingCartWorld, Key> {
  const ShoppingCartFlutterDriver();

  @override
  WidgetTester testerFor(ShoppingCartWorld world) => world.tester;

  @override
  FeatCart001FlutterBindings<Key> bindingsFor(ShoppingCartWorld world) =>
      world.bindings;

  @override
  Widget buildRoot(ShoppingCartWorld world) =>
      ShoppingScreen(controller: world.controller, bindings: world.bindings);
}
