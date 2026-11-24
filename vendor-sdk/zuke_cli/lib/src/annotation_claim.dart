import 'implementation_claims.dart';

/// Which Zuke annotation declared implementation or verification coverage.
///
/// The distinction matters to callers: a presented requirement is implemented
/// through the UI while an implemented one is implemented in logic, and a
/// provided control or bound binding is a different obligation again.
enum ImplementationKind { implemented, presented, control, binding, verified }

/// One annotation's contribution to implementation or verification coverage.
///
/// Carries the target that owns the contributing file, because a claim without
/// one cannot answer whether *this* target is covered — a Flutter package
/// claiming a `backend`-only requirement is not implementing it.
final class ImplementationClaim {
  final ImplementationKind kind;

  /// The claimed requirement, control, or binding ID.
  final String id;

  /// The target owning the file that made the claim, or null when the file
  /// cannot be attributed to a configured package.
  final String? target;

  /// Workspace-relative path of the file that made the claim.
  final String sourcePath;

  const ImplementationClaim({
    required this.kind,
    required this.id,
    required this.sourcePath,
    this.target,
  });

  /// The index form, which keeps the target and drops the local-only detail.
  ZukeImplementationClaim toIndexClaim() =>
      ZukeImplementationClaim(id: id, target: target);

  @override
  String toString() =>
      '${kind.name} $id${target == null ? '' : ' ($target)'} in $sourcePath';
}
