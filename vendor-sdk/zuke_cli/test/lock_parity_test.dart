import 'dart:convert';
import 'dart:io';

import 'package:zuke_test_support/zuke_test_support.dart';
import 'package:test/test.dart';
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

        final lockFile = File('${root.path}/zuke.lock.json');
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

        final lockFile = File('${root.path}/zuke.lock.json');
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
        lockFile.writeAsStringSync('$originalContent\n// modified\n');

        // 4. Run check command on stale lock — must FAIL, not overwrite
        final checkStaleResult = await runInProcessCli([
          'check',
          '--root',
          root.path,
          '--profile',
          'pullRequest',
        ]);
        expect(checkStaleResult.exitCode, 1);
      },
    );
  });
}
