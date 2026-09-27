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
///
/// Matches the `guide_snippets` segment anywhere in the path rather than only
/// where a separator precedes it, so a workspace whose fixtures sit at the root
/// instead of under `test/` is still excluded.
bool isGuideSnippetFixture(String path) {
  final normalized = path.replaceAll('\\', '/');
  return '/$normalized/'.contains('/guide_snippets/');
}

/// A filesystem path reduced to a comparison key.
///
/// Forward slashes so keys built with either separator agree, and lower case on
/// Windows only, so differently cased spellings of the same path collide there
/// while remaining distinct on a case-sensitive filesystem.
///
/// Distinct from a plain slash conversion: use that where the spelling has to be
/// preserved, such as keying content the caller supplied.
String pathComparisonKey(String path) => Platform.isWindows
    ? path.replaceAll('\\', '/').toLowerCase()
    : path.replaceAll('\\', '/');

/// Normalizes a workspace-relative path to forward slashes.
///
/// Posix rules are applied explicitly (`p.url`): `p.normalize` would follow the
/// host's separator style, and these values feed digests, so a lock built on
/// Windows has to hash the same as one built on Linux. The separator
/// conversion happens first because posix style does not treat `\` as a
/// separator. `..` segments are resolved lexically, as the filesystem would.
///
/// Leading `./` and `/` are stripped, and an empty path stays empty. Posix
/// style also removes trailing and duplicated separators, so `a/b/`, `a//b`,
/// and `a/b` all normalize to `a/b` and comparing them by string equality is
/// safe.
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

/// Normalizes a workspace-relative *package* path, as declared by a
/// `zuke.yaml` target's `packages:` entries.
///
/// Delegates to [normalizeRelativePath] so the target scoping, the source-root
/// scan, and the index cannot disagree about what `./apps/api`, `apps/api/` and
/// `.\apps\api` all name. Those three used to normalize separately and
/// disagreed on the root-ish spellings, which is how a package declared as `./`
/// could be dropped by one reader and kept as the workspace root by another.
///
/// A path that reduces to nothing denotes the workspace root, which is how a
/// single-package workspace declares its only package, and that is what
/// [normalizeRelativePath] already returns for `.`, `./` and `./.`. An empty
/// input stays empty, and stays meaningful: it is the one spelling that means
/// "no path at all" rather than "the root".
String normalizePackagePath(String path) => normalizeRelativePath(path.trim());
