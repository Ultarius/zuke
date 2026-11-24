import 'dart:io';

import 'package:path/path.dart' as p;

/// Host-aware comparison for already normalized workspace-relative paths.
///
/// Distinct from a plain slash conversion: use that where the spelling has to be
/// preserved, such as keying content the caller supplied.
///
/// **Duplicated in `zuke_cli` on purpose.** This package reads the configuration,
/// so a claim on a package path has to be normalized before it can be checked,
/// which means it needs this too. They cannot share one definition while
/// `zuke_cli` depends on a published version of this package: a fresh resolution
/// would fetch whichever version is on pub.dev, and importing a symbol that only
/// exists in an unreleased one fails to compile. The copies are held in step by
/// `zuke_cli`'s `test/path_agreement_test.dart`, which asserts they produce the
/// same answer for the same input.
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
/// Windows has to hash the same as one built on Linux. The separator conversion
/// happens first because posix style does not treat `\` as a separator. `..`
/// segments are resolved lexically, as the filesystem would.
///
/// Leading `./` and `/` are stripped, and an empty path stays empty. Posix style
/// also removes trailing and duplicated separators, so `a/b/`, `a//b`, and `a/b`
/// all normalize to `a/b` and comparing them by string equality is safe.
///
/// Not for absolute paths, and not a replacement for a symlink-resolving
/// canonicalizer.
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
/// `.\apps\api` all name. Those three used to normalize separately and disagreed
/// on the root-ish spellings, which is how a package declared as `./` could be
/// dropped by one reader and kept as the workspace root by another.
///
/// A path that reduces to nothing denotes the workspace root, which is how a
/// single-package workspace declares its only package, and that is what
/// [normalizeRelativePath] already returns for `.`, `./` and `./.`. An empty input
/// stays empty, and stays meaningful: it is the one spelling that means "no path
/// at all" rather than "the root".
String normalizePackagePath(String path) => normalizeRelativePath(path.trim());

/// One package's claim on a normalized package path.
///
/// A named type rather than a record because it carries identity across two
/// questions — which package owns this path, and which target declared it — and
/// the target is reported in a conflict message without being part of the
/// identity that decides the conflict.
final class WorkspacePackageClaim {
  const WorkspacePackageClaim(this.packageId, this.target);

  final String packageId;

  /// The target that declared the package, for diagnostics only. A package may be
  /// declared by more than one target, so this never participates in the
  /// conflict test.
  final String target;

  @override
  String toString() => 'package "$packageId" (target "$target")';
}

/// Checks ownership before any normalized path can overwrite a map entry.
///
/// **What conflicts.** A normalized path may be claimed by exactly one *package
/// id*. Two spellings that normalize alike for the same package are harmless
/// aliases; two different packages claiming one path is a configuration that
/// cannot be honoured and is rejected at the point it is read, rather than
/// silently resolved by whichever entry the map happened to keep.
///
/// **What deliberately does not conflict.** A package declared by more than one
/// target. Multi-target membership is a supported configuration — it is what
/// lets a shared package be verified as both a backend and a Flutter
/// implementation, and the ambiguity is meaningful information that
/// `extraction_target.dart` reports as `ZK-TARGET-AMBIGUOUS`. Rejecting it here
/// would remove a state the rest of the toolchain is built to explain.
final class WorkspacePackageOwnership {
  final _claims = <String, WorkspacePackageClaim>{};

  /// Records that [packageId] owns [path] under [target], and returns the
  /// normalized spelling every consumer should key on.
  ///
  /// Throws when a *different* package already owns that path. The first claim
  /// is kept, so the conflict message names the same pair whichever order the
  /// configuration listed them in.
  String claim(String path, String target, String packageId) {
    final normalized = normalizePackagePath(path);
    final key = pathComparisonKey(normalized);
    final previous = _claims[key];
    if (previous != null && previous.packageId != packageId) {
      throw FormatException(
        'Package path "$normalized" has conflicting owners: $previous and '
        'package "$packageId" (target "$target"). One path cannot belong to '
        'two packages.',
      );
    }
    _claims.putIfAbsent(key, () => WorkspacePackageClaim(packageId, target));
    return normalized;
  }
}
