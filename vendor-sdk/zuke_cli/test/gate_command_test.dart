import 'dart:io';

import 'package:test/test.dart';
import 'helpers/eligible_workspace.dart';
import 'cli_test_helper.dart';

void main() {
  group('GateCommand', () {
    late Directory root;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('zuke-gate-');
      await createEligibleWorkspace(root);
    });

    tearDown(() {
      if (root.existsSync()) {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('runs gate command on eligible workspace', () async {
      await runInProcessCli(['generate', '--root', root.path]);

      final result = await runInProcessCli([
        'gate',
        '--root',
        root.path,
        '--profile',
        'pullRequest',
      ]);

      expect(result.stdout, contains('Gate [generate-check]:'));
    });

    test('GateCommand emits JSON format envelope when --format json', () async {
      await runInProcessCli(['generate', '--root', root.path]);
      await runInProcessCli(['lock', '--root', root.path]);

      final result = await runInProcessCli([
        'gate',
        '--root',
        root.path,
        '--format',
        'json',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('"schemaVersion":"zuke.command-result.v2"'));
    });

    test(
      'GateCommand returns 1 when trust bundle is missing for release profile',
      () async {
        await runInProcessCli(['generate', '--root', root.path]);

        // Delete trust directory
        final trustDir = Directory('${root.path}/assurance-history/trust');
        if (trustDir.existsSync()) {
          trustDir.deleteSync(recursive: true);
        }

        final result = await runInProcessCli([
          'gate',
          '--root',
          root.path,
          '--profile',
          'release',
        ]);

        expect(result.exitCode, 1);
        expect(
          result.stderr,
          contains('Ed25519 attestation trust bundle is missing'),
        );
      },
    );

    test('expired attestations make the gate ineligible', () async {
      root.deleteSync(recursive: true);
      root = Directory.systemTemp.createTempSync('zuke-gate-expired-');
      final now = DateTime.now().toUtc();
      await createEligibleWorkspace(
        root,
        attestationIssuedAt: now.subtract(const Duration(days: 30)),
        attestationExpiresAt: now.subtract(const Duration(days: 1)),
      );
      await runInProcessCli(['generate', '--root', root.path]);

      final result = await runInProcessCli([
        'gate',
        '--root',
        root.path,
        '--profile',
        'pullRequest',
      ]);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('expired'));
    });
  });
}
