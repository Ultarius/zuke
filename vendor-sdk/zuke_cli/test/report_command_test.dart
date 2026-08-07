import 'dart:io';

import 'package:test/test.dart';
import 'helpers/eligible_workspace.dart';
import 'cli_test_helper.dart';

void main() {
  group('ReportCommand', () {
    late Directory root;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('zuke-report-');
      await createEligibleWorkspace(root);
    });

    tearDown(() {
      if (root.existsSync()) {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('writes zuke-model.json report file', () async {
      await runInProcessCli(['generate', '--root', root.path]);

      final result = await runInProcessCli(['report', '--root', root.path]);
      expect(result.exitCode, 0);

      final reportFile = File('${root.path}/generated/report/zuke-model.json');
      expect(reportFile.existsSync(), isTrue);
      expect(reportFile.readAsStringSync(), contains('FEAT-GATEWAY-001'));
    });
  });
}
