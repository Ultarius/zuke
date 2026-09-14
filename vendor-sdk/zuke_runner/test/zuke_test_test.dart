import 'package:test/test.dart';
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_runner/zuke_runner.dart';

final class _SampleScenario implements ZukeScenarioContract {
  const _SampleScenario({
    required this.id,
    required this.requirementId,
    required this.title,
  });

  @override
  final ScenarioId id;

  @override
  final RuleId requirementId;

  @override
  final String title;

  @override
  final Set<ControlId> controlIds = const {};
}

void main() {
  const scenario = _SampleScenario(
    id: ScenarioId('SCN-DEMO-001'),
    requirementId: RuleId('RULE-DEMO-001'),
    title: 'Demonstrates concise zukeTest syntax',
  );

  group('defaultZukeDescription', () {
    test('formats without caseId', () {
      expect(
        defaultZukeDescription(scenario, null),
        'Zuke SCN-DEMO-001: Demonstrates concise zukeTest syntax',
      );
    });

    test('formats with matching caseId (omits redundant case suffix)', () {
      expect(
        defaultZukeDescription(scenario, 'SCN-DEMO-001'),
        'Zuke SCN-DEMO-001: Demonstrates concise zukeTest syntax',
      );
    });

    test('formats with distinct caseId', () {
      expect(
        defaultZukeDescription(scenario, 'primary'),
        'Zuke SCN-DEMO-001 (primary): Demonstrates concise zukeTest syntax',
      );
    });
  });

  group('zukeTest', () {
    zukeTest(
      () async {
        expect(1 + 1, equals(2));
      },
      scenario: scenario,
      caseId: 'concise',
    );

    zukeTest(
      () async {
        expect('hello', startsWith('h'));
      },
      scenario: scenario,
      description: 'Custom description for explicit naming',
      caseId: 'explicit-description',
    );
  });
}
