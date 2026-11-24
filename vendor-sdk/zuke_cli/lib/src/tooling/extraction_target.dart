import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:zuke_frontend/zuke_frontend.dart';

/// A resolved workspace placement used by every extraction boundary.
final class ResolvedPlacement {
  final String workspaceRoot;
  final WorkspaceTarget target;
  final WorkspacePackage package;

  const ResolvedPlacement({
    required this.workspaceRoot,
    required this.target,
    required this.package,
  });
}

/// Typed placement failure. CLI layers map [code] to diagnostics while
/// analyzer/build-hook callers can preserve the same failure identity.
final class PlacementFailure implements Exception {
  final String code;
  final String message;
  final Map<String, Object?> context;

  const PlacementFailure(this.code, this.message, {this.context = const {}});

  @override
  String toString() => '$code: $message';
}

/// Resolves the target and package identity of [packageRoot].
///
/// [explicitWorkspaceRoot] names the workspace to use. Without it, the nearest
/// ancestor containing a `zuke.yaml` is used.
ResolvedPlacement resolvePlacement(
  String packageRoot, {
  String? requestedTarget,
  WorkspaceDiscoveryResult? workspace,
  String? explicitWorkspaceRoot,
}) {
  final packageDirectory = Directory(packageRoot);
  final workspaceRoot = _findWorkspaceRoot(
    explicitWorkspaceRoot == null
        ? packageDirectory
        : Directory(explicitWorkspaceRoot),
    searchParents: explicitWorkspaceRoot == null,
  );
  if (workspaceRoot == null) {
    throw PlacementFailure(
      'ZK-TARGET-UNASSIGNED',
      explicitWorkspaceRoot == null
          ? 'Package is not contained in a configured Zuke workspace'
          : 'Configured workspace root has no zuke.yaml',
      context: {'workspaceRoot': ?explicitWorkspaceRoot},
    );
  }
  final WorkspaceDiscoveryResult discovered;
  try {
    discovered = workspace ?? WorkspaceDiscovery().discover(workspaceRoot.path);
  } on LegacyWorkspaceConfigError catch (error) {
    throw PlacementFailure(
      'ZK-CONFIG-LEGACY-FORMAT',
      'The workspace configuration is not the current schema-3 format: '
          '${error.message}',
      context: {'workspaceRoot': workspaceRoot.path},
    );
  } on WorkspaceConfigError catch (error) {
    throw PlacementFailure(
      'ZK-CONFIG-INVALID',
      'The workspace configuration could not be parsed: ${error.message}',
      context: {'workspaceRoot': workspaceRoot.path},
    );
  }
  final canonicalPackage = _canonical(packageDirectory);
  final matchingTargets = <String, WorkspaceTarget>{};
  final matchingPackages = <String, WorkspacePackage>{};
  var missingConfiguredPackage = false;
  for (final target in discovered.config.workspaceTargets.values) {
    for (final package in target.packages) {
      // `join` would discard the workspace root for an absolute path, and a
      // package outside the workspace is never a member of it.
      if (p.isAbsolute(package.path)) continue;
      final configuredPath = Directory(
        p.join(workspaceRoot.path, package.path),
      );
      if (!configuredPath.existsSync()) {
        if (_canonical(configuredPath) == canonicalPackage) {
          missingConfiguredPackage = true;
        }
        continue;
      }
      if (_canonical(configuredPath) == canonicalPackage) {
        matchingTargets[target.id] = target;
        matchingPackages[target.id] = package;
      }
    }
  }
  final requested = requestedTarget?.trim();
  if (requested != null && requested.isNotEmpty) {
    final target = discovered.config.workspaceTargets[requested];
    if (target == null) {
      throw PlacementFailure(
        'ZK-TARGET-UNKNOWN',
        'Requested target "$requested" is not configured',
        context: {'target': requested},
      );
    }
    if (missingConfiguredPackage) {
      throw PlacementFailure(
        'ZK-SOURCE-MISSING-PACKAGE',
        'The configured package path for target "$requested" does not exist',
        context: {'target': requested, 'packageRoot': packageRoot},
      );
    }
    final package = matchingPackages[requested];
    if (package == null) {
      throw PlacementFailure(
        'ZK-TARGET-NOT-MEMBER',
        'Package is not a member of target "$requested"',
        context: {'target': requested, 'packageRoot': packageRoot},
      );
    }
    return ResolvedPlacement(
      workspaceRoot: workspaceRoot.path,
      target: target,
      package: package,
    );
  }
  if (matchingTargets.isEmpty) {
    if (missingConfiguredPackage) {
      throw const PlacementFailure(
        'ZK-SOURCE-MISSING-PACKAGE',
        'A configured package path does not exist',
      );
    }
    throw PlacementFailure(
      'ZK-TARGET-UNASSIGNED',
      'Package has no configured workspace target membership',
      context: {'packageRoot': packageRoot},
    );
  }
  if (matchingTargets.length != 1) {
    throw PlacementFailure(
      'ZK-TARGET-AMBIGUOUS',
      'Package belongs to multiple configured targets; pass --target',
      context: {'targets': matchingTargets.keys.toList()..sort()},
    );
  }
  final target = matchingTargets.values.single;
  final package = matchingPackages[target.id];
  if (package == null) {
    throw PlacementFailure(
      'ZK-SOURCE-MISSING-PACKAGE',
      'Configured package identity is missing for target ${target.id}',
    );
  }
  return ResolvedPlacement(
    workspaceRoot: workspaceRoot.path,
    target: target,
    package: package,
  );
}

Directory? _findWorkspaceRoot(Directory start, {required bool searchParents}) {
  var current = Directory(_canonical(start));
  while (true) {
    if (File.fromUri(current.uri.resolve('zuke.yaml')).existsSync()) {
      return current;
    }
    if (!searchParents) return null;
    final parent = current.parent;
    if (parent.path == current.path) return null;
    current = parent;
  }
}

String _canonical(Directory directory) {
  try {
    final resolved = directory.resolveSymbolicLinksSync().replaceAll('\\', '/');
    return Platform.isWindows ? resolved.toLowerCase() : resolved;
  } catch (_) {
    final absolute = directory.absolute.path.replaceAll('\\', '/');
    return Platform.isWindows ? absolute.toLowerCase() : absolute;
  }
}
