import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';
import 'package:zuke_core/zuke_core.dart';

import 'release_matrix.dart';
import 'src/hosted_consumer_fixture.dart';

Future<void> main(List<String> args) => runHostedConsumerCertification(args);

Future<void> runHostedConsumerCertification(List<String> args) async {
  final options = _Options.parse(args);
  if (options.help) {
    _Options.printUsage();
    return;
  }
  final frameworkRoot = Directory.current.absolute;
  final matrix = readReleaseMatrix(frameworkRoot);
  if (!matrix.operatingSystems.contains(options.platform)) {
    throw FormatException(
      'Platform ' + options.platform + ' is not declared in the release matrix',
    );
  }

  final fixture = await Directory.systemTemp.createTemp(
    'zuke-hosted-consumer-' + options.platform + '-',
  );
  final results = <Map<String, Object?>>[];
  final hostedPackages = matrix.publicPackageVersions.keys.toList();
  final useFlutter = _flutterAvailable();
  final violations = <String>[];
  if (!useFlutter &&
      hostedPackages.any((package) => _requiresFlutter(frameworkRoot, package))) {
    violations.add('Flutter is required by the published package tuple.');
  }

  try {
    HostedConsumerFixture(
      templateRoot: Directory(
        frameworkRoot.path + Platform.pathSeparator + 'tool' +
            Platform.pathSeparator + 'fixtures' + Platform.pathSeparator +
            'hosted_consumer' + Platform.pathSeparator + 'template',
      ),
      destination: fixture,
      matrix: matrix,
      hostedPackages: hostedPackages,
      useFlutter: useFlutter,
    ).render();

    final pubGet = await _run(fixture, _dartCommand(['pub', 'get']));
    results.add(pubGet.toJson());
    if (pubGet.exitCode == 0) {
      try {
        _assertCleanResolution(fixture, hostedPackages, matrix);
      } on Object catch (error) {
        violations.add(error.toString());
      }
    }

    final summaryPath = File(
      fixture.path + Platform.pathSeparator + 'generated' +
          Platform.pathSeparator + 'gate-summary.json',
    );
    final artifactDirectory = Directory(
      fixture.path + Platform.pathSeparator + 'generated' +
          Platform.pathSeparator + 'safe-artifacts',
    );
    final commands = <List<String>>[
      _zukeCommand(['doctor', '--format', 'json']),
      _zukeCommand(['generate']),
      _zukeCommand(['generate', '--check']),
      _dartCommand(['test']),
      for (final profile in const ['pullRequest', 'merge', 'release', 'nightly'])
        _zukeCommand(['test', '--profile', profile, '--format', 'json']),
      for (final profile in const ['pullRequest', 'merge', 'release', 'nightly'])
        _zukeCommand(['validate', '--profile', profile, '--format', 'json']),
      _zukeCommand(['lock', '--all-profiles']),
      _zukeCommand(['lock', '--all-profiles', '--check']),
      _zukeCommand([
        'gate',
        '--all-profiles',
        '--format',
        'json',
        '--summary-file',
        summaryPath.path,
        '--artifact-dir',
        artifactDirectory.path,
      ]),
    ];
    for (final command in commands) {
      final result = await _run(fixture, command);
      results.add(result.toJson());
    }

    try {
      _assertLocks(fixture);
    } on Object catch (error) {
      violations.add(error.toString());
    }
    final gateResult = _readCommandResult(summaryPath);
    final artifactResult = _readCommandResult(
      File(artifactDirectory.path + Platform.pathSeparator + 'command-result.json'),
    );
    if (gateResult == null || artifactResult == null) {
      violations.add(
        'Gate summary and safe artifact must both be current command results.',
      );
    } else if (!_sameJson(gateResult.toJson(), artifactResult.toJson())) {
      violations.add('Gate summary and safe artifact command results differ.');
    }
    final gateRuns = results.where(
      (result) => result['command'] is List &&
          (result['command'] as List).contains('gate'),
    );
    final stdoutGate = gateRuns.isEmpty ? null : gateRuns.last['commandResult'];
    if (stdoutGate is Map && gateResult != null &&
        !_sameJson(stdoutGate, gateResult.toJson())) {
      violations.add('Gate stdout and summary command results differ.');
    }

    final passed = violations.isEmpty &&
        results.every((result) => result['exitCode'] == 0) &&
        (gateResult?.succeeded ?? false);
    final report = <String, Object?>{
      'kind': 'zuke.hosted-consumer-certification',
      'platform': options.platform,
      'passed': passed,
      'sdk': {
        'dart': Platform.version,
        'flutter': _flutterVersion(),
      },
      'packageVersions': matrix.publicPackageVersions,
      'compatibilityIds': matrix.compatibilityIds,
      'resolvedPackages': _resolvedTuple(fixture),
      'lockDigests': _lockDigests(fixture),
      'violations': violations,
      'commands': results,
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(report) + '\n';
    if (options.output != null) {
      final output = File(options.output!);
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(encoded);
    }
    stdout.write(encoded);
    if (!passed) exitCode = 1;
  } finally {
    if (!options.keepFixture && fixture.existsSync()) {
      fixture.deleteSync(recursive: true);
    }
  }
}

List<String> _dartCommand(List<String> command) => [
  '--suppress-analytics',
  ...command,
];

List<String> _zukeCommand(List<String> command) => [
  '--suppress-analytics',
  'run',
  'zuke_cli:zuke',
  ...command,
];

Future<_RunResult> _run(Directory root, List<String> command) async {
  final executable = command.first == 'flutter'
      ? 'flutter'
      : Platform.resolvedExecutable;
  final arguments = command.first == 'flutter' ? command.sublist(1) : command;
  final process = await Process.run(
    executable,
    arguments,
    workingDirectory: root.path,
    runInShell: Platform.isWindows,
    environment: {
      ...Platform.environment,
      'PUB_ENVIRONMENT': 'zuke_hosted_consumer_certification',
    },
  );
  final stdoutText = process.stdout.toString();
  final stderrText = process.stderr.toString();
  CommandResult? structured;
  for (final line in stdoutText.split('\n').reversed) {
    final value = line.trim();
    if (!value.startsWith('{')) continue;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        structured = CommandResult.fromJson(
          Map<Object?, Object?>.from(decoded),
        );
        break;
      }
    } on Object {
      // Reports never include raw process output.
    }
  }
  return _RunResult(
    command: [executable, ...arguments],
    exitCode: process.exitCode,
    commandResult: structured,
    stdoutPresent: stdoutText.isNotEmpty,
    stderrPresent: stderrText.isNotEmpty,
  );
}

