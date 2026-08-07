import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_cart/shopping_cart.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

// guide-snippet:world:start
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

// guide-snippet:world:end
