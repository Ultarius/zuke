import 'dart:io';

import 'package:test/test.dart';
import 'helpers/eligible_workspace.dart';
import 'cli_test_helper.dart';

void main() {
  group('ManifestCommand', () {
    late Directory root;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('zuke-manifest-');
      await createEligibleWorkspace(root);
    });

    tearDown(() {
      if (root.existsSync()) {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('manifest export handles empty release history', () async {
      await runInProcessCli(['generate', '--root', root.path]);

      final result = await runInProcessCli([
        'manifest',
        'export',
        '--root',
        root.path,
      ]);

      expect(result.exitCode, 1);
    });

    test('manifest verify-v2 validates history chain', () async {
      await runInProcessCli(['generate', '--root', root.path]);

      final result = await runInProcessCli([
        'manifest',
        'verify-v2',
        '--root',
        root.path,
      ]);

      // Returns 0 when no release records or valid chain
      expect(result.exitCode, 0);
    });

    test('manifest create rejects unknown signer', () async {
      await runInProcessCli(['generate', '--root', root.path]);
      await runInProcessCli(['lock', '--root', root.path]);

      final result = await runInProcessCli([
        'manifest',
        'create',
        '--root',
        root.path,
        '--signer-id',
        'unknown-signer',
      ]);

      expect(result.exitCode, isNonZero);
    });
  });
}