bool _flutterAvailable() {
  try {
    return Process.runSync(
      'flutter',
      const ['--suppress-analytics', '--version'],
      runInShell: Platform.isWindows,
    ).exitCode == 0;
  } on Object {
    return false;
  }
}

String? _flutterVersion() {
  try {
    final result = Process.runSync(
      'flutter',
      const ['--suppress-analytics', '--version'],
      runInShell: Platform.isWindows,
    );
    return result.exitCode == 0
        ? result.stdout.toString().split('\n').first
        : null;
  } on Object {
    return null;
  }
}

bool _requiresFlutter(Directory root, String package) {
  final pubspec = File(
    root.path + Platform.pathSeparator + 'vendor-sdk' +
        Platform.pathSeparator + package + Platform.pathSeparator + 'pubspec.yaml',
  );
  return pubspec.existsSync() &&
      RegExp(
        r'(^|\n)\s+(?:flutter|flutter_test):\s*\n\s+sdk:\s+flutter',
        multiLine: true,
      ).hasMatch(pubspec.readAsStringSync());
}

void _assertCleanResolution(
  Directory root,
  List<String> expectedPackages,
  ReleaseMatrix matrix,
) {
  final pubspec = File(
    root.path + Platform.pathSeparator + 'pubspec.yaml',
  ).readAsStringSync();
  if (pubspec.contains('dependency_overrides:') ||
      pubspec.contains('workspace:') ||
      RegExp(r'(^|\n)\s+(path|git):', multiLine: true).hasMatch(pubspec)) {
    throw const FormatException(
      'Hosted consumer contains workspace inheritance, path, Git, or override configuration',
    );
  }
  final lock = File(root.path + Platform.pathSeparator + 'pubspec.lock');
  if (!lock.existsSync()) {
    throw const FormatException('Hosted consumer did not produce pubspec.lock');
  }
  final decoded = loadYaml(lock.readAsStringSync());
  final packages = decoded is Map ? decoded['packages'] : null;
  if (packages is! Map) {
    throw const FormatException('Hosted consumer pubspec.lock is malformed');
  }
  for (final entry in packages.entries) {
    final package = entry.value;
    if (package is! Map ||
        (package['source'] != 'hosted' && package['source'] != 'sdk')) {
      throw FormatException(
        'Resolved package ' + entry.key.toString() +
            ' is not hosted or SDK-provided',
      );
    }
  }
  for (final name in expectedPackages) {
    final entry = packages[name];
    final expected = matrix.packages[name]!.version;
    if (entry is! Map || entry['source'] != 'hosted' ||
        entry['version'] != expected) {
      throw FormatException(
        'Resolved ' + name + ' does not equal hosted matrix version ' + expected,
      );
    }
  }
}

