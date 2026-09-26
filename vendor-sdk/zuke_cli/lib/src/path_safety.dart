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

/// Documentation fixtures under `test/guide_snippets/` intentionally restate
/// production annotations for the integration guide. They are not
/// implementation sources and must not contribute binding identities.
bool isGuideSnippetFixture(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.contains('/guide_snippets/');
}

/// Normalizes a workspace-relative path to forward slashes.
///
/// Posix rules are applied explicitly (`p.url`): `p.normalize` would follow the
/// host's separator style, and these values feed digests, so a lock built on
/// Windows has to hash the same as one built on Linux. The separator
/// conversion happens first because posix style does not treat `\` as a
/// separator. `..` segments are resolved lexically, as the filesystem would.
///
/// Not for absolute paths, and not a replacement for [canonicalComparablePath],
/// which resolves symlinks through the filesystem.
String normalizeRelativePath(String path) {
  final prefixed = path.replaceAll('\\', '/');
  // `p.url.normalize` collapses the empty path to `.`.
  if (prefixed.isEmpty) return '';
  var normalized = p.url.normalize(prefixed);
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  while (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  return normalized;
}
