import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_cart/shopping_cart.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

void main() {
  test('an absent Zuke filter keeps every scenario runnable', () {
    final selected = scenarioFilterFromEnvironment(const {});

    expect(selected, isEmpty);
    expect(
      shouldRunScenario(ItemManagementScenarios.addItem.id.value, selected),
      isTrue,
    );
  });

  test('a Zuke filter allow-lists only stable scenario IDs', () {
    final selected = scenarioFilterFromEnvironment({
      'ZUKE_SCENARIO_FILTER':
          '${ItemManagementScenarios.addItem.id.value},${EmptyCheckoutScenarios.emptyCheckout.id.value},',
    });

    expect(
      shouldRunScenario(ItemManagementScenarios.addItem.id.value, selected),
      isTrue,
    );
    expect(
      shouldRunScenario(
        EmptyCheckoutScenarios.emptyCheckout.id.value,
        selected,
      ),
      isTrue,
    );
    expect(
      shouldRunScenario(PromoDiscountScenarios.invalidPromo.id.value, selected),
      isFalse,
    );
  });
}
