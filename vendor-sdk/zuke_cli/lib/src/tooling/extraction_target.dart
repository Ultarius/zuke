import 'dart:io';

import 'package:zuke_frontend/zuke_frontend.dart';

/// Resolves the active workspace target for a package before source
/// extraction. Provider annotations do not carry target metadata; the
/// workspace target is the only authoritative placement namespace.
String resolveExtractionTarget(String packageRoot, {String? requestedTarget}) {
  final workspaceRoot = _findWorkspaceRoot(Directory(packageRoot));
  if (workspaceRoot == null) {
    throw const FormatException(
      'ZK-PROVIDER-TARGET-AMBIGUOUS: package is not assigned to a configured target',
    );
  }
  final workspace = WorkspaceDiscovery().discover(workspaceRoot.path);
  final canonicalPackage = _canonical(Directory(packageRoot));
  final memberships = <String>[];
  for (final target in workspace.config.workspaceTargets.values) {
    for (final package in target.packages) {
      final candidate = _canonical(
        Directory(
          '${workspaceRoot.path}${Platform.pathSeparator}${package.path}',
        ),
      );
      if (candidate == canonicalPackage) memberships.add(target.id);
    }
  }
  final uniqueMemberships = memberships.toSet().toList()..sort();
  if (requestedTarget != null && requestedTarget.trim().isNotEmpty) {
    if (!uniqueMemberships.contains(requestedTarget)) {
      throw FormatException(
        'ZK-PROVIDER-TARGET-AMBIGUOUS: package is not a member of target '
        '"$requestedTarget"',
      );
    }
    return requestedTarget;
  }
  if (uniqueMemberships.length != 1) {
    throw FormatException(
      'ZK-PROVIDER-TARGET-AMBIGUOUS: package belongs to '
      '${uniqueMemberships.isEmpty ? 'no' : 'multiple'} configured targets '
      '${uniqueMemberships.join(', ')}; pass --target explicitly',
    );
  }
  return uniqueMemberships.single;
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
    // Windows paths are case-insensitive; POSIX paths are not. Lowercasing a
    // Linux temporary directory such as `/tmp/zuke-plugin-GKTOEW` changes the
    // path being inspected and makes an otherwise valid workspace disappear.
    return Platform.isWindows ? resolved.toLowerCase() : resolved;
  } catch (_) {
    final absolute = directory.absolute.path.replaceAll('\\', '/');
    return Platform.isWindows ? absolute.toLowerCase() : absolute;
  }
}
