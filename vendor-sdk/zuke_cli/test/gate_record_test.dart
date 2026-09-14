import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'cli_test_helper.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('zuke-record-'));
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'preserves append-only history, identity and diagnostic ownership',
    () async {
      final summary = File('${root.path}/summary.json')
        ..writeAsStringSync(
          jsonEncode({
            'kind': 'zuke.command-result',
            'command': 'gate',
            'stage': 'gate',
            'exitCode': 1,
            'status': 'failed',
            'eligible': false,
            'runId': 'run-1',
            'profile': 'merge',
            'diagnostics': [
              for (final owner in ['zuke', 'project'])
                {
                  'code': 'TEST-$owner',
                  'stage': 'validate',
                  'severity': 'error',
                  'owner': owner,
                  'message': '$owner failure',
                  'remediation': 'Repair fixture',
                },
            ],
          }),
        );
      final history = File('${root.path}/history.txt')
        ..writeAsStringSync('existing history\n');
      final output = File('${root.path}/record.json');
      for (var i = 0; i < 2; i++) {
        final result = await runInProcessCli([
          'gate',
          'record',
          '--summary-file',
          summary.path,
          '--blocker-file',
          history.path,
          '--output',
          output.path,
          '--release-id',
          'release-1',
          '--commit-sha',
          'abc123',
        ]);
        expect(result.exitCode, 1);
      }
      final record = jsonDecode(output.readAsStringSync()) as Map;
      expect(record['kind'], 'zuke.application-gate-record');
      expect(record['runId'], 'run-1');
      expect(record['profile'], 'merge');
      expect(record['commitSha'], 'abc123');
      expect(history.readAsStringSync(), startsWith('existing history\n'));
      expect(
        'AUTOMATED ZUKE GATE RECORD'.allMatches(history.readAsStringSync()),
        hasLength(2),
      );
      final handoff = File('${root.path}/handoff.txt');
      final result = await runInProcessCli([
        'gate',
        'handoff',
        '--summary-file',
        summary.path,
        '--output',
        handoff.path,
      ]);
      expect(result.exitCode, 0);
      expect(handoff.readAsStringSync(), contains('TEST-zuke'));
      expect(handoff.readAsStringSync(), isNot(contains('TEST-project')));
    },
  );

  test(
    'missing and malformed summaries record unknown ownership and fail',
    () async {
      final summary = File('${root.path}/missing.json');
      for (final content in [null, '{', '{}']) {
        if (content != null) summary.writeAsStringSync(content);
        final output = File('${root.path}/record.json');
        final result = await runInProcessCli([
          'gate',
          'record',
          '--summary-file',
          summary.path,
          '--output',
          output.path,
          '--blocker-file',
          '${root.path}/history.txt',
        ]);
        expect(result.exitCode, 1);
        final record = jsonDecode(output.readAsStringSync()) as Map;
        expect(record['passed'], false);
        expect(record['diagnostics'][0]['owner'], 'unknown');
      }
    },
  );
}
