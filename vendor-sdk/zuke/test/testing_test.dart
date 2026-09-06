import 'package:test/test.dart';
import 'package:zuke/zuke.dart';

final class _Scenario implements ZukeScenarioContract {
  const _Scenario();

  @override
  ScenarioId get id => const ScenarioId('SCN-UNIT-HELPER-001');

  @override
  RuleId get requirementId => const RuleId('RULE-UNIT-HELPER-001');

  @override
  String get title => 'unit helper';

  @override
  Set<ControlId> get controlIds => const {};
}

void main() {
  // Registration outside a test body mirrors a consumer test file and also
  // verifies that the helper remains an ordinary Dart test without managed
  // Zuke environment variables.
  zukeUnit(() async {}, scenario: const _Scenario());

  test('zukeUnit is available from the canonical zuke package', () {
    expect(
      defaultZukeDescription(const _Scenario(), null),
      'Zuke SCN-UNIT-HELPER-001: unit helper',
    );
  });
}
