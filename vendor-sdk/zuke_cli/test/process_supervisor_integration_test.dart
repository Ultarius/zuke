import 'dart:convert';
import 'dart:io';

import 'package:zuke_cli/zuke_cli.dart';
import 'support/temporary_directory.dart';
import 'package:test/test.dart';

void main() {
  final enabled =
      Platform.environment['ZUKE_RUN_PROCESS_INTEGRATION'] == 'true';

  test(
    'terminates a real parent and heartbeat child on timeout',
    () async {
      final directory = Directory.systemTemp.createTempSync('zuke_tree_');
      final heartbeat = File(
        '${directory.path}${Platform.pathSeparator}heartbeat',
      );
      final fixture = File(
        '${_workspaceRoot().path}${Platform.pathSeparator}vendor-sdk'
        '${Platform.pathSeparator}zuke_cli${Platform.pathSeparator}test'
        '${Platform.pathSeparator}fixtures${Platform.pathSeparator}'
        'process_tree_fixture.dart',
      );
      try {
        await expectLater(
          const LocalProcessSupervisor().run(
            ProcessRunRequest(
              executable: Platform.resolvedExecutable,
              arguments: [fixture.path, heartbeat.path],
              workingDirectory: Directory.current.path,
              environment: Platform.environment,
              startupTimeout: const Duration(seconds: 10),
              // The process has no package resolution now, but CI filesystems
              // still need scheduler headroom before the intentional timeout.
              executionTimeout: const Duration(seconds: 5),
            ),
          ),
          throwsA(
            isA<SupervisedProcessException>().having(
              (error) => error.kind,
              'kind',
              ProcessFailureKind.executionTimeout,
            ),
          ),
        );
        final ready = File('${heartbeat.path}.ready');
        expect(ready.existsSync(), isTrue);
        final ids =
            jsonDecode(ready.readAsStringSync()) as Map<String, Object?>;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(await _alive(ids['parent'] as int), isFalse);
        expect(await _alive(ids['child'] as int), isFalse);
      } finally {
        await deleteTemporaryDirectory(directory);
      }
    },
    skip: enabled ? false : 'Set ZUKE_RUN_PROCESS_INTEGRATION=true in CI.',
  );
}

Directory _workspaceRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    if (File(
      '${candidate.path}${Platform.pathSeparator}melos.yaml',
    ).existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Could not locate the Zuke workspace root.');
    }
    candidate = parent;
  }
}

Future<bool> _alive(int processId) async {
  if (Platform.isWindows) {
    final result = await Process.run('tasklist.exe', [
      '/FI',
      'PID eq $processId',
      '/NH',
    ]);
    return result.exitCode == 0 &&
        result.stdout.toString().contains('$processId');
  }
  final result = await Process.run('ps', ['-p', '$processId']);
  return result.exitCode == 0 &&
      result.stdout.toString().split('\n').length > 1;
}
