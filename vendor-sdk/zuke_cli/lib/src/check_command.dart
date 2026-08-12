import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'generate_command.dart';
import 'lock_command.dart';
import 'report_command.dart';
import 'validate_command.dart';
import 'command_result.dart';

/// Runs the complete verification pipeline for one or more workspaces.
///
/// Unlike the original implementation this composes stages directly.  Nested
/// commands are run in workspace-local IO zones, so JSON mode has exactly one
/// stdout document and concurrent roots cannot interleave their logs.
class CheckCommand {
  final ArgResults args;
  final Future<int> Function(ArgResults args) testRunner;

  CheckCommand(this.args, {required this.testRunner});

  Future<int> execute() async {
    final requested = args['root'] as List<String>;
    if (requested.isEmpty) throw const FormatException('check requires --root');
    final roots = <String>[];
    for (final value in requested) {
      final root = _normalizeRoot(value);
      if (!roots.contains(root)) roots.add(root);
    }
    final jobs = _jobs(args['jobs'] as String? ?? '');
    final profile = args['profile'] as String? ?? 'pullRequest';
    final json = (args['format'] as String? ?? 'text') == 'json';
    final summaryFile = args['summary-file'] as String?;
    final results = await _runBounded(
      roots,
      jobs: jobs < roots.length ? jobs : roots.length,
      run: (root) => _verify(
        root,
        profile: profile,
        runnerMode: args['runner-mode'] as String?,
      ),
    );
    results.sort(
      (a, b) => roots.indexOf(a.root).compareTo(roots.indexOf(b.root)),
    );
    final succeeded = results.every((result) => result.status == 'passed');
    if (json) {
      final commandResult = CommandResult(
        command: 'check',
        stage: 'check',
        exitCode: succeeded ? 0 : 1,
        status: succeeded ? CommandStatus.passed : CommandStatus.failed,
        eligible: succeeded,
        diagnostics: [
          for (final workspace in results)
            for (final stage in workspace.stages)
              if (stage.status == 'failed')
                gateDiagnostic(
                  stage: stage.name,
                  message:
                      'Check stage ${stage.name} failed for ${workspace.root}.',
                  profile: profile,
                ),
        ],
      );
      final payload = {
        ...commandResult.toJson(),
        'profile': profile,
        'workspaces': results.map(_safeWorkspaceJson).toList(),
      };
      final encoded = jsonEncode(payload);
      stdout.writeln(encoded);
      writeCommandSummary(summaryFile, commandResult);
    } else {
      for (final result in results) {
        stdout.writeln('\nCheck [${result.root}]: ${result.status}');
        for (final stage in result.stages) {
          stdout.writeln('  ${stage.name}: ${stage.status}');
          if (stage.stdout.isNotEmpty) {
            stdout.write(_indent(stage.stdout));
          }
          if (stage.stderr.isNotEmpty) {
            stderr.write(_indent(stage.stderr));
          }
        }
      }
    }
    return succeeded ? 0 : 1;
  }

  Map<String, Object?> _safeWorkspaceJson(_WorkspaceResult result) => {
    'root': result.root,
    'status': result.status,
    'stages': {
      for (final stage in result.stages) stage.name: {'status': stage.status},
    },
  };

  Future<_WorkspaceResult> _verify(
    String root, {
    required String profile,
    String? runnerMode,
  }) async {
    final stages = <_StageResult>[];
    WorkspaceDiscoveryResult initial;
    try {
      initial = WorkspaceDiscovery().discover(root);
    } catch (error) {
      stages.add(_StageResult.failed('generate', stderr: '$error\n'));
      stages.addAll(_skipped(['test', 'validate', 'lock', 'inputStability']));
      stages.add(await _report(root));
      return _WorkspaceResult(root, stages);
    }

    final generated = await _stage(
      'generate',
      () => GenerateCommand(_generateArgs(root)).execute(),
    );
    stages.add(generated);
    if (generated.status == 'passed') {
      final tested = await _stage(
        'test',
        () => testRunner(_testArgs(root, profile, runnerMode: runnerMode)),
      );
      stages.add(tested);
      if (tested.status == 'passed') {
        final stable = _inputsStable(initial, root);
        stages.add(stable);
        if (stable.status == 'passed') {
          final validated = await _stage(
            'validate',
            () => ValidateCommand(_validateArgs(root, profile)).execute(),
          );
          stages.add(validated);
          if (validated.status == 'passed') {
            stages.add(await _checkLock(root, profile));
          } else {
            stages.addAll(_skipped(['lock']));
          }
        } else {
          stages.addAll(_skipped(['validate', 'lock']));
        }
      } else {
        stages.addAll(_skipped(['inputStability', 'validate', 'lock']));
      }
    } else {
      stages.addAll(_skipped(['test', 'inputStability', 'validate', 'lock']));
    }
    // Reports are observational and remain available even when eligibility
    // stages fail, which makes failed checks debuggable in CI artifacts.
    stages.add(await _report(root));
    return _WorkspaceResult(root, stages);
  }

  Future<_StageResult> _report(String root) =>
      _stage('report', () => ReportCommand(_reportArgs(root)).execute());

  _StageResult _inputsStable(WorkspaceDiscoveryResult initial, String root) {
    try {
      final refreshed = WorkspaceDiscovery().discover(root);
      if (_sameInputs(initial.inputContents, refreshed.inputContents)) {
        return _StageResult.passed('inputStability');
      }
      return _StageResult.failed(
        'inputStability',
        stderr:
            'Specification inputs changed while configured runners executed.\n',
      );
    } catch (error) {
      return _StageResult.failed('inputStability', stderr: '$error\n');
    }
  }
}

