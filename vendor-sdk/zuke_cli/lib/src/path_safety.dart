import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns a normalized path with its existing ancestor resolved through the
/// filesystem. This keeps comparisons correct when Windows supplies an 8.3
/// alias for a path whose existing ancestor resolves to its long form.
String canonicalComparablePath(String path) {
  var candidate = p.normalize(p.absolute(path));
  final unresolved = <String>[];
  while (FileSystemEntity.typeSync(candidate, followLinks: false) ==
      FileSystemEntityType.notFound) {
    final parent = p.dirname(candidate);
    if (parent == candidate) {
      return candidate;
    }
    unresolved.insert(0, p.basename(candidate));
    candidate = parent;
  }

  final type = FileSystemEntity.typeSync(candidate, followLinks: false);
  final resolved = type == FileSystemEntityType.directory
      ? Directory(candidate).resolveSymbolicLinksSync()
      : File(candidate).resolveSymbolicLinksSync();
  var comparable = resolved;
  for (final part in unresolved) {
    comparable = p.join(comparable, part);
  }
  return p.normalize(comparable);
}

/// Tests whether [child] is [parent] or lies below it after path resolution.
bool pathEqualsOrWithin(String parent, String child) {
  final resolvedParent = canonicalComparablePath(parent);
  final resolvedChild = canonicalComparablePath(child);
  return p.equals(resolvedParent, resolvedChild) ||
      p.isWithin(resolvedParent, resolvedChild);
}
