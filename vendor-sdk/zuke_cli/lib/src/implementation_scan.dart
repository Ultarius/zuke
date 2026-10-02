import 'package:zuke_frontend/zuke_frontend.dart';

import 'annotation_claim.dart';
import 'workspace_annotation_scan.dart';

export 'annotation_claim.dart';

/// Requirement, control and binding IDs that workspace code claims to
/// implement, plus the source files that contributed them.
///
/// Projected from the same resolved scan as verification coverage, so an
/// implementation edit invalidates the index in the same way a test edit does.
///
/// Test roots are scanned as well as source roots, and deliberately so. A
/// contract test that stands in for the implementation is a real claim, and
/// excluding `test/` would report a requirement as unimplemented when the team
/// considers it covered. The trade is that a claim can come from a test helper,
/// which the index makes visible through [claims] rather than hiding. The one
/// exclusion is documentation fixtures under `test/guide_snippets/`, which
/// restate annotated code in prose; `packageDartFiles` applies the same
/// `isGuideSnippetFixture` filter extraction does, so a snippet in the guide
/// cannot satisfy coverage.
final class ImplementationScan {
  /// Claimed by `@ImplementsRequirement` or `@PresentsRequirement`.
  final Set<String> implementedRequirementIds;

  /// Claimed by `@PresentsRequirement` only.
  final Set<String> presentedRequirementIds;

  /// Claimed by `@ProvidesControl`.
  final Set<String> providedControlIds;

  /// Claimed by `@ZukeBinding`.
  final Set<String> implementedBindingIds;

  /// Every claim, with the annotation that made it and the file it came from.
  ///
  /// Not part of the index: it exists so a caller — and the tests — can see
  /// *which* file made a claim, not just that one was made.
  final List<ImplementationClaim> claims;

  /// Files that contributed at least one claim.
  final List<String> sourcePaths;

  const ImplementationScan({
    required this.implementedRequirementIds,
    required this.presentedRequirementIds,
    required this.providedControlIds,
    required this.implementedBindingIds,
    required this.claims,
    required this.sourcePaths,
  });

  factory ImplementationScan.fromScan(WorkspaceAnnotationScan scan) {
    final claims = scan.claims
        .where((claim) => claim.kind != ImplementationKind.verified)
        .toList(growable: false);
    Set<String> ids(Set<ImplementationKind> kinds) => {
      for (final claim in claims)
        if (kinds.contains(claim.kind)) claim.id,
    };
    return ImplementationScan(
      implementedRequirementIds: ids({
        ImplementationKind.implemented,
        ImplementationKind.presented,
      }),
      presentedRequirementIds: ids({ImplementationKind.presented}),
      providedControlIds: ids({ImplementationKind.control}),
      implementedBindingIds: ids({ImplementationKind.binding}),
      claims: claims,
      sourcePaths: scan.contributingPaths(claims),
    );
  }

  static const empty = ImplementationScan(
    implementedRequirementIds: {},
    presentedRequirementIds: {},
    providedControlIds: {},
    implementedBindingIds: {},
    claims: [],
    sourcePaths: [],
  );
}

/// Convenience entry point for callers that only need implementation coverage.
Future<ImplementationScan> scanImplementations(
  String root,
  WorkspaceDiscoveryResult workspace, {
  Map<String, String> pendingContent = const {},
  Set<String> generatedPaths = const {},
}) async => ImplementationScan.fromScan(
  await scanWorkspaceAnnotations(
    root,
    workspace,
    pendingContent: pendingContent,
    generatedPaths: generatedPaths,
  ),
);
