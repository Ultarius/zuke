import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

void main() {
  zukeTestWidgets(
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Text('widget lifecycle')),
      );
      expect(find.text('widget lifecycle'), findsOneWidget);
    },
    description: 'registers an ordinary widget test through the managed API',
    scenario: const _WidgetScenario(),
    evidenceTypes: const ['flutter-widget'],
  );
}

final class _WidgetScenario implements ZukeScenarioContract {
  const _WidgetScenario();

  @override
  final ScenarioId id = const ScenarioId('SCN-RUNNER-WIDGET-001');

  @override
  final RuleId requirementId = const RuleId('RULE-RUNNER-WIDGET-001');

  @override
  final String title =
      'Registers an ordinary widget test through the managed API';

  @override
  Set<ControlId> get controlIds => const {};
}
