import 'dart:io';

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

ResolvedPlacement resolvePlacement(
  String packageRoot, {
  String? requestedTarget,
  WorkspaceDiscoveryResult? workspace,
}) {
  final packageDirectory = Directory(packageRoot);
  final workspaceRoot = _findWorkspaceRoot(packageDirectory);
  if (workspaceRoot == null) {
    throw const PlacementFailure(
      'ZK-TARGET-UNASSIGNED',
      'Package is not contained in a configured Zuke workspace',
    );
  }
  final discovered =
      workspace ?? WorkspaceDiscovery().discover(workspaceRoot.path);
  final canonicalPackage = _canonical(packageDirectory);
  final targets = discovered.config.workspaceTargets.values.toList();
  final matchingTargets = <WorkspaceTarget>[];
  final matchingPackages = <String, WorkspacePackage>{};
  var missingConfiguredPackage = false;
  for (final target in targets) {
    for (final package in target.packages) {
      final configuredPath = Directory(
        '${workspaceRoot.path}${Platform.pathSeparator}${package.path}',
      );
      if (!configuredPath.existsSync()) {
        if (_canonical(configuredPath) == canonicalPackage) {
          missingConfiguredPackage = true;
        }
        continue;
      }
      if (_canonical(configuredPath) == canonicalPackage) {
        matchingTargets.add(target);
        matchingPackages[target.id] = package;
      }
    }
  }
  final uniqueTargets = {
    for (final target in matchingTargets) target.id: target,
  };
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
  if (uniqueTargets.isEmpty) {
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
  if (uniqueTargets.length != 1) {
    throw PlacementFailure(
      'ZK-TARGET-AMBIGUOUS',
      'Package belongs to multiple configured targets; pass --target',
      context: {'targets': uniqueTargets.keys.toList()..sort()},
    );
  }
  final target = uniqueTargets.values.single;
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

Directory? _findWorkspaceRoot(Directory start) {
  var current = Directory(_canonical(start));
  while (true) {
    if (File(
      '${current.path}${Platform.pathSeparator}zuke.yaml',
    ).existsSync()) {
      return current;
    }
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
