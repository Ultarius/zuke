import 'package:flutter_test/flutter_test.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:zuke/assurance.dart';

import 'vendor_steps.dart';
import 'world.dart';

Future<void> executeGuideScenario(
  ParsedFeature feature,
  ParsedRule rule,
  GherkinScenario scenario,
  ShoppingCartWorld world,
  String profile,
  ZukeScenarioContract contract,
) async {
  // guide-snippet:executor:start
  final executor = ScenarioExecutor<ShoppingCartWorld>(
    registry: registry(),
    evidenceType: 'gherkin-ui',
    target: 'flutter',
    profile: profile,
    candidateId: contract.id,
    controlIds: contract.controlIds.map((control) => control.value).toSet(),
    runnerId: 'my-app-flutter-tests',
    runnerCompatibilityId: 'my-app-flutter-tests-v1',
    digests: const {'runner': 'zuke-runner-flutter-v1'},
  );
  final result = await executor.executeScenario(
    feature,
    rule,
    scenario,
    () => world,
  );
  expect(result.status, ScenarioStatus.passed);

  const writer = ExecutionResultWriter(
    identity: ExecutionSourceIdentity(
      sourcePackage: 'shopping-cart',
      sourceAdapter: 'dart-source',
      sourceCompatibilityId: 'dart-source-package-v1',
    ),
  );
  writer.writeScenarioToEnvironment(result);
  // guide-snippet:executor:end
}
