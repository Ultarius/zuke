import 'dart:io';

import 'package:args/args.dart';

import 'cli_parser.dart';
import 'doctor_command.dart';
import 'tooling/analyzer_sdk.dart';

Future<int> runAnalyze(
  ArgResults command, {
  Future<int> Function(ArgResults) doctor = _repairExistingCache,
  Future<int> Function(String, List<String>) analyze = _dartAnalyze,
}) async {
  final root = command['root'] as String? ?? Directory.current.path;
  final repairCommand = buildZukeArgParser().parse([
    'doctor',
    '--root',
    root,
    '--fix',
    '--current-context',
  ]).command!;
  final repaired = await doctor(repairCommand);
  if (repaired != 0) return repaired;
  return analyze(root, command.rest);
}

/// Repairs this context's cache entry when it has one. A first analysis has none
/// yet, and the `dart analyze` that follows is what creates it.
Future<int> _repairExistingCache(ArgResults command) =>
    runDoctor(command, requireContextEntry: false);

Future<int> _dartAnalyze(String root, List<String> arguments) async {
  final process = await Process.start(
    resolveDartExecutable(),
    ['analyze', ...arguments],
    workingDirectory: root,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}
