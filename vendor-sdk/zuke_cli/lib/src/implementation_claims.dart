import 'path_safety.dart';

/// One claim that a requirement is implemented, and which target made it.
///
/// The target is part of the claim because a flat set of implemented IDs loses
/// the one fact that matters: a `flutter` package claiming a `backend`-only
/// requirement has not implemented it. The editor and `zuke validate` have to
/// reach the same conclusion, and they only can if both can see the target.
final class ZukeImplementationClaim {
  /// The requirement, control, or binding ID claimed.
  final String id;

  /// The target owning the file that made the claim, or null when the file
  /// cannot be attributed to a configured package.
  ///
  /// Null means "unpinned", and an unpinned claim satisfies every target — the
  /// same lenient direction `requirementAppliesTo` takes for a file whose target
  /// is unknown.
  final String? target;

  const ZukeImplementationClaim({required this.id, this.target});

  Map<String, Object?> toJson() => {
    'id': id,
    if (target != null) 'target': target,
  };

  /// Reads one claim, returning null when its ID is missing and rejecting an
  /// explicitly malformed target rather than treating it as an unpinned claim.
  static ZukeImplementationClaim? fromJson(Map<Object?, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final target = json['target'];
    if (json.containsKey('target') &&
        (target is! String || target.trim().isEmpty)) {
      throw const FormatException('Invalid implementation claim target');
    }
    return ZukeImplementationClaim(id: id, target: target as String?);
  }

  @override
  String toString() => target == null ? id : '$target|$id';
}

/// Whether [claims] satisfy [requirementId] for [targetId].
///
/// The single definition of that rule, shared by the editor rule and the CLI
/// validator so the two cannot disagree. An unpinned claim satisfies every
/// target, and so does any claim when the file being judged is itself
/// unattributable: under-reporting a gap is recoverable, hiding one because
/// scoping metadata was missing is not.
bool claimsSatisfyRequirement(
  Iterable<ZukeImplementationClaim> claims,
  String requirementId,
  String? targetId,
) {
  if (targetId == null) return claims.any((claim) => claim.id == requirementId);
  for (final claim in claims) {
    if (claim.id != requirementId) continue;
    if (claim.target == null || claim.target == targetId) return true;
  }
  return false;
}

/// The target that owns [relativePath] under [packageTargets], or null when no
/// configured package contains it.
///
/// Longest matching package path wins, so a nested package resolves to its own
/// target rather than the workspace root's. Case is folded on Windows only;
/// on case-sensitive filesystems differently cased packages remain distinct.
///
/// Shared with the implementation scan, which has to attribute a claim to a
/// target the same way the index later judges it.
String? targetForWorkspacePath(
  Map<String, String> packageTargets,
  String relativePath,
) {
  final owner = _owningPackageKey(packageTargets, relativePath);
  return owner == null ? null : packageTargets[owner];
}

/// Whether [normalizedPath] denotes the workspace root rather than a directory
/// inside it.
///
/// A single-package workspace records its one package as `.`, and that package
/// owns the whole workspace. Matching `.` as a literal directory prefix would
/// match no path at all, and a file whose target cannot be attributed is
/// deliberately reported as *unscoped*, so the mistake does not look like a
/// miss, it looks like every requirement applying everywhere. That is how
/// `backend` requirements ended up reported in a Flutter app.
bool isWorkspaceRootPackage(String normalizedPath) => normalizedPath == '.';

/// The configured package containing [relativePath] under [packageIds], or null
/// when no configured package contains it.
///
/// The longest-match rule is [targetForWorkspacePath]'s, resolved by the same
/// helper rather than a second copy of it. A slot names a `sourcePackage` as
/// well as a target, and a target alone cannot tell two packages of one target
/// apart. If the two lookups were ever to disagree, the same file would be
/// judged against one package while its target came from another, and the editor
/// would call a slot unattributable where `zuke validate` called it decided —
/// which is precisely the drift one shared verdict engine exists to prevent.
String? packageIdForWorkspacePath(
  Map<String, String> packageIds,
  String relativePath,
) {
  final owner = _owningPackageKey(packageIds, relativePath);
  return owner == null ? null : packageIds[owner];
}

