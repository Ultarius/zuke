import 'dart:io';

import 'package:test/test.dart';
import 'helpers/eligible_workspace.dart';
import 'cli_test_helper.dart';

void main() {
  group('TraceCommand', () {
    late Directory root;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('zuke-trace-');
      await createEligibleWorkspace(root);
    });

    tearDown(() {
      if (root.existsSync()) {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('returns 1 when no requirement ID is provided', () async {
      final result = await runInProcessCli(['trace', '--root', root.path]);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('Usage: zuke trace RULE-ID'));
    });

    test('returns 1 when an unknown requirement ID is provided', () async {
      final result = await runInProcessCli([
        'trace',
        'UNKNOWN-RULE',
        '--root',
        root.path,
      ]);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('Unknown requirement: UNKNOWN-RULE'));
    });

    test('traces an existing requirement in an eligible workspace', () async {
      await runInProcessCli(['generate', '--root', root.path]);

      final result = await runInProcessCli([
        'trace',
        'RULE-GATEWAY-RATE-LIMIT',
        '--root',
        root.path,
      ]);
      expect(
        result.exitCode,
        1,
      ); // Unproven in fixture -> ineligible status (1)
      expect(result.stdout, contains('RULE-GATEWAY-RATE-LIMIT'));
      expect(result.stdout, contains('Required controls:'));
    });
  });
}
