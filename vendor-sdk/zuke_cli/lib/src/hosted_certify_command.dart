import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';

Future<int> runHostedCertification(ArgResults cmd) async {
  final root = cmd['root'] as String? ?? Directory.current.path;
  final platform = cmd['platform'] as String?;
  final host = cmd['host'] as String?;
  if (platform == null || host == null) {
    stderr.writeln(
      'certify hosted requires --platform <linux|windows> and '
      '--host <dart|flutter>',
    );
    return 2;
  }
  final script = File(
    '$root${Platform.pathSeparator}tool${Platform.pathSeparator}'
    'check_hosted_consumer.dart',
  );
  if (!script.existsSync()) {
    stderr.writeln(
      'Hosted certification must run from a Zuke framework checkout.',
    );
    return 2;
  }
  final arguments = <String>[
    '--suppress-analytics',
    'run',
    script.path,
    '--platform',
    platform,
    '--host',
    host,
    if (cmd['flutter-version'] case final String version) ...[
      '--flutter-version',
      version,
    ],
    if (cmd['output'] case final String output) ...['--output', output],
    if (cmd['keep-fixture'] as bool? ?? false) '--keep-fixture',
  ];
  final process = await Process.start(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: root,
    runInShell: Platform.isWindows,
  );
  await Future.wait([
    stdout.addStream(process.stdout),
    stderr.addStream(process.stderr),
  ]);
  return process.exitCode;
}
