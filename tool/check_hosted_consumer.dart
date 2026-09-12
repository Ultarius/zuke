import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';
import 'package:zuke_cli/src/command_result.dart';
import 'package:zuke_core/zuke_core.dart';

import 'release_matrix.dart';
import 'src/hosted_dependency_graph.dart';
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

  final flutterVersion = options.host == 'flutter' ? _flutterVersion() : null;
  if (options.host == 'flutter') {
    if (!_flutterAvailable()) {
      throw const ProcessException(
        'flutter',
        ['--version'],
        'Flutter is required for the Flutter hosted capsule.',
        69,
      );
    }
    final expected =
        options.flutterVersion ?? matrix.flutterCertification.current;
    if (expected.isNotEmpty &&
        (flutterVersion == null || !flutterVersion.contains(expected))) {
      throw FormatException(
        'Installed Flutter does not match certified version $expected: '
        '${flutterVersion ?? 'unavailable'}',
      );
    }
  }

  final fixture = await Directory.systemTemp.createTemp(
    'zuke-hosted-consumer-${options.host}-${options.platform}-',
  );
  final certHome = await Directory.systemTemp.createTemp(
    'zuke-hosted-cert-home-',
  );
  final certCache = await Directory.systemTemp.createTemp(
    'zuke-hosted-cert-cache-',
  );
  final results = <Map<String, Object?>>[];
  // Keep the capsule minimal: the CLI is certification tooling and belongs
  // in dev_dependencies, while only the host runner and its public runtime
  // surface belong in the application dependency graph.
  final hostedPackages = const ['zuke_cli'];
  final requiredPackages = <String>{
    'zuke',
    'zuke_annotations',
    'zuke_core',
    'zuke_frontend',
    'zuke_cli',
    options.host == 'flutter' ? 'zuke_runner_flutter' : 'zuke_runner',
  };
  final violations = <String>[];

  try {
    if (_isInside(fixture, frameworkRoot) || isInsidePubWorkspace(fixture)) {
      throw StateError(
        'Hosted certification fixture must be outside all Pub workspaces',
      );
    }
    HostedConsumerFixture(
      templateRoot: Directory(
        frameworkRoot.path +
            Platform.pathSeparator +
            'tool' +
            Platform.pathSeparator +
            'fixtures' +
            Platform.pathSeparator +
            'hosted_consumer' +
            Platform.pathSeparator +
            'template',
      ),
      destination: fixture,
      matrix: matrix,
      hostedPackages: hostedPackages,
      host: options.host,
    ).render();

    final pubGet = await _run(
      fixture,
      _hostCommand(options.host, ['pub', 'get']),
      home: certHome,
      cache: certCache,
    );
    results.add(pubGet.toJson());
    if (pubGet.exitCode == 0) {
      try {
        _assertCleanResolution(fixture, requiredPackages, matrix, options.host);
      } on Object catch (error) {
        violations.add(error.toString());
      }

      final pubDeps = await _run(
        fixture,
        _hostCommand(options.host, ['pub', 'deps', '--json']),
        home: certHome,
        cache: certCache,
      );
      results.add(pubDeps.toJson());
      if (pubDeps.exitCode == 0) {
        try {
          assertHostedDependencyGraph(
            pubDeps.stdoutText,
            expectedVersions: matrix.publicPackageVersions,
            host: options.host,
            requiredPackages: requiredPackages,
          );
        } on Object catch (error) {
          violations.add(error.toString());
        }
      } else {
        violations.add(
          'Hosted dependency graph inspection failed after Pub resolution.',
        );
      }
    } else {
      violations.add(
        'Hosted dependency resolution failed; certification stages were not run.',
      );
    }

    CommandResult? gateResult;
    if (pubGet.exitCode == 0) {
      final summaryPath = File(
        fixture.path +
            Platform.pathSeparator +
            'generated' +
            Platform.pathSeparator +
            'gate-summary.json',
      );
      final artifactDirectory = Directory(
        fixture.path +
            Platform.pathSeparator +
            'generated' +
            Platform.pathSeparator +
            'safe-artifacts',
      );
      final commands = <List<String>>[
        _zukeCommand(['doctor', '--format', 'json']),
        _zukeCommand(['generate']),
        _zukeCommand(['generate', '--check']),
        _hostCommand(options.host, ['test']),
        for (final profile in const [
          'pullRequest',
          'merge',
          'release',
          'nightly',
        ])
          _zukeCommand(['test', '--profile', profile, '--format', 'json']),
        for (final profile in const [
          'pullRequest',
          'merge',
          'release',
          'nightly',
        ])
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
        final result = await _run(
          fixture,
          command,
          home: certHome,
          cache: certCache,
        );
        results.add(result.toJson());
      }

      try {
        _assertLocks(fixture);
      } on Object catch (error) {
        violations.add(error.toString());
      }
      gateResult = _readCommandResult(summaryPath);
      final artifactResult = _readCommandResult(
        File(
          artifactDirectory.path +
              Platform.pathSeparator +
              'command-result.json',
        ),
      );
      if (gateResult == null || artifactResult == null) {
        violations.add(
          'Gate summary and safe artifact must both be current command results.',
        );
      } else {
        final summaryBytes = summaryPath.readAsBytesSync();
        final artifactBytes = File(
          artifactDirectory.path +
              Platform.pathSeparator +
              'command-result.json',
        ).readAsBytesSync();
        if (!_sameBytesAllowingTrailingNewline(summaryBytes, artifactBytes)) {
          violations.add('Gate summary and safe artifact bytes differ.');
        }
        final canonical = utf8.encode(encodeCommandResult(gateResult));
        if (!_sameBytesAllowingTrailingNewline(summaryBytes, canonical)) {
          violations.add('Gate summary is not canonical CommandResult bytes.');
        }
      }
      final gateRuns = results.where(
        (result) =>
            result['command'] is List &&
            (result['command'] as List).contains('gate'),
      );
      final stdoutGate = gateRuns.isEmpty ? null : gateRuns.last;
      if (stdoutGate != null && gateResult != null) {
        final structuredLine = stdoutGate['structuredLine'];
        if (structuredLine is! String || structuredLine.isEmpty) {
          violations.add(
            'Gate stdout did not contain a structured command result.',
          );
        } else if (!_sameBytesAllowingTrailingNewline(
          utf8.encode('$structuredLine\n'),
          utf8.encode(encodeCommandResult(gateResult)),
        )) {
          violations.add(
            'Gate stdout and summary command result bytes differ.',
          );
        }
      }
    }

    final passed =
        violations.isEmpty &&
        results.every((result) => result['exitCode'] == 0) &&
        (gateResult?.succeeded ?? false);
    final report = <String, Object?>{
      'kind': 'zuke.hosted-consumer-certification',
      'platform': options.platform,
      'host': options.host,
      'passed': passed,
      'sdk': {
        'dart': Platform.version,
        if (flutterVersion != null) 'flutter': flutterVersion,
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
    if (certHome.existsSync()) certHome.deleteSync(recursive: true);
    if (certCache.existsSync()) certCache.deleteSync(recursive: true);
  }
}

List<String> _dartCommand(List<String> command) => [
  'dart',
  '--suppress-analytics',
  ...command,
];

List<String> _hostCommand(String host, List<String> command) => [
  host == 'flutter' ? 'flutter' : 'dart',
  '--suppress-analytics',
  ...command,
];

List<String> _zukeCommand(List<String> command) =>
    _dartCommand(['run', 'zuke_cli:zuke', ...command]);

Future<_RunResult> _run(
  Directory root,
  List<String> command, {
  required Directory home,
  required Directory cache,
}) async {
  final executable = command.first;
  final arguments = command.sublist(1);
  final process = await Process.run(
    executable,
    arguments,
    workingDirectory: root.path,
    runInShell: Platform.isWindows,
    environment: {
      ...Platform.environment,
      'PUB_ENVIRONMENT': 'zuke_hosted_consumer_certification',
      'PUB_CACHE': cache.path,
      'HOME': home.path,
      'USERPROFILE': home.path,
    },
  );
  final stdoutText = process.stdout.toString();
  final stderrText = process.stderr.toString();
  CommandResult? structured;
  String? structuredLine;
  for (final line in stdoutText.split('\n').reversed) {
    final value = line.trim();
    if (!value.startsWith('{')) continue;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        structured = CommandResult.fromJson(
          Map<Object?, Object?>.from(decoded),
        );
        structuredLine = value;
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
    structuredLine: structuredLine,
    stdoutText: stdoutText,
  );
}

bool _flutterAvailable() {
  try {
    return Process.runSync('flutter', const [
          '--suppress-analytics',
          '--version',
        ], runInShell: Platform.isWindows).exitCode ==
        0;
  } on Object {
    return false;
  }
}

String? _flutterVersion() {
  try {
    final result = Process.runSync('flutter', const [
      '--suppress-analytics',
      '--version',
    ], runInShell: Platform.isWindows);
    return result.exitCode == 0
        ? result.stdout.toString().split('\n').first.trim()
        : null;
  } on Object {
    return null;
  }
}

bool _isInside(Directory child, Directory parent) {
  final childPath = child.absolute.path.toLowerCase();
  final parentPath = parent.absolute.path.toLowerCase();
  return childPath == parentPath ||
      childPath.startsWith('$parentPath${Platform.pathSeparator}');
}

/// Returns whether [child] would inherit a Pub workspace from an ancestor.
///
/// Certification fixtures must not accidentally resolve through a parent
/// checkout. A normal parent package is harmless; only a declared Pub
/// workspace can affect resolution.
bool isInsidePubWorkspace(Directory child) {
  var current = child.absolute.parent;
  while (true) {
    final pubspec = File(
      current.path + Platform.pathSeparator + 'pubspec.yaml',
    );
    if (pubspec.existsSync()) {
      final decoded = loadYaml(pubspec.readAsStringSync());
      if (decoded is Map &&
          (decoded['resolution'] == 'workspace' ||
              decoded['workspace'] is List)) {
        return true;
      }
    }
    final parent = current.parent;
    if (parent.path == current.path) return false;
    current = parent;
  }
}

void _assertCleanResolution(
  Directory root,
  Set<String> requiredPackages,
  ReleaseMatrix matrix,
  String host,
) {
  final pubspecText = File(
    root.path + Platform.pathSeparator + 'pubspec.yaml',
  ).readAsStringSync();
  final pubspec = loadYaml(pubspecText);
  if (pubspec is! Map ||
      pubspec.containsKey('dependency_overrides') ||
      pubspec.containsKey('resolution') ||
      pubspec.containsKey('workspace') ||
      _containsForbiddenSource(pubspec)) {
    throw const FormatException(
      'Hosted consumer contains workspace inheritance, path, Git, or override configuration',
    );
  }
  final devDependencies = pubspec['dev_dependencies'];
  if (host == 'flutter' &&
      devDependencies is Map &&
      devDependencies.containsKey('test')) {
    throw const FormatException(
      'Flutter hosted capsule must not declare a direct package:test dependency',
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
        'Resolved package ' +
            entry.key.toString() +
            ' is not hosted or SDK-provided',
      );
    }
  }
  final excludedRunner = host == 'flutter'
      ? 'zuke_runner'
      : 'zuke_runner_flutter';
  for (final name in requiredPackages.where((name) => name != excludedRunner)) {
    final entry = packages[name];
    final expected = matrix.publicPackageVersions[name];
    if (expected == null) {
      throw FormatException(
        'Required hosted package $name is not in the release matrix',
      );
    }
    if (entry is! Map ||
        entry['source'] != 'hosted' ||
        entry['version'] != expected) {
      throw FormatException(
        'Resolved ' +
            name +
            ' does not equal hosted matrix version ' +
            expected,
      );
    }
  }
  for (final entry in packages.entries) {
    final name = entry.key.toString();
    if (name == excludedRunner) {
      throw FormatException('Resolved opposite Zuke runner $name');
    }
    if (name == 'zuke' || name.startsWith('zuke_')) {
      final expected = matrix.publicPackageVersions[name];
      if (expected == null) {
        throw FormatException(
          'Resolved Zuke package $name is not part of the public release matrix',
        );
      }
      if (entry.value is! Map || entry.value['version'] != expected) {
        throw FormatException(
          'Resolved Zuke package $name does not equal hosted matrix version '
          '$expected',
        );
      }
    }
  }
}

