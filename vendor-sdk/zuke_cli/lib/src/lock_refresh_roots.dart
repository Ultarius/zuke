import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Resolves explicit Zuke roots or discovers their nearest owning workspace.
List<Directory> lockRefreshRoots(Iterable<String> paths) {
  final roots = <String, Directory>{};
  void add(Directory root) {
    final canonical = root.resolveSymbolicLinksSync();
    roots[Platform.isWindows ? canonical.toLowerCase() : canonical] = Directory(
      canonical,
    );
  }

  for (final path in paths) {
    final repository = Directory(Directory(path).resolveSymbolicLinksSync());
    if (File(p.join(repository.path, 'zuke.yaml')).existsSync()) {
      add(repository);
      continue;
    }
    final pubspec = File(p.join(repository.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw FormatException(
        'No zuke.yaml or pubspec.yaml at ${repository.path}',
      );
    }
    final document = loadYaml(pubspec.readAsStringSync());
    final members = document is Map ? document['workspace'] : null;
    if (members is! List || members.isEmpty) {
      throw const FormatException(
        'pubspec.yaml workspace must contain package paths',
      );
    }
    var found = false;
    for (final member in members) {
      if (member is! String || member.trim().isEmpty) {
        throw const FormatException(
          'Workspace members must be non-empty paths',
        );
      }
      var candidate = Directory(
        Directory(p.join(repository.path, member)).resolveSymbolicLinksSync(),
      );
      if (!p.isWithin(repository.path, candidate.path) &&
          !p.equals(repository.path, candidate.path)) {
        throw FormatException('Workspace member escapes repository: $member');
      }
      while (p.isWithin(repository.path, candidate.path) ||
          p.equals(repository.path, candidate.path)) {
        if (File(p.join(candidate.path, 'zuke.yaml')).existsSync()) {
          add(candidate);
          found = true;
          break;
        }
        candidate = candidate.parent;
      }
    }
    if (!found) {
      throw FormatException('No Zuke roots found at ${repository.path}');
    }
  }
  return roots.values.toList(growable: false);
}
