import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_cart/main.dart' as app;
import 'package:shopping_cart/shopping_cart.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

import 'support/shopping_cart_flutter_driver.dart';
import 'support/generated/feat_cart_001_steps.g.dart';

void main() {
  final feature = ZukeFeatureLoader.load('shopping_cart.feature');

  StepRegistry<ShoppingCartWorld> registry() {
    final driver = const ShoppingCartFlutterDriver();
    return buildStepRegistry([
      ...const FeatCart001GeneratedSteps<ShoppingCartWorld>().build(
        theShoppingApplicationIsOpen: driver.open,
        theCatalogItemIsListedAtPrice: (world, item, price) async {
          expect(await driver.readCatalogItemName(world), item);
          expect(await driver.readCatalogItemPrice(world), price);
        },
        theCartContainsItemAtPrice: (world, item, price) async {
          final suppliedPrice = double.parse(
            price.replaceAll(RegExp(r'[^0-9.]'), ''),
          );
          expect(suppliedPrice, greaterThan(0));
          expect(
            world.controller.addItem('headphone-1', item, suppliedPrice),
            isTrue,
          );
          await driver.pumpAndSettle(world);
        },
        theCartIsCompletelyEmpty: (world) async {
          world.controller.clear();
          await driver.pumpAndSettle(world);
        },
        theCheckoutButtonStateMustBeDisabled: (world) async {
          final button = world.tester.widget<ElevatedButton>(
            find.byKey(world.bindings.checkoutButton),
          );
          expect(button.onPressed, isNull);
        },
        theUserViewsTheCheckoutSummary: driver.captureSemantics,
        theSemanticsTreeMustContainLabelMatching: (world, label) async {
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape(label))),
            findsOneWidget,
          );
        },
      ),
      ...flutterVendorSteps<ShoppingCartWorld, FeatCart001FlutterBinding>(
        testerFor: (world) => world.tester,
        bindingFromId: FeatCart001FlutterBinding.fromId,
        keyFor: (world, binding) => binding.keyIn(world.bindings),
      ),
    ]);
  }

  ZukeFlutterHarness<ShoppingCartWorld>(
    feature: feature,
    scenarios: FeatCart001Scenarios.all,
    registryFactory: registry,
    worldFactory: (tester) => ShoppingCartWorld(
      tester: tester,
      controller: CartController(),
      bindings: ShoppingBindings(),
    ),
    runnerId: 'shopping-flutter-tests',
    runnerCompatibilityId: 'shopping-cart-flutter-runner-v1',
    digests: const {'runner': 'zuke-runner-flutter-v1'},
  ).registerAll();

  testWidgets('main launches application root', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingScreen), findsOneWidget);
  });
}
