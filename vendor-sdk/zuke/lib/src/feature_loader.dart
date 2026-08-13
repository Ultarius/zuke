import 'dart:io';

import 'package:zuke_frontend/zuke_frontend.dart';

/// Resolves a feature from a Zuke workspace without project-specific
/// current-working-directory fallbacks in every test entrypoint.
final class ZukeFeatureLoader {
  const ZukeFeatureLoader._();

  static ParsedFeature load(String feature, {String? workspaceRoot}) {
    final root = _resolveRoot(workspaceRoot);
    late final WorkspaceDiscoveryResult workspace;
    try {
      workspace = WorkspaceDiscovery().discover(root.path);
    } on WorkspaceConfigError catch (error) {
      throw StateError(
        'Zuke workspace configuration is invalid at ${root.path}: ${error.message}',
      );
    }
    final requested = feature.replaceAll('\\', '/');
    final matches = workspace.data.features.where((candidate) {
      final source = candidate.metadata.source.file.replaceAll('\\', '/');
      if (source == requested || source.endsWith('/$requested')) return true;
      return source.split('/').last == requested;
    }).toList();
    if (matches.isEmpty) {
      throw StateError(
        'Feature "$feature" was not found under ${root.path}. '
        'Use a workspace-relative path or a unique basename.',
      );
    }
    if (matches.length > 1) {
      final locations = matches
          .map((candidate) => candidate.metadata.source.file)
          .join(', ');
      throw StateError('Feature "$feature" is ambiguous: $locations');
    }
    return matches.single;
  }

  static Directory _resolveRoot(String? explicit) {
    if (explicit != null && explicit.isNotEmpty) {
      return _requireWorkspace(Directory(explicit).absolute);
    }
    final environmentRoot = Platform.environment['ZUKE_ROOT'];
    if (environmentRoot != null && environmentRoot.isNotEmpty) {
      return _requireWorkspace(Directory(environmentRoot).absolute);
    }
    var directory = Directory.current.absolute;
    while (true) {
      if (File(
        '${directory.path}${Platform.pathSeparator}zuke.yaml',
      ).existsSync()) {
        return directory;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    throw StateError(
      'No zuke.yaml found from ${Directory.current.path}. '
      'Set ZUKE_ROOT or pass workspaceRoot.',
    );
  }

  static Directory _requireWorkspace(Directory directory) {
    if (!File(
      '${directory.path}${Platform.pathSeparator}zuke.yaml',
    ).existsSync()) {
      throw StateError('Zuke workspace not found at ${directory.path}');
    }
    return directory;
  }
}
