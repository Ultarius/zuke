import 'package:zuke_frontend/zuke_frontend.dart';

import 'annotation_claim.dart';
import 'workspace_annotation_scan.dart';

/// Requirement IDs declared by `@VerifiesRequirement` plus the source files
/// that contributed them, so generate can index verification coverage and
/// invalidate the index when those sources change.
final class VerifiedRequirementScan {
  final Set<String> requirementIds;
  final List<String> sourcePaths;

  /// Each verification, with the target owning the test file.
  ///
  /// Symmetric with [ImplementationScan.claims]. Dropping these would leave
  /// verification target-blind, and a backend-only test would then satisfy a
  /// Flutter package's requirement — the editor would report a missing test
  /// that `zuke validate` considers covered.
  final List<ImplementationClaim> claims;

  factory VerifiedRequirementScan.fromScan(WorkspaceAnnotationScan scan) {
    final claims = scan.claims
        .where((claim) => claim.kind == ImplementationKind.verified)
        .toList();
    return VerifiedRequirementScan(
      requirementIds: {for (final claim in claims) claim.id},
      sourcePaths: scan.contributingPaths(claims),
      claims: claims,
    );
  }

  const VerifiedRequirementScan({
    required this.requirementIds,
    required this.sourcePaths,
    this.claims = const [],
  });
}

/// Convenience entry point for callers that only need verification coverage.
Future<VerifiedRequirementScan> scanVerifiedRequirements(
  String root,
  WorkspaceDiscoveryResult workspace, {
  Map<String, String> pendingContent = const {},
  Set<String> generatedPaths = const {},
}) async => VerifiedRequirementScan.fromScan(
  await scanWorkspaceAnnotations(
    root,
    workspace,
    pendingContent: pendingContent,
    generatedPaths: generatedPaths,
  ),
);
