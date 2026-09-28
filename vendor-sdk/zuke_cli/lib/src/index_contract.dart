import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Bump for JSON shape or editor-visible semantic changes. See the schema
/// golden and docs/editor-plugin-cache.md for the release guard.
const zukeIndexContract = 1;

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
    for (final name in ['lib', 'bin', 'test']) {
      final directory = Directory(p.join(root, name));
      if (!directory.existsSync()) continue;
      try {
        final files =
            directory
                .listSync(recursive: true, followLinks: false)
                .whereType<File>()
                .where((file) => file.path.endsWith('.dart'))
                .map((file) => file.path)
                .toList()
              ..sort();
        if (files.isNotEmpty) return files.first;
      } on FileSystemException {
        // An unreadable fallback must not turn a contract mismatch into a
        // generic stale-index error in every other source file.
        continue;
      }
    }
    return null;
  }
}
