import 'dart:io';

import 'package:test/test.dart';

import 'cli_test_helper.dart';
import 'helpers/eligible_workspace.dart';
import 'support/temporary_directory.dart';

void main() {
  group('Lock failure remediation', () {
    late Directory root;

    tearDown(() => deleteTemporaryDirectory(root));

    test('an unexecuted selected scenario names lock --refresh', () async {
      // A tag expression gives `lock` a selected scenario set to reason about.
      // Without one the fixture runs selection-managed and never reports an
      // untested scenario.
      root = Directory.systemTemp.createTempSync('zuke-lock-hint-');
      await createEligibleWorkspace(
        root,
        pullRequestTagExpression: '@pr',
        scenarioTags: const ['@pr'],
      );

      final generate = await runInProcessCli(['generate', '--root', root.path]);
      expect(generate.exitCode, 0, reason: generate.stdout);

      final result = await runInProcessCli(['lock', '--root', root.path]);
      expect(result.exitCode, isNot(0), reason: result.stderr);
      expect(result.stderr, contains('ZUKE-SCENARIO-UNTESTED'));
      expect(result.stderr, contains('zuke lock --refresh'));
    });

    test('a lock that succeeds never suggests a refresh', () async {
      root = Directory.systemTemp.createTempSync('zuke-lock-hint-');
      await createEligibleWorkspace(root);

      final generate = await runInProcessCli(['generate', '--root', root.path]);
      expect(generate.exitCode, 0, reason: generate.stdout);

      final result = await runInProcessCli(['lock', '--root', root.path]);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stderr, isNot(contains('zuke lock --refresh')));
    });
  });
}
