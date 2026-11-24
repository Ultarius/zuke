import 'tool_invocation.dart';

const _runnerOptionsWithValues = <String>{
  '--dart-define',
  '--dart-define-from-file',
  '--device-id',
  '--enable-experiment',
  '--flavor',
  '--packages',
  '--target',
  '--target-platform',
  '--verbosity',
  '--web-renderer',
  '-d',
  '-t',
};

/// Builds the argv for one configured runner.
///
/// Coverage instrumentation slows a suite down, so it stays opt-in: only the
/// CI step that reads `coverage/` should pass `--coverage`. Flutter takes
/// `--coverage` and writes `coverage/lcov.info`; `dart test` requires the
/// destination directory explicitly.
///
/// A `setup` runner (`flutter pub get`, `dart analyze`) rejects unknown
/// flags, so coverage is only ever appended when the runner's primary command
/// is `test` — for both the Flutter and the Dart tool.
///
/// [runnerPrimaryCommand] also encodes what the `dart`/`flutter` CLIs accept,
/// which `tool_invocation.dart` holds for the launch path. They are deliberately
/// not unified: the failure mode here is benign (coverage is simply not
/// appended), while sharing it would couple runner argv to tool launching.
List<String> buildRunnerArguments(
  String executable,
  List<String> configured, {
  required bool coverage,
  bool setupRunner = false,
}) {
  final isDart = isDartTool(executable);
  var base = configured;
  if (coverage &&
      !setupRunner &&
      runnerPrimaryCommand(base) == 'test' &&
      !base.any((argument) => argument.startsWith('--coverage'))) {
    if (isFlutterTool(executable)) {
      base = [...base, '--coverage'];
    } else if (isDart) {
      base = [...base, '--coverage=coverage'];
    }
  }
  if (isDart && !base.contains('--disable-dart-dev')) {
    return [
      '--disable-dart-dev',
      if (!base.contains('--suppress-analytics')) '--suppress-analytics',
      ...base,
    ];
  }
  return base;
}

/// The runner's primary command, or null when it declares no subcommand.
///
/// Skips equals-style flags and known value-taking Dart/Flutter global options
/// to locate the first non-option command token.
String? runnerPrimaryCommand(List<String> configured) {
  for (var index = 0; index < configured.length; index++) {
    final argument = configured[index];
    if (argument.startsWith('-')) {
      if (!argument.contains('=') &&
          _runnerOptionsWithValues.contains(argument)) {
        index++;
      }
      continue;
    }
    return argument;
  }
  return null;
}
