import 'package:shopping_cart/shopping_cart.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

void registerGuideProfileScenarios(
  ParsedFeature feature,
  void Function(ZukeScenarioContract) registerScenario,
) {
  // guide-snippet:registration:start
  void registerScenarios(Object pattern) {
    for (final resolved in resolveScenarioContracts(
      feature,
      FeatCart001Scenarios.all,
      ZukeScenarioPattern.from(pattern),
    )) {
      registerScenario(resolved.contract);
    }
  }

  // zuke: allow-raw-id -- the guide demonstrates a scoped prefix.
  registerScenarios(ZukeScenarioPattern.prefix('SCN-CART-'));
  // guide-snippet:registration:end
}
