import 'dart:io';

import 'package:zuke_cli/zuke_cli.dart';
import 'package:test/test.dart';

void main() {
  final enabled =
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
      Platform.environment['ZUKE_RUN_PROCESS_INTEGRATION'] == 'true';

  for (final inheritedCi in [false, true]) {
    test(
      'streams Flutter through the selected launcher '
      'with mode=${Platform.isWindows ? 'auto' : 'directSnapshot'} '
      'and CI=${inheritedCi ? 'true' : 'unset'}',
      () async {
        final environment = Map<String, String>.from(Platform.environment);
        if (inheritedCi) {
          environment['CI'] = 'true';
        } else {
          environment.remove('CI');
        }

        final stopwatch = Stopwatch()..start();
        Duration? firstOutputAt;
        final result = await const LocalProcessSupervisor().run(
          ProcessRunRequest(
            executable: 'flutter',
            arguments: const [
              'test',
              '--no-pub',
              '--reporter',
              'compact',
              'test/todo_controller_test.dart',
            ],
            workingDirectory: _workspaceDirectory('examples', 'todo_app').path,
            environment: environment,
            startupTimeout: const Duration(seconds: 30),
            executionTimeout: const Duration(minutes: 2),
            runnerMode: Platform.isWindows
                ? ToolRunnerMode.auto
                : ToolRunnerMode.directSnapshot,
            firstOutputTimeout: Platform.isWindows
                ? const Duration(seconds: 90)
                : null,
            onStdoutChunk: (_) {
              firstOutputAt ??= stopwatch.elapsed;
            },
            onStderrChunk: (_) {
              firstOutputAt ??= stopwatch.elapsed;
            },
          ),
        );
        stopwatch.stop();

        expect(result.exitCode, 0, reason: result.stderr);
        expect(firstOutputAt, isNotNull);
        expect(firstOutputAt, lessThan(const Duration(seconds: 90)));
        expect(
          '${result.stdout}\n${result.stderr}',
          contains('All tests passed'),
        );
      },
      skip: enabled
          ? false
          : 'Set ZUKE_RUN_PROCESS_INTEGRATION=true on a supported OS.',
    );
  }
}

Directory _workspaceDirectory(String first, String second) {
  var candidate = Directory.current.absolute;
  while (true) {
    final melos = File('${candidate.path}${Platform.pathSeparator}melos.yaml');
    if (melos.existsSync()) {
      return Directory(
        <String>[candidate.path, first, second].join(Platform.pathSeparator),
      );
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Could not locate the Zuke workspace root.');
    }
    candidate = parent;
  }
}