Map<String, String> _resolvedTuple(Directory root) {
  final lock = File(root.path + Platform.pathSeparator + 'pubspec.lock');
  if (!lock.existsSync()) return {};
  final decoded = loadYaml(lock.readAsStringSync());
  final packages = decoded is Map ? decoded['packages'] : null;
  if (packages is! Map) return {};
  return {
    for (final entry in packages.entries)
      if (entry.key is String && entry.value is Map)
        entry.key as String:
            entry.value['source'].toString() + ':' +
            entry.value['version'].toString(),
  };
}

Map<String, String> _lockDigests(Directory root) {
  final result = <String, String>{};
  for (final profile in const ['pullRequest', 'merge', 'release', 'nightly']) {
    final file = File(
      root.path + Platform.pathSeparator + 'assurance' +
          Platform.pathSeparator + 'locks' + Platform.pathSeparator +
          profile + '.lock.json',
    );
    if (file.existsSync()) {
      result[profile] = sha256.convert(file.readAsBytesSync()).toString();
    }
  }
  return result;
}

void _assertLocks(Directory root) {
  for (final profile in const ['pullRequest', 'merge', 'release', 'nightly']) {
    final path = root.path + Platform.pathSeparator + 'assurance' +
        Platform.pathSeparator + 'locks' + Platform.pathSeparator +
        profile + '.lock.json';
    if (!File(path).existsSync()) {
      throw StateError('Missing generated profile lock: ' + path);
    }
  }
}

CommandResult? _readCommandResult(File file) {
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return null;
    return CommandResult.fromJson(Map<Object?, Object?>.from(decoded));
  } on Object {
    return null;
  }
}

bool _sameJson(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

final class _RunResult {
  const _RunResult({
    required this.command,
    required this.exitCode,
    required this.commandResult,
    required this.stdoutPresent,
    required this.stderrPresent,
  });

  final List<String> command;
  final int exitCode;
  final CommandResult? commandResult;
  final bool stdoutPresent;
  final bool stderrPresent;

  Map<String, Object?> toJson() => {
    'command': command,
    'exitCode': exitCode,
    'status': exitCode == 0 ? 'passed' : 'failed',
    'stdoutPresent': stdoutPresent,
    'stderrPresent': stderrPresent,
    if (commandResult != null) 'commandResult': commandResult!.toJson(),
  };
}

final class _Options {
  const _Options({
    required this.platform,
    this.output,
    this.keepFixture = false,
    this.help = false,
  });

  final String platform;
  final String? output;
  final bool keepFixture;
  final bool help;

  static _Options parse(List<String> args) {
    if (args.contains('--help') || args.contains('-h')) {
      return const _Options(platform: 'linux', help: true);
    }
    String? platform;
    String? output;
    var keepFixture = false;
    for (var index = 0; index < args.length; index++) {
      switch (args[index]) {
        case '--platform':
          if (++index >= args.length) {
            throw const FormatException('--platform requires a value');
          }
          platform = args[index];
        case '--output':
          if (++index >= args.length) {
            throw const FormatException('--output requires a value');
          }
          output = args[index];
        case '--keep-fixture':
          keepFixture = true;
        default:
          throw FormatException('Unknown option: ' + args[index]);
      }
    }
    if (platform == null || !const {'linux', 'windows'}.contains(platform)) {
      throw const FormatException('--platform must be linux or windows');
    }
    return _Options(
      platform: platform,
      output: output,
      keepFixture: keepFixture,
    );
  }

  static void printUsage() {
    stdout.writeln(
      'dart run tool/check_hosted_consumer.dart '
      '--platform <linux|windows> [--output <json>] [--keep-fixture]',
    );
  }
}
