import 'dart:io';

import 'package:yaml/yaml.dart';

Future<void> main(List<String> args) async {
  try {
    final options = _Options.parse(args);
    if (options.help) {
      _Options.printUsage();
      return;
    }

    final repositoryRoot = Directory.current.absolute;
    final workspaceRoots = options.roots.isEmpty
        ? _discoverProjectRoots(repositoryRoot)
        : _deduplicateRoots(
            options.roots.map(
              (requestedRoot) => _resolveRoot(repositoryRoot, requestedRoot),
            ),
          );

    if (options.roots.isEmpty) {
      stdout.writeln(
        'Discovered ${workspaceRoots.length} Zuke project(s) from '
        '${_path(repositoryRoot, 'pubspec.yaml')}:',
      );
      for (final workspaceRoot in workspaceRoots) {
        stdout.writeln('  - ${_relativePath(repositoryRoot, workspaceRoot)}');
      }
    }

    for (final workspaceRoot in workspaceRoots) {
      final configuredProfiles = _readLockProfiles(workspaceRoot);
      final profiles = options.profiles.isEmpty
          ? configuredProfiles
          : _selectProfiles(options.profiles, configuredProfiles);

      stdout.writeln('Refreshing profile locks for ${workspaceRoot.path}');
      for (final profile in profiles) {
        await _runZuke(repositoryRoot, <String>[
          'test',
          '--root',
          workspaceRoot.path,
          '--profile',
          profile,
          '--format',
          'json',
        ]);
        await _runZuke(repositoryRoot, <String>[
          'lock',
          '--root',
          workspaceRoot.path,
          '--profile',
          profile,
        ]);
        await _runZuke(repositoryRoot, <String>[
          'lock',
          '--root',
          workspaceRoot.path,
          '--profile',
          profile,
          '--check',
        ]);
      }

      if (profiles.length == configuredProfiles.length &&
          profiles.toSet().containsAll(configuredProfiles)) {
        await _runZuke(repositoryRoot, <String>[
          'lock',
          '--root',
          workspaceRoot.path,
          '--all-profiles',
          '--check',
        ]);
      }
    }
  } on FormatException catch (error) {
    stderr.writeln('Profile-lock refresh failed: ${error.message}');
    _Options.printUsage();
    exitCode = 64;
  } on Object catch (error) {
    stderr.writeln('Profile-lock refresh failed: $error');
    exitCode = 1;
  }
}