bool _sameInputs(Map<String, String> left, Map<String, String> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

String _normalizeRoot(String root) {
  final directory = Directory(root).absolute;
  try {
    return directory.resolveSymbolicLinksSync();
  } on FileSystemException {
    return directory.path;
  }
}

int _jobs(String raw) {
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 1) {
    throw const FormatException('check --jobs must be a positive integer');
  }
  return parsed;
}

ArgResults _generateArgs(String root) =>
    (ArgParser()
          ..addOption('root')
          ..addFlag('check')
          ..addOption('output')
          ..addFlag('quiet'))
        .parse(['--root', root, '--check', '--quiet']);

ArgResults _testArgs(String root, String profile, {String? runnerMode}) =>
    (ArgParser()
          ..addOption('root')
          ..addOption('profile')
          ..addOption('format')
          ..addOption('runner-mode')
          ..addFlag('quiet'))
        .parse([
          '--root',
          root,
          '--profile',
          profile,
          '--format',
          'text',
          '--quiet',
          if (runnerMode != null) ...['--runner-mode', runnerMode],
        ]);

ArgResults _validateArgs(String root, String profile) =>
    (ArgParser()
          ..addOption('root')
          ..addOption('profile')
          ..addOption('format')
          ..addFlag('quiet'))
        .parse([
          '--root',
          root,
          '--profile',
          profile,
          '--format',
          'text',
          '--quiet',
        ]);

ArgResults _lockArgs(String root, String profile, {required bool check}) =>
    (ArgParser()
          ..addOption('root')
          ..addOption('profile')
          ..addFlag('check')
          ..addFlag('quiet'))
        .parse([
          '--root',
          root,
          '--profile',
          profile,
          if (check) '--check',
          '--quiet',
        ]);

ArgResults _reportArgs(String root) =>
    (ArgParser()
          ..addOption('root')
          ..addOption('output')
          ..addFlag('quiet'))
        .parse(['--root', root, '--quiet']);

Future<_StageResult> _stage(String name, Future<int> Function() action) async {
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  late int code;
  try {
    code = await IOOverrides.runZoned(
      action,
      stdout: () => _BufferStdout(stdoutBuffer),
      stderr: () => _BufferStdout(stderrBuffer),
    );
  } catch (error) {
    stderrBuffer.writeln(error);
    code = 1;
  }
  return _StageResult(
    name,
    code == 0 ? 'passed' : 'failed',
    stdoutBuffer.toString(),
    stderrBuffer.toString(),
  );
}

/// A configured runner intentionally replaces profile evidence. Lock output
Future<_StageResult> _checkLock(String root, String profile) async => _stage(
  'lock',
  () => LockCommand(_lockArgs(root, profile, check: true)).execute(),
);

List<_StageResult> _skipped(List<String> names) =>
    names.map((name) => _StageResult(name, 'skipped', '', '')).toList();

Future<List<_WorkspaceResult>> _runBounded(
  List<String> roots, {
  required int jobs,
  required Future<_WorkspaceResult> Function(String root) run,
}) async {
  final results = <_WorkspaceResult>[];
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= roots.length) return;
      results.add(await run(roots[index]));
    }
  }

  await Future.wait(List.generate(jobs, (_) => worker()));
  return results;
}

String _indent(String text) => text
    .split(RegExp(r'\r?\n'))
    .where((line) => line.isNotEmpty)
    .map((line) => '    $line\n')
    .join();

final class _WorkspaceResult {
  final String root;
  final List<_StageResult> stages;
  const _WorkspaceResult(this.root, this.stages);

  String get status =>
      stages.every(
        (stage) => stage.status == 'passed' || stage.status == 'skipped',
      )
      ? 'passed'
      : 'failed';

  Map<String, Object?> toJson() => {
    'root': root,
    'status': status,
    'stages': {for (final stage in stages) stage.name: stage.toJson()},
  };
}

final class _StageResult {
  final String name;
  final String status;
  final String stdout;
  final String stderr;
  const _StageResult(this.name, this.status, this.stdout, this.stderr);
  factory _StageResult.passed(String name) =>
      _StageResult(name, 'passed', '', '');
  factory _StageResult.failed(String name, {required String stderr}) =>
      _StageResult(name, 'failed', '', stderr);
  Map<String, Object?> toJson() => {
    'status': status,
    if (stdout.isNotEmpty) 'stdout': stdout,
    if (stderr.isNotEmpty) 'stderr': stderr,
  };
}

final class _BufferStdout implements Stdout {
  final StringBuffer buffer;
  _BufferStdout(this.buffer);
  @override
  Encoding encoding = utf8;
  @override
  bool get hasTerminal => false;
  @override
  bool get supportsAnsiEscapes => false;
  @override
  int get terminalColumns => 0;
  @override
  int get terminalLines => 0;
  @override
  IOSink get nonBlocking => this;
  @override
  String lineTerminator = '\n';
  @override
  Future<void> get done async {}
  @override
  void add(List<int> data) => buffer.write(encoding.decode(data));
  @override
  void addError(Object error, [StackTrace? stackTrace]) => buffer.write(error);
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<void> close() async {}
  @override
  Future<void> flush() async {}
  @override
  void write(Object? object) => buffer.write(object);
  @override
  void writeln([Object? object = '']) => buffer.writeln(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => buffer.writeCharCode(charCode);
}
