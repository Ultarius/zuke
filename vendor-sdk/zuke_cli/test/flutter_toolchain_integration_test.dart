import 'dart:io';

import 'package:zuke_cli/zuke_cli.dart';
import 'package:test/test.dart';

// The launcher contract under test. The outer test timeout below is derived
// from the execution bound so tightening the inner contract cannot fall back
// to Dart's 30s default, which is shorter than a cold first `flutter test` on
// a contended runner.
const _startupTimeout = Duration(seconds: 30);
const _firstOutputTimeout = Duration(seconds: 90);
const _executionTimeout = Duration(minutes: 2);

const _target = 'test/todo_controller_test.dart';

void main() {
  final enabled =
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
      Platform.environment['ZUKE_RUN_PROCESS_INTEGRATION'] == 'true';
  final runnerMode = Platform.isWindows
      ? ToolRunnerMode.auto
      : ToolRunnerMode.directSnapshot;
  final workingDirectory = _workspaceDirectory('examples', 'todo_app');

  // The inherited-CI pass-through contract is covered without a second Flutter
  // launch by tool_invocation_test.dart ('never adds CI but inherits it
  // naturally' and 'does not set CI when not in input').
  test(
    'streams Flutter through the selected launcher '
    'with mode=${Platform.isWindows ? 'auto' : 'directSnapshot'} '
    'and CI=unset',
    () async {
      final environment = Map<String, String>.from(Platform.environment)
        ..remove('CI');

      final target = File(
        <String>[
          workingDirectory.path,
          ..._target.split('/'),
        ].join(Platform.pathSeparator),
      );
      expect(
        target.existsSync(),
        isTrue,
        reason: 'Missing Flutter test target ${target.path}',
      );

      // The run must exercise the prepared snapshot invocation, not a platform
      // batch wrapper; assert the same resolution the supervisor performs
      // before launching.
      final prepared = prepareToolInvocation(
        'flutter',
        const ['test', '--no-pub'],
        environment,
        runnerMode: runnerMode,
      );
      final dartExecutable = Platform.isWindows ? 'dart.exe' : 'dart';
      expect(prepared.executable.toLowerCase(), endsWith(dartExecutable));
      expect(prepared.arguments, contains(endsWith('flutter_tools.snapshot')));

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
            _target,
          ],
          workingDirectory: workingDirectory.path,
          environment: environment,
          startupTimeout: _startupTimeout,
          executionTimeout: _executionTimeout,
          runnerMode: runnerMode,
          firstOutputTimeout: Platform.isWindows ? _firstOutputTimeout : null,
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
      expect(firstOutputAt, lessThan(_firstOutputTimeout));
      expect(
        '${result.stdout}\n${result.stderr}',
        contains('All tests passed'),
      );
    },
    // The launcher contract is bounded internally (30s startup, 2m execution,
    // 90s first output); this test outlives Dart's 30s default so a cold first
    // run on a contended runner fails through the coded diagnostic instead of
    // the generic test timeout.
    timeout: Timeout(_executionTimeout + const Duration(minutes: 1)),
    skip: enabled
        ? false
        : 'Set ZUKE_RUN_PROCESS_INTEGRATION=true on a supported OS.',
  );
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
