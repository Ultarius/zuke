import 'dart:convert';
import 'dart:io';

import '../vendor-sdk/check_docs.dart';
import 'release_matrix.dart';

Future<void> main(List<String> args) async {
  final root = Directory.current.absolute;
  late final ReleaseMatrix matrix;
  try {
    matrix = readReleaseMatrix(root);
  } on Object catch (error) {
    stderr.writeln('Release matrix preflight failed: $error');
    exitCode = 1;
    return;
  }
  final documentationFailures = DocumentationChecker(root).check();
  if (documentationFailures.isNotEmpty) {
    stderr.writeln('Publication boundary preflight failed:');
    for (final failure in documentationFailures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }
  final generatedContractCheck = Process.runSync(
    Platform.resolvedExecutable,
    ['tool/generate_release_contract.dart', '--check'],
    workingDirectory: root.path,
    runInShell: Platform.isWindows,
  );
  if (generatedContractCheck.exitCode != 0) {
    stderr.writeln('Generated release contract preflight failed:');
    stderr.write(generatedContractCheck.stdout);
    stderr.write(generatedContractCheck.stderr);
    exitCode = 1;
    return;
  }
  final options = _PublishOptions.parse(args, matrix.publicationOrder);
  if (options.error != null) {
    stderr.writeln(options.error);
    _printUsage();
    exitCode = 64;
    return;
  }
  if (options.help) {
    _printUsage();
    return;
  }

  final packages = options.packages;
  final mode = options.publish ? 'publish' : 'dry-run';
  final warningFlag = options.ignoreWarnings ? ' --ignore-warnings' : '';

  stdout.writeln(
    'Zuke package $mode: ${packages.length} package(s) in dependency order.',
  );
  stdout.writeln(
    'Command: dart pub publish${options.publish ? '' : ' --dry-run'}$warningFlag',
  );

  final targets = <_PublishTarget>[];
  var skipped = 0;
  final versionChecker = options.publish ? _PubDevVersionChecker() : null;

  try {
    for (final package in packages) {
      late final _PublishTarget target;
      try {
        target = _readPublishTarget(root, package, matrix);
        if (versionChecker != null &&
            await versionChecker.contains(target.package, target.version)) {
          stdout.writeln(
            'Skipping ${target.package} ${target.version}: '
            'this version already exists on pub.dev.',
          );
          skipped++;
          continue;
        }
      } on Object catch (error) {
        stderr.writeln('Preflight failed for $package: $error');
        exitCode = 1;
        return;
      }
      targets.add(target);
    }
  } finally {
    versionChecker?.close();
  }

  if (options.publish) {
    stdout.writeln(
      'Publish preflight: ${targets.length} package(s) to publish; '
      '$skipped skipped because their exact versions already exist on pub.dev.',
    );
    if (targets.isEmpty) {
      stdout.writeln('All selected package versions are already published.');
      return;
    }
  }

  if (options.publish && !options.confirmed) {
    stdout.write('Type PUBLISH to continue: ');
    if (stdin.readLineSync() != 'PUBLISH') {
      stdout.writeln('Publication cancelled.');
      return;
    }
  }

  for (final target in targets) {
    stdout.writeln('\n==> ${target.package} ${target.version}');
    final command = <String>['pub', 'publish'];
    if (!options.publish) command.add('--dry-run');
    if (options.ignoreWarnings) command.add('--ignore-warnings');

    final process = await Process.start(
      Platform.resolvedExecutable,
      command,
      workingDirectory: target.directory.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final result = await process.exitCode;
    if (result != 0) {
      stderr.writeln('\nStopped after ${target.package} (exit code $result).');
      exitCode = result;
      return;
    }
  }

  stdout.writeln('\nAll selected Zuke packages completed successfully.');
}

_PublishTarget _readPublishTarget(
  Directory root,
  String package,
  ReleaseMatrix matrix,
) {
  final packageDirectory = Directory(
    '${root.path}${Platform.pathSeparator}vendor-sdk${Platform.pathSeparator}$package',
  );
  final pubspec = File(
    '${packageDirectory.path}${Platform.pathSeparator}pubspec.yaml',
  );

  if (!packageDirectory.existsSync() || !pubspec.existsSync()) {
    throw StateError('Missing package directory or pubspec: $package');
  }

  final pubspecText = pubspec.readAsStringSync();
  if (!RegExp(
    r'^name:\s*' + RegExp.escape(package) + r'\s*$',
    multiLine: true,
  ).hasMatch(pubspecText)) {
    throw StateError('Package name mismatch in ${pubspec.path}: $package');
  }
  if (RegExp(
    r'^publish_to:\s*none\s*$',
    multiLine: true,
  ).hasMatch(pubspecText)) {
    throw StateError('Refusing to publish repository-only package: $package');
  }

  final versionMatch = RegExp(
    r'''^version:\s*["']?([^"'\s#]+)''',
    multiLine: true,
  ).firstMatch(pubspecText);
  if (versionMatch == null) {
    throw StateError('Missing package version in ${pubspec.path}: $package');
  }

  final actualVersion = versionMatch.group(1)!;
  final expectedVersion = matrix.versions[package];
  if (expectedVersion == null) {
    throw StateError('$package is absent from the release matrix');
  }
  if (actualVersion != expectedVersion) {
    throw StateError(
      '$package is $actualVersion but the release matrix requires $expectedVersion',
    );
  }

  return _PublishTarget(
    package: package,
    version: actualVersion,
    directory: packageDirectory,
  );
}

class _PublishTarget {
  const _PublishTarget({
    required this.package,
    required this.version,
    required this.directory,
  });

  final String package;
  final String version;
  final Directory directory;
}

class _PubDevVersionChecker {
  _PubDevVersionChecker()
    : _client = HttpClient()
        ..userAgent =
            'zuke-publish-script/1.0 (+https://github.com/Ultarius/zuke)';

  final HttpClient _client;

  Future<bool> contains(String package, String version) async {
    final uri = Uri.https('pub.dev', '/api/packages/$package');
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode == HttpStatus.notFound) {
      return false;
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'pub.dev returned HTTP ${response.statusCode} '
        '${response.reasonPhrase} while checking $package',
        uri: uri,
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw FormatException('Unexpected pub.dev response for $package.');
    }
    final versions = decoded['versions'];
    if (versions is! List) {
      throw FormatException(
        'pub.dev response for $package has no versions list.',
      );
    }

    return versions.any((entry) => entry is Map && entry['version'] == version);
  }

  void close() => _client.close(force: true);
}

class _PublishOptions {
  _PublishOptions({
    required this.help,
    required this.publish,
    required this.ignoreWarnings,
    required this.confirmed,
    required this.packages,
    this.error,
  });

  final bool help;
  final bool publish;
  final bool ignoreWarnings;
  final bool confirmed;
  final List<String> packages;
  final String? error;

  factory _PublishOptions.parse(
    List<String> args,
    List<String> publishablePackages,
  ) {
    var help = false;
    var publish = false;
    var dryRun = false;
    var ignoreWarnings = false;
    var confirmed = false;
    final selected = <String>[];
    String? error;

    for (var index = 0; index < args.length; index++) {
      final argument = args[index];
      switch (argument) {
        case '--help':
        case '-h':
          help = true;
        case '--publish':
          publish = true;
        case '--dry-run':
          dryRun = true;
        case '--ignore-warnings':
          ignoreWarnings = true;
        case '--yes':
          confirmed = true;
        case '--package':
          if (index + 1 >= args.length) {
            error = '--package requires a package name.';
          } else {
            selected.add(args[++index]);
          }
        default:
          if (argument.startsWith('--package=')) {
            selected.add(argument.substring('--package='.length));
          } else {
            error = 'Unknown argument: $argument';
          }
      }
    }

    if (publish && dryRun) {
      error = '--publish and --dry-run cannot be combined.';
    }
    if (ignoreWarnings && publish) {
      error = '--ignore-warnings is only valid with --dry-run.';
    }
    if (selected.any((package) => !publishablePackages.contains(package))) {
      final invalid = selected
          .where((package) => !publishablePackages.contains(package))
          .join(', ');
      error = 'Not a publishable Zuke package: $invalid';
    }

    final selectedSet = selected.toSet();
    final packages = selected.isEmpty
        ? publishablePackages
        : publishablePackages
              .where(selectedSet.contains)
              .toList(growable: false);
    return _PublishOptions(
      help: help,
      publish: publish,
      ignoreWarnings: ignoreWarnings,
      confirmed: confirmed,
      packages: packages,
      error: error,
    );
  }
}

void _printUsage() {
  stdout.writeln('''
Publish the supported Zuke packages sequentially.

Usage:
  dart run tool/publish_packages.dart --dry-run
  dart run tool/publish_packages.dart --dry-run --ignore-warnings
  dart run tool/publish_packages.dart --publish
  dart run tool/publish_packages.dart --publish --package zuke_cli

Options:
  --dry-run          Run `dart pub publish --dry-run` (the default mode).
  --publish          Run `dart pub publish` for each selected package.
  --ignore-warnings  Pass `--ignore-warnings` to dry-run commands.
  --package NAME     Select one package; may be repeated.
  --yes              Skip this script's publication confirmation prompt.
  --help             Show this help.
''');
}
