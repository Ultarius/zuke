import 'dart:io';

/// The packages released to pub.dev, in dependency order.
const _publishablePackages = <String>[
  'zuke_core',
  'zuke_annotations',
  'zuke_frontend',
  'zuke',
  'zuke_runner',
  'zuke_runner_flutter',
  'zuke_http_runtime',
  'zuke_dart_build_hook',
  'zuke_cli',
];

Future<void> main(List<String> args) async {
  final options = _PublishOptions.parse(args);
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

  if (options.publish && !options.confirmed) {
    stdout.write('Type PUBLISH to continue: ');
    if (stdin.readLineSync() != 'PUBLISH') {
      stdout.writeln('Publication cancelled.');
      return;
    }
  }

  final root = Directory.current.absolute;
  for (final package in packages) {
    final packageDirectory = Directory(
      '${root.path}${Platform.pathSeparator}vendor-sdk${Platform.pathSeparator}$package',
    );
    final pubspec = File(
      '${packageDirectory.path}${Platform.pathSeparator}pubspec.yaml',
    );

    if (!packageDirectory.existsSync() || !pubspec.existsSync()) {
      stderr.writeln('Missing package directory or pubspec: $package');
      exitCode = 1;
      return;
    }

    final pubspecText = pubspec.readAsStringSync();
    if (!RegExp(
      r'^name:\s*' + RegExp.escape(package) + r'\s*$',
      multiLine: true,
    ).hasMatch(pubspecText)) {
      stderr.writeln('Package name mismatch in ${pubspec.path}: $package');
      exitCode = 1;
      return;
    }
    if (RegExp(
      r'^publish_to:\s*none\s*$',
      multiLine: true,
    ).hasMatch(pubspecText)) {
      stderr.writeln('Refusing to publish repository-only package: $package');
      exitCode = 1;
      return;
    }

    stdout.writeln('\n==> $package');
    final command = <String>['pub', 'publish'];
    if (!options.publish) command.add('--dry-run');
    if (options.ignoreWarnings) command.add('--ignore-warnings');

    final process = await Process.start(
      Platform.resolvedExecutable,
      command,
      workingDirectory: packageDirectory.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final result = await process.exitCode;
    if (result != 0) {
      stderr.writeln('\nStopped after $package (exit code $result).');
      exitCode = result;
      return;
    }
  }

  stdout.writeln('\nAll selected Zuke packages completed successfully.');
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

  factory _PublishOptions.parse(List<String> args) {
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
    if (selected.any((package) => !_publishablePackages.contains(package))) {
      final invalid = selected
          .where((package) => !_publishablePackages.contains(package))
          .join(', ');
      error = 'Not a publishable Zuke package: $invalid';
    }

    final selectedSet = selected.toSet();
    final packages = selected.isEmpty
        ? _publishablePackages
        : _publishablePackages
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
