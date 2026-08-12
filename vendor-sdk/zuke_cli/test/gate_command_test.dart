import 'dart:io';
import 'dart:convert';

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
      expect(result.stdout, contains('"kind":"zuke.command-result"'));
    });

    test(
      'gate rejects legacy configuration before running later stages',
      () async {
        File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 2
targets: {}
''');

        final result = await runInProcessCli([
          'gate',
          '--root',
          root.path,
          '--profile',
          'pullRequest',
          '--format',
          'json',
        ]);

        expect(result.exitCode, 1);
        final document = jsonDecode(result.stdout) as Map;
        expect(
          (document['diagnostics'] as List).single['code'],
          'ZK-CONFIG-LEGACY-FORMAT',
        );
        final stages = document['stages'] as List;
        expect(stages.first['name'], 'doctor');
        expect(stages.first['status'], 'failed');
        expect(stages[1]['status'], 'skipped');
        expect(
          stages.first['diagnostics'].single['remediation'],
          contains('docs/migration.md'),
        );
      },
    );

    test(
      'JSON gate summary and safe artifact use the canonical document',
      () async {
        await runInProcessCli(['generate', '--root', root.path]);
        await runInProcessCli(['lock', '--root', root.path]);
        final summary = File('${root.path}/gate-summary.json');
        final artifacts = Directory('${root.path}/gate-artifacts');
        final result = await runInProcessCli([
          'gate',
          '--root',
          root.path,
          '--format',
          'json',
          '--summary-file',
          summary.path,
          '--artifact-dir',
          artifacts.path,
        ]);
        expect(result.exitCode, 0);
        final stdoutDocument = jsonDecode(result.stdout) as Map;
        final summaryDocument = jsonDecode(summary.readAsStringSync()) as Map;
        final artifactDocument =
            jsonDecode(
                  File(
                    '${artifacts.path}/command-result.json',
                  ).readAsStringSync(),
                )
                as Map;
        expect(summaryDocument, stdoutDocument);
        expect(artifactDocument, stdoutDocument);
        expect(summary.readAsStringSync(), result.stdout);
        expect(
          File('${artifacts.path}/command-result.json').readAsStringSync(),
          result.stdout,
        );
      },
    );

    test('artifact directory rejects unexpected pre-existing files', () async {
      await runInProcessCli(['generate', '--root', root.path]);
      await runInProcessCli(['lock', '--root', root.path]);
      final artifacts = Directory('${root.path}/unsafe-artifacts')
        ..createSync(recursive: true);
      File('${artifacts.path}/raw.log').writeAsStringSync('unexpected output');

      final result = await runInProcessCli([
        'gate',
        '--root',
        root.path,
        '--format',
        'json',
        '--artifact-dir',
        artifacts.path,
      ]);

      expect(result.exitCode, isNot(0));
      final document = jsonDecode(result.stdout) as Map;
      expect(document['status'], 'failed');
      expect(document['eligible'], isFalse);
      expect(
        (document['diagnostics'] as List).single['code'],
        'ZK-ARTIFACT-UNSAFE',
      );
      expect(File('${artifacts.path}/raw.log').existsSync(), isTrue);
      expect(
        File('${artifacts.path}/command-result.json').existsSync(),
        isFalse,
      );
    });

    test(
      'all-profile artifact safety fails before executing any profile',
      () async {
        final artifacts = Directory('${root.path}/unsafe-all-artifacts')
          ..createSync(recursive: true);
        File(
          '${artifacts.path}/raw.log',
        ).writeAsStringSync('unexpected output');
        final summary = File('${root.path}/unsafe-all-summary.json');

        final result = await runInProcessCli([
          'gate',
          '--root',
          root.path,
          '--all-profiles',
          '--format',
          'json',
          '--summary-file',
          summary.path,
          '--artifact-dir',
          artifacts.path,
        ]);

        expect(result.exitCode, 1);
        final document = jsonDecode(result.stdout) as Map;
        expect(document['status'], 'failed');
        expect(document['eligible'], isFalse);
        expect(
          (document['diagnostics'] as List).single['code'],
          'ZK-ARTIFACT-UNSAFE',
        );
        expect(document['profiles'], isEmpty);
        expect(summary.readAsStringSync(), result.stdout);
        expect(
          File('${artifacts.path}/command-result.json').existsSync(),
          isFalse,
        );
      },
    );

    test('gate rejects profile and all-profile selection together', () async {
      final result = await runInProcessCli([
        'gate',
        '--root',
        root.path,
        '--profile',
        'pullRequest',
        '--all-profiles',
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('mutually exclusive'));
    });

    test(
      'all-profiles returns one canonical result with every profile',
      () async {
        await runInProcessCli(['generate', '--root', root.path]);
        await runInProcessCli(['lock', '--root', root.path, '--all-profiles']);

        final result = await runInProcessCli([
          'gate',
          '--root',
          root.path,
          '--all-profiles',
          '--format',
          'json',
          '--summary-file',
          '${root.path}/gate-summary.json',
        ]);

        expect(result.exitCode, 0);
        final document = jsonDecode(result.stdout) as Map;
        final profiles = document['profiles'] as List;
        expect(profiles.map((profile) => profile['profile']), [
          'pullRequest',
          'merge',
          'release',
          'nightly',
        ]);
        expect(
          File('${root.path}/gate-summary.json').readAsStringSync(),
          result.stdout,
        );
      },
    );

    test(
      'all-profile artifact is byte-identical to stdout and summary',
      () async {
        await runInProcessCli(['generate', '--root', root.path]);
        await runInProcessCli(['lock', '--root', root.path, '--all-profiles']);
        final summary = File('${root.path}/all-gate-summary.json');
        final artifacts = Directory('${root.path}/all-gate-artifacts');
        final result = await runInProcessCli([
          'gate',
          '--root',
          root.path,
          '--all-profiles',
          '--format',
          'json',
          '--summary-file',
          summary.path,
          '--artifact-dir',
          artifacts.path,
        ]);

        expect(result.exitCode, 0);
        expect(summary.readAsStringSync(), result.stdout);
        expect(
          File('${artifacts.path}/command-result.json').readAsStringSync(),
          result.stdout,
        );
      },
    );

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
