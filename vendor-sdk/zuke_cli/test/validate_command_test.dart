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
  });
}
