import 'dart:io';

import 'package:args/args.dart';

/// Removes only repository-local Zuke test temporary directories.
///
/// The command deliberately does not remove generated contracts, locks,
/// evidence, caches, build outputs, or user source files.
class CleanCommand {
  CleanCommand(this.args);

  final ArgResults args;

  int execute() {
    final requestedRoot = args['root'] as String? ?? Directory.current.path;
    final root = Directory(requestedRoot).absolute;
    if (!root.existsSync()) {
      throw FormatException('Clean root does not exist: ${root.path}');
    }

    final candidates = <Directory>[];
    _collectTestTempDirectories(root, candidates);
    candidates.sort((left, right) => left.path.compareTo(right.path));

    final dryRun = args['dry-run'] as bool? ?? false;
    if (candidates.isEmpty) {
      stdout.writeln('No Zuke test temporary directories found.');
      return 0;
    }

    if (dryRun) {
      for (final candidate in candidates) {
        stdout.writeln('Would remove ${candidate.path}');
      }
      stdout.writeln('${candidates.length} directory(s) would be removed.');
      return 0;
    }

    final failures = <String>[];
    for (final candidate in candidates) {
      try {
        candidate.deleteSync(recursive: true);
        stdout.writeln('Removed ${candidate.path}');
      } on FileSystemException {
        failures.add(candidate.path);
      }
    }
    if (failures.isNotEmpty) {
      throw FormatException(
        'Unable to remove Zuke test temporary directories: '
        '${failures.join(', ')}',
      );
    }
    stdout.writeln('${candidates.length} directory(s) removed.');
    return 0;
  }

  void _collectTestTempDirectories(
    Directory directory,
    List<Directory> output,
  ) {
    if (_basename(directory.path) == 'test') {
      for (final child
          in directory.listSync(followLinks: false).whereType<Directory>()) {
        if (_basename(child.path).startsWith('temp_')) output.add(child);
      }
      return;
    }

    for (final child
        in directory.listSync(followLinks: false).whereType<Directory>()) {
      final name = _basename(child.path);
      if (_skippedDirectoryNames.contains(name)) continue;
      _collectTestTempDirectories(child, output);
    }
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final separator = normalized.lastIndexOf('/');
    return separator == -1 ? normalized : normalized.substring(separator + 1);
  }
}

const _skippedDirectoryNames = <String>{
  '.git',
  '.dart_tool',
  '.zuke',
  'build',
  'coverage',
  'dist',
  'node_modules',
};
