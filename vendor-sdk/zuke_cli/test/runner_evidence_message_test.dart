import 'package:test/test.dart';
import 'package:zuke_cli/src/test_command.dart';

void main() {
  group('Runner evidence failure messages', () {
    // These strings are the only guidance a user gets when a managed test suite
    // runs green but proves nothing. They once said only what went wrong, not
    // what to do, which is the moment the concept has to land. Pinning the
    // wording here keeps a later edit from quietly dropping the fix.
    test('no artifacts names the required types and the fix', () {
      final message = runnerProducedNoArtifactsMessage('app-tests', {
        'unit',
        'flutter-widget',
      });

      expect(message, contains('app-tests'));
      // Sorted, so the text is stable regardless of set iteration order.
      expect(message, contains('flutter-widget, unit'));
      expect(
        message,
        contains('zukeTest(...)'),
        reason: 'must name the helper that registers managed evidence',
      );
      expect(message, contains('evidenceTypes'));
      expect(
        message,
        contains('test()/testWidgets()'),
        reason: 'must name the construct the user is migrating away from',
      );
    });

    test('no artifacts sorts the types so the text is deterministic', () {
      expect(
        runnerProducedNoArtifactsMessage('r', {'zulu', 'alpha'}),
        runnerProducedNoArtifactsMessage('r', {'alpha', 'zulu'}),
      );
    });

    test('missing types reports observed against expected', () {
      final message = runnerMissingEvidenceTypesMessage(
        'app-tests',
        {'flutter-widget', 'unit'},
        {'domain-unit'},
      );

      expect(message, contains('Missing: flutter-widget, unit'));
      expect(message, contains('Observed: domain-unit'));
    });

    test('missing types says none rather than an empty list', () {
      final message = runnerMissingEvidenceTypesMessage('r', {'unit'}, {});
      expect(message, contains('Observed: (none)'));
    });
  });
}
