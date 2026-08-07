import 'dart:convert';
import 'dart:io';

String? formattedSourceFromJson(String output) {
  try {
    final decoded = jsonDecode(output);
    return decoded is Map && decoded['source'] is String
        ? decoded['source'] as String
        : null;
  } on FormatException {
    return null;
  }
}

bool formattedSourceMatches(String original, String formatterOutput) {
  final formatted = formattedSourceFromJson(formatterOutput);
  if (formatted == null) return false;
  String normalize(String value) =>
      value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return normalize(original) == normalize(formatted);
}

/// Checks only repository-owned Dart files. `dart format .` recursively walks
/// package caches and generated state, making a source-format gate depend on
/// local `.dart_tool` size and filesystem latency.
Future<void> main() async {
  final listed = await Process.run('git', [
    '-c',
    'safe.directory=${Directory.current.absolute.path.replaceAll('\\', '/')}',
    'ls-files',
    '-z',
    '--',
    '*.dart',
  ]);
  if (listed.exitCode != 0) {
    stderr.write(listed.stderr);
    exitCode = listed.exitCode;
    return;
  }
  final files = listed.stdout
      .toString()
      .split('\u0000')
      .where((path) => path.isNotEmpty && File(path).existsSync())
      .toList(growable: false);
  if (files.isEmpty) return;
  // Keep below Windows' command-line limit while avoiding one process per
  // package. The formatter discovers each file's language version itself.
  const maximumArgumentsLength = 20000;
  final batches = <List<String>>[];
  var batch = <String>[];
  var length = 0;
  for (final path in files) {
    if (batch.isNotEmpty && length + path.length + 1 > maximumArgumentsLength) {
      batches.add(batch);
      batch = <String>[];
      length = 0;
    }
    batch.add(path);
    length += path.length + 1;
  }
  if (batch.isNotEmpty) batches.add(batch);

  for (final paths in batches) {
    final result = await Process.run(Platform.resolvedExecutable, [
      '--suppress-analytics',
      'format',
      '--output=none',
      '--set-exit-if-changed',
      ...paths,
    ]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode == 0) continue;

    // Do not rewrite tracked files to decide whether formatting differs. Some
    // Windows SDK releases report LF-only files as changed despite producing
    // identical logical source, so compare the formatter's JSON source output
    // after normalising line endings. This slow path runs only after a batch
    // reports a change.
    final changed = <String>[];
    for (final path in paths) {
      final shown = await Process.run(Platform.resolvedExecutable, [
        '--suppress-analytics',
        'format',
        '--output=json',
        path,
      ]);
      if (shown.exitCode != 0) {
        stderr.write(shown.stderr);
        exitCode = shown.exitCode;
        continue;
      }
      if (formattedSourceFromJson(shown.stdout.toString()) == null) {
        stderr.writeln('Dart formatter returned invalid JSON for $path');
        exitCode = 1;
        continue;
      }
      final source = File(path).readAsStringSync();
      if (!formattedSourceMatches(source, shown.stdout.toString())) {
        changed.add(path);
      }
    }
    if (changed.isNotEmpty) {
      for (final path in changed) {
        stderr.writeln('Unformatted Dart source: $path');
      }
      exitCode = result.exitCode;
    }
  }
}
