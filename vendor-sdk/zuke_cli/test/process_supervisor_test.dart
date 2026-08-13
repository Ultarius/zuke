import 'dart:io';

import 'package:zuke_cli/zuke_cli.dart';
import 'support/temporary_directory.dart';
import 'package:test/test.dart';

void main() {
  test('process failure preserves a stable diagnostic contract', () {
    const failure = SupervisedProcessException(
      kind: ProcessFailureKind.terminationFailure,
      diagnosticCode: 'ZUKE-PROCESS-TERMINATION-FAILED',
      message: 'runner remained alive after tree termination',
    );

    expect(failure.kind, ProcessFailureKind.terminationFailure);
    expect(failure.toString(), contains('ZUKE-PROCESS-TERMINATION-FAILED'));
  });

  test('process request keeps startup and execution limits distinct', () {
    const request = ProcessRunRequest(
      executable: 'dart',
      arguments: ['test'],
      workingDirectory: '.',
      environment: {'ZUKE_PROFILE': 'pullRequest'},
      startupTimeout: Duration(seconds: 60),
      executionTimeout: Duration(minutes: 10),
    );

    expect(request.startupTimeout, const Duration(seconds: 60));
    expect(request.executionTimeout, const Duration(minutes: 10));
  });

  test('streams output before the child exits', () async {
    final directory = Directory.systemTemp.createTempSync('zuke_stream_');
    final script = File('${directory.path}${Platform.pathSeparator}runner.dart')
      ..writeAsStringSync(
        "import 'dart:async'; void main() async { print('ready'); await Future<void>.delayed(const Duration(milliseconds: 80)); }",
      );
    final chunks = <String>[];
    try {
      await const LocalProcessSupervisor().run(
        ProcessRunRequest(
          executable: Platform.resolvedExecutable,
          arguments: ['run', script.path],
          workingDirectory: directory.path,
          environment: Platform.environment,
          startupTimeout: const Duration(seconds: 10),
          executionTimeout: const Duration(seconds: 10),
          onStdoutChunk: chunks.add,
        ),
      );
      expect(chunks.join(), contains('ready'));
    } finally {
      await deleteTemporaryDirectory(directory);
    }
  });

  test('drains stdout and stderr emitted immediately before exit', () async {
    final directory = Directory.systemTemp.createTempSync('zuke_tail_');
    final script = File('${directory.path}${Platform.pathSeparator}tail.dart')
      ..writeAsStringSync('''import 'dart:io';
void main() {
  for (var index = 0; index < 5000; index++) {
    stdout.writeln('tail-out-\$index');
    stderr.writeln('tail-err-\$index');
  }
}
''');
    try {
      final result = await const LocalProcessSupervisor().run(
        ProcessRunRequest(
          executable: Platform.resolvedExecutable,
          arguments: ['run', script.path],
          workingDirectory: directory.path,
          environment: Platform.environment,
          startupTimeout: const Duration(seconds: 10),
          executionTimeout: const Duration(seconds: 10),
        ),
      );
      expect(result.exitCode, 0);
      expect(result.stdout, contains('tail-out-4999'));
      expect(result.stderr, contains('tail-err-4999'));
    } finally {
      await deleteTemporaryDirectory(directory);
    }
  });

  test('firstOutputTimeout fires when process produces no output', () async {
    final directory = Directory.systemTemp.createTempSync('zuke_timeout_');
    final script = File('${directory.path}${Platform.pathSeparator}slow.dart')
      ..writeAsStringSync(
        "import 'dart:async'; void main() async { await Future.delayed(const Duration(seconds: 10)); print('done'); }",
      );
    try {
      await expectLater(
        const LocalProcessSupervisor().run(
          ProcessRunRequest(
            executable: Platform.resolvedExecutable,
            arguments: ['run', script.path],
            workingDirectory: directory.path,
            environment: Platform.environment,
            startupTimeout: const Duration(seconds: 10),
            executionTimeout: const Duration(seconds: 30),
            firstOutputTimeout: const Duration(milliseconds: 10),
          ),
        ),
        throwsA(
          isA<SupervisedProcessException>().having(
            (e) => e.kind,
            'kind',
            ProcessFailureKind.noOutput,
          ),
        ),
      );
    } finally {
      await deleteTemporaryDirectory(directory);
    }
  });

  test('firstOutputTimeout is cancelled when output arrives', () async {
    final directory = Directory.systemTemp.createTempSync('zuke_quick_');
    final script = File('${directory.path}${Platform.pathSeparator}fast.dart')
      ..writeAsStringSync("void main() { print('ready'); }");
    final chunks = <String>[];
    try {
      final result = await const LocalProcessSupervisor().run(
        ProcessRunRequest(
          executable: Platform.resolvedExecutable,
          arguments: ['run', script.path],
          workingDirectory: directory.path,
          environment: Platform.environment,
          startupTimeout: const Duration(seconds: 10),
          executionTimeout: const Duration(seconds: 10),
          firstOutputTimeout: const Duration(seconds: 5),
          onStdoutChunk: chunks.add,
        ),
      );
      expect(result.exitCode, 0);
      expect(chunks.join(), contains('ready'));
    } finally {
      await deleteTemporaryDirectory(directory);
    }
  });

  test('a silent successful process returns its actual exit code', () async {
    final directory = Directory.systemTemp.createTempSync('zuke_silent_');
    final script = File('${directory.path}${Platform.pathSeparator}silent.dart')
      ..writeAsStringSync('void main() {}');
    try {
      final result = await const LocalProcessSupervisor().run(
        ProcessRunRequest(
          executable: Platform.resolvedExecutable,
          arguments: ['run', script.path],
          workingDirectory: directory.path,
          environment: Platform.environment,
          startupTimeout: const Duration(seconds: 10),
          executionTimeout: const Duration(seconds: 10),
          firstOutputTimeout: const Duration(seconds: 5),
        ),
      );
      expect(result.exitCode, 0);
      expect(result.stdout, isEmpty);
      expect(result.stderr, isEmpty);
    } finally {
      await deleteTemporaryDirectory(directory);
    }
  });

  test('execution timeout remains active after first output', () async {
    final directory = Directory.systemTemp.createTempSync('zuke_hang_');
    final script = File('${directory.path}${Platform.pathSeparator}hang.dart')
      ..writeAsStringSync(
        "import 'dart:async'; void main() async { print('ready'); "
        'await Future<void>.delayed(const Duration(seconds: 10)); }',
      );
    try {
      await expectLater(
        const LocalProcessSupervisor().run(
          ProcessRunRequest(
            executable: Platform.resolvedExecutable,
            arguments: ['run', script.path],
            workingDirectory: directory.path,
            environment: Platform.environment,
            startupTimeout: const Duration(seconds: 10),
            executionTimeout: const Duration(milliseconds: 500),
            firstOutputTimeout: const Duration(seconds: 5),
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
    } finally {
      await deleteTemporaryDirectory(directory);
    }
  });

  test(
    'captures safe generic batch output and rejects shell metacharacters',
    () async {
      if (!Platform.isWindows) return;
      final directory = Directory.systemTemp.createTempSync('zuke_batch_safe_');
      final script = File('${directory.path}${Platform.pathSeparator}emit.bat')
        ..writeAsStringSync('''@echo off
echo batch-out
echo batch-err 1>&2
exit /b 7
''');
      try {
        final result = await const LocalProcessSupervisor().run(
          ProcessRunRequest(
            executable: script.path,
            arguments: const ['safe value', "apostrophe's value"],
            workingDirectory: directory.path,
            environment: Platform.environment,
            startupTimeout: const Duration(seconds: 10),
            executionTimeout: const Duration(seconds: 10),
          ),
        );
        expect(result.exitCode, 7);
        expect(result.stdout, contains('batch-out'));
        expect(result.stderr, contains('batch-err'));

        await expectLater(
          const LocalProcessSupervisor().run(
            ProcessRunRequest(
              executable: script.path,
              arguments: const ['unsafe&value'],
              workingDirectory: directory.path,
              environment: Platform.environment,
              startupTimeout: Duration(seconds: 10),
              executionTimeout: Duration(seconds: 10),
            ),
          ),
          throwsA(
            isA<SupervisedProcessException>().having(
              (error) => error.diagnosticCode,
              'diagnosticCode',
              'ZUKE-BATCH-UNSAFE-ARGUMENT',
            ),
          ),
        );
      } finally {
        await deleteTemporaryDirectory(directory);
      }
    },
  );

  test(
    'tool preparation failures preserve their diagnostic code',
    () async {
      final missingRoot = Directory.systemTemp.createTempSync(
        'missing_flutter_',
      )..deleteSync();
      await expectLater(
        const LocalProcessSupervisor().run(
          ProcessRunRequest(
            executable: 'flutter',
            arguments: ['test'],
            workingDirectory: Directory.current.path,
            environment: {'FLUTTER_ROOT': missingRoot.path},
            startupTimeout: const Duration(seconds: 10),
            executionTimeout: const Duration(seconds: 10),
          ),
        ),
        throwsA(
          isA<SupervisedProcessException>()
              .having(
                (error) => error.kind,
                'kind',
                ProcessFailureKind.launchFailure,
              )
              .having(
                (error) => error.diagnosticCode,
                'diagnosticCode',
                'ZUKE-FLUTTER-NOT-FOUND',
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('Bad state:')),
              ),
        ),
      );
    },
    skip: Platform.isWindows ? false : 'Windows Flutter resolution only.',
  );
}