bool _containsForbiddenSource(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key == 'path' || entry.key == 'git') return true;
      if (_containsForbiddenSource(entry.value)) return true;
    }
  } else if (value is List) {
    return value.any(_containsForbiddenSource);
  }
  return false;
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
            entry.value['source'].toString() +
            ':' +
            entry.value['version'].toString(),
  };
}

Map<String, String> _lockDigests(Directory root) {
  final result = <String, String>{};
  for (final profile in const ['pullRequest', 'merge', 'release', 'nightly']) {
    final file = File(
      root.path +
          Platform.pathSeparator +
          'assurance' +
          Platform.pathSeparator +
          'locks' +
          Platform.pathSeparator +
          profile +
          '.lock.json',
    );
    if (file.existsSync()) {
      result[profile] = sha256.convert(file.readAsBytesSync()).toString();
    }
  }
  return result;
}

void _assertLocks(Directory root) {
  for (final profile in const ['pullRequest', 'merge', 'release', 'nightly']) {
    final path =
        root.path +
        Platform.pathSeparator +
        'assurance' +
        Platform.pathSeparator +
        'locks' +
        Platform.pathSeparator +
        profile +
        '.lock.json';
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

bool _sameBytesAllowingTrailingNewline(List<int> left, List<int> right) {
  List<int> normalize(List<int> bytes) {
    if (bytes.isNotEmpty && bytes.last == 10) {
      if (bytes.length > 1 && bytes[bytes.length - 2] == 13) {
        return bytes.sublist(0, bytes.length - 2);
      }
      return bytes.sublist(0, bytes.length - 1);
    }
    return bytes;
  }

  final a = normalize(left);
  final b = normalize(right);
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

final class _RunResult {
  const _RunResult({
    required this.command,
    required this.exitCode,
    required this.commandResult,
    required this.stdoutPresent,
    required this.stderrPresent,
    this.structuredLine,
    this.stdoutText = '',
  });

  final List<String> command;
  final int exitCode;
  final CommandResult? commandResult;
  final bool stdoutPresent;
  final bool stderrPresent;
  final String? structuredLine;
  // Kept private to validate the dependency graph. It is never serialized into
  // the safe certification report because raw command output is not safe to
  // publish.
  final String stdoutText;

  Map<String, Object?> toJson() => {
    'command': command,
    'exitCode': exitCode,
    'status': exitCode == 0 ? 'passed' : 'failed',
    'stdoutPresent': stdoutPresent,
    'stderrPresent': stderrPresent,
    if (structuredLine != null) 'structuredLine': structuredLine,
    if (commandResult != null) 'commandResult': commandResult!.toJson(),
  };
}

final class _Options {
  const _Options({
    required this.platform,
    required this.host,
    this.output,
    this.flutterVersion,
    this.keepFixture = false,
    this.help = false,
  });

  final String platform;
  final String host;
  final String? output;
  final String? flutterVersion;
  final bool keepFixture;
  final bool help;

  static _Options parse(List<String> args) {
    if (args.contains('--help') || args.contains('-h')) {
      return const _Options(platform: 'linux', host: 'dart', help: true);
    }
    String? platform;
    var host = 'dart';
    String? output;
    String? flutterVersion;
    var keepFixture = false;
    for (var index = 0; index < args.length; index++) {
      switch (args[index]) {
        case '--platform':
          if (++index >= args.length) {
            throw const FormatException('--platform requires a value');
          }
          platform = args[index];
        case '--host':
          if (++index >= args.length) {
            throw const FormatException('--host requires a value');
          }
          host = args[index];
        case '--flutter-version':
          if (++index >= args.length) {
            throw const FormatException('--flutter-version requires a value');
          }
          flutterVersion = args[index];
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
    if (!const {'dart', 'flutter'}.contains(host)) {
      throw const FormatException('--host must be dart or flutter');
    }
    return _Options(
      platform: platform,
      host: host,
      output: output,
      flutterVersion: flutterVersion,
      keepFixture: keepFixture,
    );
  }

  static void printUsage() {
    stdout.writeln(
      'dart run tool/check_hosted_consumer.dart '
      '--platform <linux|windows> [--host <dart|flutter>] '
      '[--flutter-version <version>] [--output <json>] [--keep-fixture]',
    );
  }
}
