import 'dart:convert';
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

    test(
      'renders informational binding findings, which only exist in result.infos',
      () async {
        await root.delete(recursive: true);
        await createEligibleWorkspace(root, bindingCoverage: true);
        await runInProcessCli(['generate', '--root', root.path]);

        final result = await runInProcessCli([
          'validate',
          '--root',
          root.path,
          '--profile',
          'pullRequest',
        ]);

        // The rule declares a flutter-widget slot and the workspace has a runner
        // for that target, package and adapter but no test publishing the kind,
        // so this is a decided gap.
        expect(
          result.stderr,
          contains('ZUKE-EVIDENCE-BINDING-UNBOUND'),
          reason: 'the gap is a warning and renders on stderr',
        );

        // The per-feature roll-up is informational. Before infos were rendered,
        // it reached only the JSON report and vanished from plain output.
        expect(
          result.stderr,
          contains('ZUKE-EVIDENCE-BINDING-SUMMARY'),
          reason: 'informational findings render too',
        );
        expect(result.stdout, contains('Info:'));
      },
    );

    test('--quiet still reports informational findings', () async {
      await root.delete(recursive: true);
      await createEligibleWorkspace(root, bindingCoverage: true);
      await runInProcessCli(['generate', '--root', root.path]);

      final quiet = await runInProcessCli([
        'validate',
        '--root',
        root.path,
        '--profile',
        'pullRequest',
        '--quiet',
      ]);

      // --quiet suppresses progress, not findings. An informational finding is
      // a finding.
      expect(
        quiet.stderr,
        contains('ZUKE-EVIDENCE-BINDING-SUMMARY'),
        reason: quiet.stdout,
      );
    });

    test('--silent suppresses informational findings too', () async {
      await root.delete(recursive: true);
      await createEligibleWorkspace(root, bindingCoverage: true);
      await runInProcessCli(['generate', '--root', root.path]);

      final silent = await runInProcessCli([
        'validate',
        '--root',
        root.path,
        '--profile',
        'pullRequest',
        '--silent',
      ]);

      // The counterpart to the --quiet case. `--silent` is the stronger switch:
      // it suppresses findings as well as progress, which is what
      // `lock --refresh` relies on when it validates as a probe and validates
      // again after the tests. Informational findings are findings, so they go
      // with the rest.
      expect(silent.stderr, isNot(contains('ZUKE-EVIDENCE-BINDING')));
      expect(
        silent.stdout,
        isNot(contains('ZUKE-EVIDENCE-BINDING-SUMMARY')),
        reason: silent.stdout,
      );
      // The run still happened: a silent validation is not a no-op that could
      // pass by doing nothing.
      expect(silent.exitCode, isNot(0), reason: silent.stdout);
    });

    test(
      'the JSON report carries all three diagnostic buckets, including infos',
      () async {
        // `infos` is newer than `errors` and `warnings` and nothing pinned its
        // presence, so renaming or dropping the key would have left every other
        // test green while a consumer reading the JSON silently stopped seeing
        // informational findings. Asserted by name, and by content, rather than
        // by the whole document: the report's own keys change for unrelated
        // reasons and pinning them here would make this test about the wrong
        // thing.
        await root.delete(recursive: true);
        await createEligibleWorkspace(root, bindingCoverage: true);
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

        final report = jsonDecode(result.stdout) as Map<String, dynamic>;
        for (final bucket in ['errors', 'warnings', 'infos']) {
          expect(report.containsKey(bucket), isTrue, reason: 'missing $bucket');
          expect(report[bucket], isA<List<dynamic>>(), reason: bucket);
        }

        List<String> codesIn(String bucket) => [
          for (final entry in report[bucket] as List<dynamic>)
            (entry as Map<String, dynamic>)['code'] as String,
        ];
        expect(codesIn('warnings'), contains('ZUKE-EVIDENCE-BINDING-UNBOUND'));
        expect(codesIn('infos'), contains('ZUKE-EVIDENCE-BINDING-SUMMARY'));
        expect(
          codesIn('warnings'),
          isNot(contains('ZUKE-EVIDENCE-BINDING-SUMMARY')),
        );
        expect(codesIn('errors'), contains('ZUKE-EVID-003'));
        expect(
          codesIn('errors'),
          isNot(contains('ZUKE-EVIDENCE-BINDING-SUMMARY')),
        );
      },
    );
  });
}
