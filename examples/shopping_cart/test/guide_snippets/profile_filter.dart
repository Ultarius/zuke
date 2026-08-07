import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

void registerGuideScenario(
  String scenarioId,
  String name,
  Future<void> Function(WidgetTester tester, String scenarioId) runScenario,
  bool Function(String scenarioId, Set<String> selected) shouldRunScenario,
) {
  // guide-snippet:profile-filter:start
  final selectedScenarioIds = scenarioFilterFromEnvironment(
    Platform.environment,
  );

  testWidgets(
    '$scenarioId: $name',
    (tester) => runScenario(tester, scenarioId),
    skip: !shouldRunScenario(scenarioId, selectedScenarioIds),
  );
  // guide-snippet:profile-filter:end
}
