import 'dart:convert';
import 'dart:io';

import 'package:zuke_cli/zuke_cli.dart';

/// In-process stdout/stderr buffer implementation for isolated CLI testing.
final class TestStdout implements Stdout {
  final StringBuffer buffer;

  TestStdout(this.buffer);

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding encoding) {}

  @override
  bool get hasTerminal => false;

  @override
  int get terminalColumns => 80;

  @override
  int get terminalLines => 24;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  String get lineTerminator => '\n';

  @override
  set lineTerminator(String lineTerminator) {}

  @override
  void writeln([Object? object = '']) {
    buffer.writeln(object ?? '');
  }

  @override
  void write(Object? object) {
    buffer.write(object ?? '');
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    buffer.write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    buffer.writeCharCode(charCode);
  }

  @override
  void add(List<int> data) {
    buffer.write(utf8.decode(data, allowMalformed: true));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    buffer.write('ERROR: $error\n');
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs [ZukeCli] in-process using isolated [IOOverrides] stdout/stderr streams.
Future<ProcessResult> runInProcessCli(List<String> args) async {
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  late int exitCode;

  await IOOverrides.runZoned(
    () async {
      exitCode = await ZukeCli().run(args);
    },
    stdout: () => TestStdout(stdoutBuffer),
    stderr: () => TestStdout(stderrBuffer),
  );

  return ProcessResult(
    0,
    exitCode,
    stdoutBuffer.toString(),
    stderrBuffer.toString(),
  );
}

/// Finds the repository workspace even when a package test is launched with
/// the package directory as its current working directory.
Directory zukeWorkspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(
      '${current.path}${Platform.pathSeparator}pubspec.yaml',
    );
    if (pubspec.existsSync() &&
        RegExp(
          r'^workspace:\s*$',
          multiLine: true,
        ).hasMatch(pubspec.readAsStringSync())) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError(
        'Unable to locate the Dart workspace root from ${Directory.current.path}',
      );
    }
    current = parent;
  }
}
