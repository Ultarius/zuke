import 'dart:io';

import 'package:test/test.dart';
import 'helpers/eligible_workspace.dart';
import 'cli_test_helper.dart';

void main() {
  group('ValidateCommand', () {
    late Directory root;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('zuke-validate-');
      await createEligibleWorkspace(root);
    });

    tearDown(() {
      if (root.existsSync()) {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test(
      'validates workspace and outputs json when --json is passed',
      () async {
        await runInProcessCli(['generate', '--root', root.path]);

        final result = await runInProcessCli([
          'validate',
          '--root',
          root.path,
          '--profile',
          'pullRequest',
          '--format',
          'json',
        ]);

        expect(result.stdout, contains('"status"'));
        expect(result.stdout, contains('"errors"'));
      },
    );

    test('only fails an unevidenced profile with --require-evidence', () async {
      await runInProcessCli(['generate', '--root', root.path]);

      final ordinary = await runInProcessCli([
        'validate',
        '--root',
        root.path,
        '--profile',
        'pullRequest',
      ]);
      expect(ordinary.exitCode, 0, reason: ordinary.stderr);

      final guarded = await runInProcessCli([
        'validate',
        '--root',
        root.path,
        '--profile',
        'pullRequest',
        '--require-evidence',
      ]);
      expect(guarded.exitCode, isNot(0), reason: guarded.stdout);
      expect(guarded.stderr, contains('no executed evidence'));
    });

    test('reports the unevidenced profile in --format json', () async {
      await runInProcessCli(['generate', '--root', root.path]);

      final result = await runInProcessCli([
        'validate',
        '--root',
        root.path,
        '--profile',
        'pullRequest',
        '--require-evidence',
        '--format',
        'json',
      ]);

      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('ZUKE-PROFILE-UNTESTED'));
      expect(result.stdout, contains('"status": "failed"'));
    });

    test('--silent suppresses findings as well as progress output', () async {
      await runInProcessCli(['generate', '--root', root.path]);

      final loud = await runInProcessCli([
        'validate',
        '--root',
        root.path,
        '--profile',
        'pullRequest',
        '--require-evidence',
        '--quiet',
      ]);
      expect(loud.exitCode, isNot(0));
      expect(
        loud.stderr,
        contains('no executed evidence'),
        reason: '--quiet still reports findings',
      );

      final silent = await runInProcessCli([
        'validate',
        '--root',
        root.path,
        '--profile',
        'pullRequest',
        '--require-evidence',
        '--silent',
      ]);
      expect(silent.exitCode, isNot(0));
      expect(silent.stdout, isEmpty);
      expect(silent.stderr, isEmpty);
    });
  });
}
