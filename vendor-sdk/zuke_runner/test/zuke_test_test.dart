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
    // These two registrations demonstrate the concise `zukeTest` syntax, so they
    // deliberately omit `evidenceTypes` -- that is the form being documented.
    // The diagnostic is suppressed rather than satisfied because this file is a
    // plain `dart test` suite: it is never launched by a managed run, so the
    // `ArgumentError` it guards against cannot be reached here. It would fire
    // correctly the moment this file became managed evidence.
    // ignore: zuke/zuke_missing_evidence_types
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
