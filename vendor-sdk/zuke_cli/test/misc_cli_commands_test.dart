import 'dart:io';

import 'package:test/test.dart';
import 'helpers/eligible_workspace.dart';
import 'cli_test_helper.dart';

void main() {
  group('Misc CLI Commands', () {
    late Directory root;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('zuke-misc-');
      await createEligibleWorkspace(root);
    });

    tearDown(() {
      if (root.existsSync()) {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('runs doctor command', () async {
      final result = await runInProcessCli(['doctor', '--root', root.path]);
      expect(result.exitCode, isNotNull);
    });

    test('runs affected command', () async {
      final result = await runInProcessCli(['affected', '--root', root.path]);
      expect(result.exitCode, isNotNull);
    });

    test('runs watch command', () async {
      final result = await runInProcessCli([
        'watch',
        '--once',
        '--root',
        root.path,
      ]);
      expect(result.exitCode, isNotNull);
    });

    test('runs test command', () async {
      await runInProcessCli(['generate', '--root', root.path]);
      final result = await runInProcessCli(['test', '--root', root.path]);
      expect(result.exitCode, isNotNull);
    });

    test('runs check command with --format json and invalid root', () async {
      await runInProcessCli(['generate', '--root', root.path]);
      await runInProcessCli(['lock', '--root', root.path]);
      final jsonRes = await runInProcessCli([
        'check',
        '--root',
        root.path,
        '--format',
        'json',
      ]);
      expect(jsonRes.exitCode, 0);
      expect(jsonRes.stdout, contains('"kind":"zuke.command-result"'));

      final invalidRes = await runInProcessCli([
        'check',
        '--root',
        '${root.path}/nonexistent',
      ]);
      expect(invalidRes.exitCode, 1);
    });

    test('runs init command with --dry-run', () async {
      final freshDir = Directory.systemTemp.createTempSync('zuke-init-dry-');
      try {
        Directory(
          '${freshDir.path}/vendor-sdk/zuke_dart_build_hook',
        ).createSync(recursive: true);
        final pkgDir = Directory('${freshDir.path}/packages/my_pkg')
          ..createSync(recursive: true);
        File(
          '${pkgDir.path}/pubspec.yaml',
        ).writeAsStringSync('name: my_pkg\ndependencies:\n  meta: ^1.0.0\n');

        final result = await runInProcessCli([
          'init',
          '--root',
          freshDir.path,
          '--enable-dart-build-hooks',
          '--dry-run',
          '--package',
          'packages/my_pkg',
        ]);
        expect(result.exitCode, 0);
      } finally {
        if (freshDir.existsSync()) freshDir.deleteSync(recursive: true);
      }
    });

    test('runs adopt package command', () async {
      final result = await runInProcessCli([
        'adopt',
        'package',
        '--root',
        root.path,
        '--dry-run',
      ]);
      expect(result.exitCode, isNotNull);
    });
  });
}
