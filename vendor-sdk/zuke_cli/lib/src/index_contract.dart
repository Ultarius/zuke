import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Bump for JSON shape or editor-visible semantic changes. See the schema
/// golden and docs/editor-plugin-cache.md for the release guard.
const zukeIndexContract = 1;

const _fallbackDirectoryLimit = 256;
const _fallbackExcludedDirectories = {
  '.dart_tool',
  '.git',
  '.zuke',
  'build',
  'coverage',
  'node_modules',
};

/// A directory the anchor fallback may list, paired with the configured source
/// root it was reached from. Artifact names are judged relative to that root, so
/// a package may legitimately be named after a build directory while a nested
/// build tree beneath it is still pruned.
final class _FallbackDirectory {
  _FallbackDirectory(this.path, [String? base]) : base = base ?? path;

  final String path;
  final String base;

  _FallbackDirectory nested(String child) => _FallbackDirectory(child, base);

  bool get isArtifact => p
      .split(p.relative(path, from: base))
      .any(
        (segment) =>
            _fallbackExcludedDirectories.contains(segment.toLowerCase()),
      );
}

String _comparablePath(String path) =>
    Platform.isWindows ? path.toLowerCase() : path;

/// Read before decoding the version-specific index payload. An incompatible
/// producer may have changed every other field in that payload.
final class ZukeIndexHeader {
  final int? contractVersion;
  final Map<Object?, Object?> json;

  ZukeIndexHeader(this.json) : contractVersion = _version(json);

  factory ZukeIndexHeader.read(File file) {
    final value = jsonDecode(file.readAsStringSync());
    if (value is! Map) throw const FormatException('Invalid analyzer index');
    return ZukeIndexHeader(value);
  }

  static int? _version(Map<Object?, Object?> json) {
    final value = json['contractVersion'];
    if (value == null && !json.containsKey('contractVersion')) return null;
    if (value is! int || value < 0) {
      throw const FormatException('Invalid analyzer index contractVersion');
    }
    return value;
  }

  bool get isIncompatible =>
      contractVersion != null && contractVersion != zukeIndexContract;

  String get mismatchMessage =>
      'ZUKE-PLUGIN-STALE: analyzer plugin was compiled for index contract '
      '$zukeIndexContract, this index is $contractVersion. The plugin and '
      'generator are incompatible. Run zuke doctor --fix with the workspace\'s '
      'current Zuke CLI, then restart the analysis server.';

  /// A stable existing Dart file, independent of callback order. Prefer the
  /// configured barrel; workspaces without a barrel use a generated contract.
  /// Without recorded locations, search source directories in a deterministic
  /// order, pruning build/cache trees and limiting fallback directory listings.
  String? diagnosticAnchor(String root) {
    final featureFiles = json['featureFiles'];
    final sourcePaths = json['sourcePaths'];
    final candidates = <String>[
      if (json['diagnosticAnchor'] is String)
        json['diagnosticAnchor'] as String,
      'lib/zuke_contracts.dart',
      if (featureFiles is Map)
        ...(featureFiles.values.whereType<String>().toList()..sort()),
      if (sourcePaths is List)
        ...(sourcePaths.whereType<String>().toList()..sort()),
    ];
    for (final candidate in candidates) {
      final normalized = candidate.replaceAll('\\', '/');
      if (p.posix.isAbsolute(normalized) || p.windows.isAbsolute(normalized)) {
        continue;
      }
      final path = p.normalize(p.join(root, normalized));
      if (p.isWithin(p.normalize(root), path) &&
          path.endsWith('.dart') &&
          File(path).existsSync()) {
        return path;
      }
    }
    // A newer producer may no longer use the optional location fields. Keep
    // the error visible on one deterministic source even in that case.
    final directories = <String>{
      for (final name in ['lib', 'bin', 'test']) p.join(root, name),
      ..._configuredSourceDirectories(root),
    };
    return _fallbackAnchor(root, directories);
  }

  /// List one directory at a time, preferring its files before subdirectories.
  /// Unlike a recursive `listSync`, this can prune artifacts before entering
  /// them and return as soon as it finds an anchor. Overlapping configured roots
  /// share a visit budget, including `roots: ['.']` at the workspace root.
  static String? _fallbackAnchor(String root, Iterable<String> directories) {
    final pending = [
      for (final directory in directories)
        _FallbackDirectory(p.normalize(directory)),
    ].reversed.toList();
    final visited = <String>{};
    var listed = 0;
    while (pending.isNotEmpty && listed < _fallbackDirectoryLimit) {
      final directory = pending.removeLast();
      // Checked before `visited` so a path pruned relative to one configured
      // root can still be listed when reached from another.
      if (directory.isArtifact) continue;
      final key = _comparablePath(directory.path);
      if (!visited.add(key)) continue;
      if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      listed++;
      try {
        final entries = Directory(directory.path).listSync(followLinks: false)
          ..sort((left, right) => left.path.compareTo(right.path));
        for (final entry in entries) {
          if (entry is File && entry.path.endsWith('.dart')) return entry.path;
        }
        pending.addAll(
          entries.reversed.whereType<Directory>().map(
            (entry) => directory.nested(entry.path),
          ),
        );
      } on FileSystemException {
        // An unreadable fallback must not turn a contract mismatch into a
        // generic stale-index error in every other source file.
        continue;
      }
    }
    return null;
  }

  /// Read only source locations, without pulling the extractor/IR graph into
  /// the editor plugin. A workspace can have packages without a root `lib/`.
  static Iterable<String> _configuredSourceDirectories(String root) sync* {
    final config = File(p.join(root, 'zuke.yaml'));
    final Object? yaml;
    try {
      if (!config.existsSync()) return;
      yaml = loadYaml(config.readAsStringSync());
    } on FileSystemException {
      return;
    } on YamlException {
      return;
    }
    final targets = yaml is Map ? yaml['targets'] : null;
    if (targets is! Map) return;
    final directories = <String>{};
    for (final target in targets.values) {
      if (target is! Map || target['language'] != 'dart') continue;
      final packages = target['packages'];
      if (packages is! List) continue;
      for (final package in packages) {
        if (package is! Map || package['path'] is! String) continue;
        final roots = package['roots'];
        if (roots is! List) continue;
        for (final sourceRoot in roots.whereType<String>()) {
          final directory = p.normalize(
            p.join(root, package['path'] as String, sourceRoot),
          );
          if (p.equals(directory, p.normalize(root)) ||
              p.isWithin(p.normalize(root), directory)) {
            directories.add(directory);
          }
        }
      }
    }
    yield* directories.toList()..sort();
  }
}