/// The key of the configured package path owning [relativePath], or null when
/// none does.
///
/// One implementation of the longest-match rule, because two callers depend on
/// it agreeing exactly. A package declared at the workspace root owns every path
/// in the workspace, so it matches anything, but it still loses to a longer
/// nested path; that is what keeps a multi-package workspace resolving
/// `apps/api` to its own target rather than the root's.
String? _owningPackageKey(Map<String, String> byPath, String relativePath) {
  final normalized = pathComparisonKey(relativePath);
  String? best;
  var bestLength = -1;
  for (final key in byPath.keys) {
    final path = pathComparisonKey(normalizePackagePath(key));
    final matches =
        isWorkspaceRootPackage(path) ||
        normalized == path ||
        normalized.startsWith(path.endsWith('/') ? path : '$path/');
    if (!matches) continue;
    // The root is a fallback, not a one-character directory prefix.
    final specificity = isWorkspaceRootPackage(path) ? 0 : path.length;
    if (specificity == bestLength && byPath[best] != byPath[key]) {
      throw FormatException('Conflicting package owners for "$path"');
    }
    if (specificity > bestLength) {
      best = key;
      bestLength = specificity;
    }
  }
  return best;
}

/// Claims deduplicated and ordered deterministically, so regenerating an
/// unchanged workspace produces an identical index.
List<ZukeImplementationClaim> normalizedImplementationClaims(
  Iterable<ZukeImplementationClaim> claims,
) {
  final byTarget = <String?, Map<String, ZukeImplementationClaim>>{};
  for (final claim in claims) {
    if (claim.id.isEmpty) continue;
    (byTarget[claim.target] ??= {}).putIfAbsent(claim.id, () => claim);
  }
  final ordered = byTarget.values.expand((claims) => claims.values).toList()
    ..sort((left, right) {
      final byTarget = (left.target ?? '').compareTo(right.target ?? '');
      return byTarget != 0 ? byTarget : left.id.compareTo(right.id);
    });
  return ordered;
}

/// Reads one of the index's claim arrays, rejecting anything malformed rather
/// than silently dropping a claim.
///
/// A dropped claim would be reported as an unimplemented or unverified
/// requirement, so a corrupt index has to fail loudly instead of quietly
/// inventing a gap.
List<ZukeImplementationClaim> claimsFromJson(
  Map<Object?, Object?> json,
  String field,
) {
  final value = json[field];
  if (value == null) return const [];
  if (value is! List) {
    throw FormatException('Analyzer index $field invalid');
  }
  final parsed = <ZukeImplementationClaim>[];
  for (final entry in value) {
    if (entry is! Map<Object?, Object?>) {
      throw FormatException('Analyzer index $field entry invalid');
    }
    final claim = ZukeImplementationClaim.fromJson(entry);
    if (claim == null) {
      throw FormatException('Analyzer index $field entry invalid');
    }
    parsed.add(claim);
  }
  return normalizedImplementationClaims(parsed);
}

/// Claims reconciled against the flat implemented sets, which are the only
/// record an index written before claims existed carries.
///
/// The two representations are not independent facts. Claims are authoritative
/// because only they say *which* target made a claim, but when an index has none
/// — an older generated index, or a hand-written fixture — the flat set is all
/// there is. Backfilling it as unpinned claims keeps the two from ever
/// disagreeing, and unpinned is the lenient direction: it satisfies every
/// target, so a reader that lacks target data under-reports rather than
/// inventing a gap.
///
/// An index that has claims is left exactly as written. The flat sets are not
/// used to add to them, so a genuinely unimplemented requirement cannot be
/// rescued by a stale set.
List<ZukeImplementationClaim> reconcileClaims({
  required List<ZukeImplementationClaim> claims,
  required Set<String> implementedRequirements,
  required Set<String> presentedRequirements,
  required Set<String> providedControls,
  required Set<String> implementedBindings,
}) {
  if (claims.isNotEmpty) return claims;
  return normalizedImplementationClaims([
    for (final id in {
      ...implementedRequirements,
      ...presentedRequirements,
      ...providedControls,
      ...implementedBindings,
    })
      ZukeImplementationClaim(id: id),
  ]);
}