/// Finds project roots from the repository Dart workspace.
///
/// The root pubspec lists package members, not necessarily Zuke workspace
/// roots. For example, the calculator product lists its apps and packages,
/// while its `zuke.yaml` lives one directory above them. Each member is
/// therefore walked upward until the nearest `zuke.yaml` is found. SDK-only
/// members under `vendor-sdk` are intentionally ignored because they do not
/// own profile locks.
List<Directory> _discoverProjectRoots(Directory repositoryRoot) {
  final pubspec = File(_path(repositoryRoot, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw FormatException(
      'Cannot discover projects: missing pubspec.yaml at ${pubspec.path}',
    );
  }

  final document = loadYaml(pubspec.readAsStringSync());
  if (document is! YamlMap) {
    throw const FormatException('pubspec.yaml must contain a mapping');
  }
  final workspace = document['workspace'];
  if (workspace is! YamlList || workspace.isEmpty) {
    throw const FormatException(
      'pubspec.yaml workspace must contain one or more package paths',
    );
  }

  final discovered = <String, Directory>{};
  for (final member in workspace) {
    if (member is! String || member.trim().isEmpty) {
      throw const FormatException(
        'pubspec.yaml workspace entries must be non-empty strings',
      );
    }

    final memberRoot = _resolveRoot(repositoryRoot, member);
    var candidate = memberRoot;
    while (_isWithin(repositoryRoot, candidate)) {
      if (File(_path(candidate, 'zuke.yaml')).existsSync()) {
        final resolved = _canonicalDirectory(candidate);
        discovered[resolved.path.toLowerCase()] = resolved;
        break;
      }

      final parent = candidate.parent;
      if (parent.path == candidate.path) break;
      candidate = parent;
    }
  }

  if (discovered.isEmpty) {
    throw const FormatException(
      'No Zuke project roots were found beneath the pubspec.yaml workspace',
    );
  }

  return discovered.values.toList(growable: false);
}

List<Directory> _deduplicateRoots(Iterable<Directory> roots) {
  final unique = <String, Directory>{};
  for (final root in roots) {
    final resolved = _canonicalDirectory(root);
    unique[resolved.path.toLowerCase()] = resolved;
  }
  return unique.values.toList(growable: false);
}

Directory _canonicalDirectory(Directory directory) {
  try {
    return Directory(directory.resolveSymbolicLinksSync());
  } on FileSystemException {
    return directory.absolute;
  }
}

bool _isWithin(Directory parent, Directory child) {
  final parentPath = _comparisonPath(_canonicalDirectory(parent).path);
  final childPath = _comparisonPath(_canonicalDirectory(child).path);
  final separator = Platform.pathSeparator;
  return childPath == parentPath ||
      childPath.startsWith('$parentPath$separator');
}

String _comparisonPath(String value) =>
    Platform.isWindows ? value.toLowerCase() : value;

String _relativePath(Directory repositoryRoot, Directory child) {
  final root = _canonicalDirectory(repositoryRoot).path;
  final path = _canonicalDirectory(child).path;
  final rootForComparison = _comparisonPath(root);
  final pathForComparison = _comparisonPath(path);
  if (pathForComparison == rootForComparison) return '.';
  final prefix = '$rootForComparison${Platform.pathSeparator}';
  if (pathForComparison.startsWith(prefix)) {
    return path.substring(prefix.length).replaceAll('\\', '/');
  }
  return path;
}

String _path(Directory directory, String child) =>
    '${directory.path}${Platform.pathSeparator}$child';

Directory _resolveRoot(Directory repositoryRoot, String value) {
  final root = Directory(value);
  final resolved = root.isAbsolute
      ? root.absolute
      : Directory(
          '${repositoryRoot.path}${Platform.pathSeparator}$value',
        ).absolute;
  if (!resolved.existsSync()) {
    throw FormatException('Workspace root does not exist: ${resolved.path}');
  }
  return resolved;
}

List<String> _readLockProfiles(Directory workspaceRoot) {
  final configFile = File(
    '${workspaceRoot.path}${Platform.pathSeparator}zuke.yaml',
  );
  if (!configFile.existsSync()) {
    throw FormatException('Missing zuke.yaml at ${workspaceRoot.path}');
  }

  final document = loadYaml(configFile.readAsStringSync());
  if (document is! YamlMap) {
    throw FormatException('zuke.yaml must contain a mapping');
  }
  final lock = document['lock'];
  if (lock is! YamlMap) {
    throw FormatException('zuke.yaml must declare lock.profiles');
  }
  final profiles = lock['profiles'];
  if (profiles is! YamlList) {
    throw FormatException('zuke.yaml lock.profiles must be a list');
  }

  final values = profiles.whereType<String>().toList(growable: false);
  if (values.length != profiles.length || values.isEmpty) {
    throw FormatException(
      'zuke.yaml lock.profiles must contain one or more string values',
    );
  }
  if (values.toSet().length != values.length) {
    throw FormatException(
      'zuke.yaml lock.profiles must not contain duplicates',
    );
  }
  return values;
}

List<String> _selectProfiles(List<String> requested, List<String> configured) {
  final configuredSet = configured.toSet();
  final unknown = requested.where(
    (profile) => !configuredSet.contains(profile),
  );
  if (unknown.isNotEmpty) {
    throw FormatException(
      'Requested profile(s) are not configured: ${unknown.join(', ')}',
    );
  }
  return requested.toSet().toList(growable: false);
}

Future<void> _runZuke(Directory repositoryRoot, List<String> command) async {
  stdout.writeln('> dart run zuke_cli:zuke ${command.join(' ')}');
  final result = await Process.run(
    Platform.resolvedExecutable,
    <String>['--suppress-analytics', 'run', 'zuke_cli:zuke', ...command],
    workingDirectory: repositoryRoot.path,
    runInShell: Platform.isWindows,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(
      Platform.resolvedExecutable,
      <String>['run', 'zuke_cli:zuke', ...command],
      'Zuke command failed with exit code ${result.exitCode}',
      result.exitCode,
    );
  }
}

final class _Options {
  const _Options({
    required this.roots,
    required this.profiles,
    this.help = false,
  });

  final List<String> roots;
  final List<String> profiles;
  final bool help;

  static _Options parse(List<String> args) {
    if (args.contains('--help') || args.contains('-h')) {
      return const _Options(
        roots: <String>[],
        profiles: <String>[],
        help: true,
      );
    }

    final roots = <String>[];
    final profiles = <String>[];
    for (var index = 0; index < args.length; index++) {
      switch (args[index]) {
        case '--root':
        case '-r':
          if (++index >= args.length || args[index].startsWith('-')) {
            throw const FormatException('--root requires a value');
          }
          roots.add(args[index]);
        case '--profile':
          if (++index >= args.length || args[index].startsWith('-')) {
            throw const FormatException('--profile requires a value');
          }
          profiles.add(args[index]);
        default:
          throw FormatException('Unknown option: ${args[index]}');
      }
    }
    return _Options(roots: roots, profiles: profiles);
  }

  static void printUsage() {
    stdout.writeln(
      'dart run tool/regenerate_profile_locks.dart '
      '[--root <project>]... [--profile <name>]...',
    );
    stdout.writeln(
      'With no --root, discovers Zuke project roots from the root '
      'pubspec.yaml workspace. Runs managed tests, generates each '
      'configured profile lock, and verifies it without mutation.',
    );
  }
}
