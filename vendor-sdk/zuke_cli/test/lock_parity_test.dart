import 'dart:convert';
import 'dart:io';

import 'support/temporary_directory.dart';
import 'package:test/test.dart';
import 'package:zuke_core/zuke_core.dart';
import 'helpers/eligible_workspace.dart';
import 'cli_test_helper.dart';

void main() {
  group('Lock parity and read-only check mode', () {
    late Directory root;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('zuke-lock-parity-');
      await createEligibleWorkspace(root);
    });

    tearDown(() => deleteTemporaryDirectory(root));

    test('refresh produces a receipt and protects lock destinations', () async {
      final lock = File('${root.path}/assurance/locks/pullRequest.lock.json');
      final rejected = await runInProcessCli([
        'lock',
        '--refresh',
        '--root',
        root.path,
        '--diff-output',
        lock.path,
      ]);
      expect(rejected.exitCode, isNot(0));
      expect(lock.existsSync(), isFalse);
      final receipt = File('${root.path}/lock-diff.json');
      final refreshed = await runInProcessCli([
        'lock',
        '--refresh',
        '--root',
        root.path,
        '--profile',
        'pullRequest',
        '--diff-output',
        receipt.path,
      ]);
      expect(refreshed.exitCode, 0, reason: refreshed.stderr);
      final json = jsonDecode(receipt.readAsStringSync()) as Map;
      final change = (json['changed'] as List).single as Map;
      expect(change['profile'], 'pullRequest');
      expect(change['beforePresent'], isFalse);
      expect(change['afterPresent'], isTrue);
      expect(change['afterSha256'], hasLength(64));
      final bytes = receipt.readAsBytesSync();
      final repeated = await runInProcessCli([
        'lock',
        '--refresh',
        '--root',
        root.path,
        '--diff-output',
        receipt.path,
      ]);
      expect(repeated.exitCode, isNot(0));
      expect(receipt.readAsBytesSync(), bytes);
    });

    test(
      'lock update refreshes every configured profile and is not check mode',
      () async {
        await runInProcessCli(['generate', '--root', root.path]);

        final result = await runInProcessCli([
          'lock',
          '--root',
          root.path,
          '--update',
        ]);

        expect(result.exitCode, 0);
        for (final profile in ['pullRequest', 'merge', 'release', 'nightly']) {
          expect(
            File(
              '${root.path}/assurance/locks/$profile.lock.json',
            ).existsSync(),
            isTrue,
          );
        }
        final check = await runInProcessCli([
          'lock',
          '--root',
          root.path,
          '--all-profiles',
          '--check',
        ]);
        expect(check.exitCode, 0);
      },
    );

    test('refreshes multiple roots and only the requested profiles', () async {
      final second = Directory.systemTemp.createTempSync('zuke-second-root-');
      addTearDown(() => deleteTemporaryDirectory(second));
      await createEligibleWorkspace(second);
      final result = await runInProcessCli([
        'lock',
        '--refresh',
        '--roots',
        root.path,
        '--roots',
        second.path,
        '--profiles',
        'pullRequest',
        '--profiles',
        'merge',
      ]);
      expect(result.exitCode, 0, reason: result.stderr);
      for (final directory in [root, second]) {
        for (final profile in ['pullRequest', 'merge']) {
          final checked = await runInProcessCli([
            'lock',
            '--root',
            directory.path,
            '--profile',
            profile,
            '--check',
          ]);
          expect(checked.exitCode, 0, reason: checked.stderr);
        }
        expect(
          File(
            '${directory.path}/assurance/locks/release.lock.json',
          ).existsSync(),
          isFalse,
        );
      }
    });

    test(
      'invalid later root selection fails before changing the first root',
      () async {
        final invalid = Directory.systemTemp.createTempSync(
          'zuke-invalid-root-',
        );
        addTearDown(() => deleteTemporaryDirectory(invalid));
        File('${invalid.path}/zuke.yaml').writeAsStringSync('schemaVersion: 0');
        final result = await runInProcessCli([
          'lock',
          '--refresh',
          '--roots',
          root.path,
          '--roots',
          invalid.path,
        ]);
        expect(result.exitCode, isNot(0));
        expect(Directory('${root.path}/assurance/locks').existsSync(), isFalse);
        expect(
          Directory('${root.path}/generated/evidence').existsSync(),
          isFalse,
        );
      },
    );

    test('publication failure restores an already replaced profile', () async {
      await runInProcessCli(['generate', '--root', root.path]);
      final lock = File('${root.path}/assurance/locks/pullRequest.lock.json');
      lock.parent.createSync(recursive: true);
      lock.writeAsStringSync('previous lock bytes');
      Directory('${root.path}/assurance/locks/merge.lock.json').createSync();
      final result = await runInProcessCli([
        'lock',
        '--root',
        root.path,
        '--update',
        '--profiles',
        'pullRequest',
        '--profiles',
        'merge',
      ]);
      expect(result.exitCode, isNot(0));
      expect(lock.readAsStringSync(), 'previous lock bytes');
    });

    test('lock update and check are rejected together', () async {
      final result = await runInProcessCli([
        'lock',
        '--root',
        root.path,
        '--update',
        '--check',
      ]);

      expect(result.exitCode, 2);
      expect(result.stderr, contains('mutually exclusive'));
    });

    test('all-profiles and a selected profile are rejected together', () async {
      final result = await runInProcessCli([
        'lock',
        '--root',
        root.path,
        '--all-profiles',
        '--profile',
        'pullRequest',
      ]);

      expect(result.exitCode, 2);
      expect(result.stderr, contains('mutually exclusive'));
    });

    test(
      'lock refresh runs the managed pipeline before attempting a lock write',
      () async {
        final result = await runInProcessCli([
          'lock',
          '--root',
          root.path,
          '--all-profiles',
          '--refresh',
        ]);

        expect(result.exitCode, 0);
        expect(result.stdout, contains('Refreshing Zuke evidence'));
        expect(
          File(
            '${root.path}/assurance/locks/pullRequest.lock.json',
          ).existsSync(),
          isTrue,
        );
      },
    );

    test(
      'lock refresh does not publish locks when managed execution fails',
      () async {
        final config = File('${root.path}/zuke.yaml');
        final original = config.readAsStringSync();
        final failing = Platform.isWindows
            ? original.replaceFirst('exit 0', 'exit 7')
            : original.replaceFirst(
                "executable: 'true'",
                "executable: 'false'",
              );
        config.writeAsStringSync(failing);

        final result = await runInProcessCli([
          'lock',
          '--root',
          root.path,
          '--profile',
          'pullRequest',
          '--refresh',
        ]);

        expect(result.exitCode, isNot(0));
        expect(Directory('${root.path}/assurance/locks').existsSync(), isFalse);
      },
    );

    test(
      'specificationDigest is non-empty and changes when specs change',
      () async {
        await runInProcessCli(['generate', '--root', root.path]);

        final writeResult = await runInProcessCli([
          'lock',
          '--root',
          root.path,
          '--profile',
          'pullRequest',
        ]);
        expect(writeResult.exitCode, 0);

        final lockFile = File(
          '${root.path}/assurance/locks/pullRequest.lock.json',
        );
        expect(lockFile.existsSync(), isTrue);

        final json =
            jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>;
        final digest = json['specificationDigest'] as String;
        expect(json['specificationDigestScope'], 'discovery-inputs-v1');

        // Must not be the SHA-256 of empty bytes
        const emptyDigest =
            'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
        expect(digest, isNot(equals(emptyDigest)));
        expect(digest, startsWith('sha256:'));

        // Modifying a feature file alters the digest
        final featureFile = File('${root.path}/specs/features/gateway.feature');
        featureFile.writeAsStringSync(
          '${featureFile.readAsStringSync()}\n# edit\n',
        );

        final checkResult = await runInProcessCli([
          'lock',
          '--root',
          root.path,
          '--profile',
          'pullRequest',
          '--check',
        ]);
        expect(checkResult.exitCode, 1);
        expect(checkResult.stderr, contains('stale or missing'));
      },
    );

    test(
      'check command is strictly read-only and agrees with lock --check',
      () async {
        await runInProcessCli(['generate', '--root', root.path]);

        // 1. Initially create lock
        final writeResult = await runInProcessCli([
          'lock',
          '--root',
          root.path,
          '--profile',
          'pullRequest',
        ]);
        expect(writeResult.exitCode, 0);

        final lockFile = File(
          '${root.path}/assurance/locks/pullRequest.lock.json',
        );
        final originalContent = lockFile.readAsStringSync();

        // 2. Run check command — must pass and NOT modify the lock file
        final checkCmdResult = await runInProcessCli([
          'check',
          '--root',
          root.path,
          '--profile',
          'pullRequest',
        ]);
        expect(checkCmdResult.exitCode, 0);
        expect(lockFile.readAsStringSync(), equals(originalContent));

        // 3. Make lock file stale by modifying it
        final modifiedLock = Map<String, Object?>.from(
          jsonDecode(originalContent) as Map,
        )..['policyHash'] = 'sha256:${List.filled(64, '0').join()}';
        lockFile.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(modifiedLock)}\n',
        );

        // 4. Run check command on stale lock — must FAIL, not overwrite
        final checkStaleResult = await runInProcessCli([
          'check',
          '--root',
          root.path,
          '--profile',
          'pullRequest',
          '--format',
          'json',
        ]);
        expect(checkStaleResult.exitCode, 1);

        final commandResult = CommandResult.fromJson(
          Map<Object?, Object?>.from(
            jsonDecode(checkStaleResult.stdout) as Map,
          ),
        );
        final workspaces = commandResult.details['workspaces'] as List;
        final workspace = Map<Object?, Object?>.from(workspaces.single as Map);
        final stages = (workspace['stages'] as List)
            .cast<Map<Object?, Object?>>();
        final lockStage = stages.singleWhere(
          (stage) => stage['name'] == 'lock',
        );
        final diagnostics = (lockStage['diagnostics'] as List)
            .cast<Map<Object?, Object?>>();
        expect(
          diagnostics.map((diagnostic) => diagnostic['code']),
          contains('ZK-LOCK-STALE'),
        );
      },
    );
  });
}
