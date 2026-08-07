import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'tool_invocation.dart';

final class ProcessRunRequest {
  const ProcessRunRequest({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
    required this.startupTimeout,
    required this.executionTimeout,
    this.runnerMode = ToolRunnerMode.auto,
    this.firstOutputTimeout,
    this.onStdoutChunk,
    this.onStderrChunk,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final Duration startupTimeout;
  final Duration executionTimeout;
  final ToolRunnerMode runnerMode;
  final Duration? firstOutputTimeout;
  final void Function(String chunk)? onStdoutChunk;
  final void Function(String chunk)? onStderrChunk;
}

abstract interface class ProcessSupervisor {
  Future<ProcessResult> run(ProcessRunRequest request);
}

enum ProcessFailureKind {
  startTimeout,
  executionTimeout,
  launchFailure,
  terminationFailure,
  noOutput,
}

final class SupervisedProcessException implements Exception {
  const SupervisedProcessException({
    required this.kind,
    required this.diagnosticCode,
    required this.message,
  });

  final ProcessFailureKind kind;
  final String diagnosticCode;
  final String message;

  @override
  String toString() => '$diagnosticCode: $message';
}

/// The only production boundary that launches configured test processes.
final class LocalProcessSupervisor implements ProcessSupervisor {
  const LocalProcessSupervisor();

  @override
  Future<ProcessResult> run(ProcessRunRequest request) async {
    late final ToolInvocation prepared;
    try {
      prepared = prepareToolInvocation(
        request.executable,
        request.arguments,
        request.environment,
        runnerMode: request.runnerMode,
      );
    } on ToolInvocationException catch (error) {
      throw SupervisedProcessException(
        kind: ProcessFailureKind.launchFailure,
        diagnosticCode: error.diagnosticCode,
        message: error.message,
      );
    }
    final isBatch =
        Platform.isWindows &&
        (prepared.executable.toLowerCase().endsWith('.bat') ||
            prepared.executable.toLowerCase().endsWith('.cmd'));
    if (isBatch) {
      final unsafe = <String>[prepared.executable, ...prepared.arguments]
          .indexed
          .map((entry) => (index: entry.$1, value: entry.$2))
          .firstWhere(
            (entry) => RegExp(r'''[&|<>^%!"\r\n]''').hasMatch(entry.value),
            orElse: () => (index: -1, value: ''),
          );
      if (unsafe.index >= 0) {
        throw const SupervisedProcessException(
          kind: ProcessFailureKind.launchFailure,
          diagnosticCode: 'ZUKE-BATCH-UNSAFE-ARGUMENT',
          message:
              'batch runners cannot safely forward shell metacharacters; '
              'use a shell-free executable or remove the unsafe character',
        );
      }
    }
    final executable = isBatch ? 'cmd.exe' : prepared.executable;
    final arguments = isBatch
        ? ['/d', '/s', '/c', 'call', prepared.executable, ...prepared.arguments]
        : prepared.arguments;
    final environment = _normalizeEnvironment(prepared.environment);
    late final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: request.workingDirectory,
        environment: environment,
        runInShell: false,
      ).timeout(request.startupTimeout);
    } on TimeoutException {
      throw const SupervisedProcessException(
        kind: ProcessFailureKind.startTimeout,
        diagnosticCode: 'ZUKE-PROCESS-START-TIMEOUT',
        message: 'runner failed to start before the configured timeout',
      );
    } on ProcessException catch (error) {
      throw SupervisedProcessException(
        kind: ProcessFailureKind.launchFailure,
        diagnosticCode: 'ZUKE-PROCESS-LAUNCH-FAILED',
        message: error.message,
      );
    }

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    Timer? firstOutputTimer;
    final firstEvent = Completer<_FirstProcessEvent>();
    final rawExitCode = process.exitCode;
    final boundedExitCode = rawExitCode.timeout(request.executionTimeout);
    rawExitCode.then((_) {
      if (!firstEvent.isCompleted) {
        firstEvent.complete(_FirstProcessEvent.exit);
      }
    });
    if (request.firstOutputTimeout != null) {
      firstOutputTimer = Timer(request.firstOutputTimeout!, () {
        if (!firstEvent.isCompleted) {
          firstEvent.complete(_FirstProcessEvent.noOutput);
        }
      });
    }

    void onChunk(String chunk, StringBuffer buffer, void Function(String)? cb) {
      if (!firstEvent.isCompleted) {
        firstEvent.complete(_FirstProcessEvent.output);
        firstOutputTimer?.cancel();
        firstOutputTimer = null;
      }
      buffer.write(chunk);
      cb?.call(chunk);
    }

    final stdoutSubscription = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (chunk) {
            onChunk(chunk, stdoutBuffer, request.onStdoutChunk);
          },
          onError: (Object _, StackTrace __) {
            if (!stdoutDone.isCompleted) stdoutDone.complete();
          },
          onDone: () {
            if (!stdoutDone.isCompleted) stdoutDone.complete();
          },
        );
    final stderrSubscription = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (chunk) {
            onChunk(chunk, stderrBuffer, request.onStderrChunk);
          },
          onError: (Object _, StackTrace __) {
            if (!stderrDone.isCompleted) stderrDone.complete();
          },
          onDone: () {
            if (!stderrDone.isCompleted) stderrDone.complete();
          },
        );
    try {
      if (request.firstOutputTimeout != null) {
        final event = await Future.any([
          firstEvent.future,
          boundedExitCode.then((_) => _FirstProcessEvent.exit),
        ]);
        if (event == _FirstProcessEvent.noOutput) {
          await _terminateTree(process);
          await _awaitStreamDrain(stdoutDone.future, stderrDone.future);
          throw SupervisedProcessException(
            kind: ProcessFailureKind.noOutput,
            diagnosticCode: 'ZUKE-PROCESS-NO-OUTPUT',
            message:
                'runner produced no output within '
                '${request.firstOutputTimeout}',
          );
        }
      }
      final exitCode = await boundedExitCode;
      await _awaitStreamDrain(stdoutDone.future, stderrDone.future);
      return ProcessResult(
        process.pid,
        exitCode,
        stdoutBuffer.toString(),
        stderrBuffer.toString(),
      );
    } on TimeoutException {
      try {
        await _terminateTree(process);
        await _awaitStreamDrain(stdoutDone.future, stderrDone.future);
      } on SupervisedProcessException {
        rethrow;
      } catch (error) {
        throw SupervisedProcessException(
          kind: ProcessFailureKind.terminationFailure,
          diagnosticCode: 'ZUKE-PROCESS-TERMINATION-FAILED',
          message: '$error',
        );
      }
      throw SupervisedProcessException(
        kind: ProcessFailureKind.executionTimeout,
        diagnosticCode: 'ZUKE-TEST-TIMEOUT',
        message: 'runner timed out after ${request.executionTimeout}',
      );
    } finally {
      firstOutputTimer?.cancel();
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
    }
  }

  Future<void> _terminateTree(Process process) async {
    if (Platform.isWindows) {
      final result = await Process.run('taskkill.exe', [
        '/PID',
        '${process.pid}',
        '/T',
        '/F',
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0 && !await _hasExited(process)) {
        Process.killPid(process.pid);
      }
    } else {
      final descendants = await Process.run('ps', ['-eo', 'pid=,ppid=']);
      if (descendants.exitCode != 0) {
        throw const SupervisedProcessException(
          kind: ProcessFailureKind.terminationFailure,
          diagnosticCode: 'ZUKE-PROCESS-TERMINATION-FAILED',
          message: 'could not enumerate POSIX child processes',
        );
      }
      final children = <int, List<int>>{};
      for (final line in descendants.stdout.toString().split('\n')) {
        final fields = line.trim().split(RegExp(r'\s+'));
        if (fields.length < 2) continue;
        final child = int.tryParse(fields[0]);
        final parent = int.tryParse(fields[1]);
        if (child != null && parent != null) {
          children.putIfAbsent(parent, () => []).add(child);
        }
      }
      Future<void> killChildren(int parent) async {
        for (final child in children[parent] ?? const <int>[]) {
          await killChildren(child);
          Process.killPid(child, ProcessSignal.sigkill);
        }
      }

      await killChildren(process.pid);
      Process.killPid(process.pid, ProcessSignal.sigkill);
    }
    if (!await _waitForExit(process, const Duration(seconds: 5))) {
      throw const SupervisedProcessException(
        kind: ProcessFailureKind.terminationFailure,
        diagnosticCode: 'ZUKE-PROCESS-TERMINATION-FAILED',
        message: 'runner remained alive after tree termination',
      );
    }
  }

  Future<void> _awaitStreamDrain(
    Future<void> stdoutDone,
    Future<void> stderrDone,
  ) async {
    try {
      await Future.wait([
        stdoutDone,
        stderrDone,
      ]).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // The process has already exited or been terminated.  The subscriptions
      // are cancelled by the caller's finally block if a pipe remains open.
    }
  }

  Future<bool> _hasExited(Process process) =>
      _waitForExit(process, const Duration(milliseconds: 1));

  Future<bool> _waitForExit(Process process, Duration timeout) async {
    try {
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Map<String, String> _normalizeEnvironment(Map<String, String> input) {
    if (!Platform.isWindows) return Map<String, String>.from(input);
    final normalized = <String, String>{};
    final keys = <String, String>{};
    for (final entry in input.entries) {
      final folded = entry.key.toLowerCase();
      final previous = keys[folded];
      if (previous != null) normalized.remove(previous);
      keys[folded] = entry.key;
      normalized[entry.key] = entry.value;
    }
    return normalized;
  }
}

enum _FirstProcessEvent { output, exit, noOutput }
