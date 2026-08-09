import 'dart:io';

import 'package:test/test.dart';

import 'cli_test_helper.dart';

void main() {
  test('lock --check rejects a workspace with no lock file', () async {
    final directory = Directory.systemTemp.createTempSync('zuke_lock_probe_');
    try {
      Directory('${directory.path}/specs/features').createSync(recursive: true);
      File('${directory.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 2
workspace:
  name: stale-probe
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets: {}
''');
      File('${directory.path}/specs/features/test.feature').writeAsStringSync(
        '''
# spec-begin
# schemaVersion: 1
# id: FEAT-PROBE-001
# spec-end
@FEAT-PROBE-001
Feature: Probe
  # rule-spec-begin
  # id: RULE-PROBE-001
  # rule-spec-end
  @RULE-PROBE-001
  Rule: Probe rule
    @SCN-PROBE-001
    Scenario: probe
      Given a step
''',
      );

      final result = await runInProcessCli([
        'lock',
        '--root',
        directory.path,
        '--check',
      ]);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('Specification lock is stale or missing'));
      expect(File('${directory.path}/zuke.lock.json').existsSync(), isFalse);
    } finally {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
  });
}
