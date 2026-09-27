import 'dart:io';

import 'package:zuke_frontend/zuke_frontend.dart';

import 'tooling/source_constants.dart';

/// Which Zuke annotation declared an implementation, and the IDs it claimed.
///
/// The distinction matters to callers: a presented requirement is implemented
/// through the UI while an implemented one is implemented in logic, and a
/// provided control or bound binding is a different obligation again.
enum ImplementationKind { implemented, presented, control, binding }

/// One annotation's contribution to implementation coverage.
final class ImplementationClaim {
  final ImplementationKind kind;
  final String id;

  const ImplementationClaim(this.kind, this.id);
}

/// Requirement, control and binding IDs that workspace code claims to
/// implement, plus the source files that contributed them.
///
/// Generated at the same time as the verified-requirement scan and from the
/// same const-resolution machinery, so an implementation edit invalidates the
/// analyzer index in exactly the same way a test edit does.
///
/// Test roots are scanned as well as source roots, and deliberately so. A
/// contract test that stands in for the implementation is a real claim, and
/// excluding `test/` would report a requirement as unimplemented when the team
/// considers it covered. The trade is that a claim can come from a test helper,
/// which the index makes visible through [claims] rather than hiding. Guide
/// snippets are the exception: they are documentation, not code, and
/// `isGuideSnippetFixture` excludes them.
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

  static const empty = ImplementationScan(
    implementedRequirementIds: {},
    presentedRequirementIds: {},
    providedControlIds: {},
    implementedBindingIds: {},
    claims: [],
    sourcePaths: [],
  );
}

ImplementationScan scanImplementations(
  String root,
  WorkspaceDiscoveryResult workspace,
) {
  final implemented = <String>{};
  final presented = <String>{};
  final controls = <String>{};
  final bindings = <String>{};
  final claims = <ImplementationClaim>[];
  final sourcePaths = <String>{};
  final constants = SourceConstants();

  // Two phases, and the order matters: scan every file for constants, resolve
  // every list alias against the complete value map, then read annotations. A
  // list alias may reference constants declared in a file that sorts after it.
  //
  // Generated contracts are scanned first so annotations that reference
  // contract constants resolve.
  for (final file in generatedContractFiles(root, workspace)) {
    collectSourceConstants(file, constants);
  }
  final sources = <File>[];
  for (final file in packageDartFiles(root, workspace)) {
    collectSourceConstants(file, constants);
    // A generated contract declares IDs, it does not implement them. Counting
    // its own constants would make every requirement look implemented.
    if (!isGeneratedSource(file)) sources.add(file);
  }
  constants.resolveLists();

  for (final file in sources) {
    var contributed = false;

    final logicIds = collectAnnotationIds(
      file,
      constants,
      annotationNames: const {'ImplementsRequirement'},
      idField: 'requirementIds',
    );
    implemented.addAll(logicIds);
    for (final id in logicIds) {
      claims.add(ImplementationClaim(ImplementationKind.implemented, id));
    }
    contributed |= logicIds.isNotEmpty;

    final uiIds = collectAnnotationIds(
      file,
      constants,
      annotationNames: const {'PresentsRequirement'},
      idField: 'requirementIds',
    );
    presented.addAll(uiIds);
    // A presented requirement is implemented too: it is a different
    // obligation, not a lesser one.
    implemented.addAll(uiIds);
    for (final id in uiIds) {
      claims.add(ImplementationClaim(ImplementationKind.presented, id));
    }
    contributed |= uiIds.isNotEmpty;

    final controlIds = collectAnnotationIds(
      file,
      constants,
      annotationNames: const {'ProvidesControl'},
      idField: 'controlIds',
    );
    controls.addAll(controlIds);
    for (final id in controlIds) {
      claims.add(ImplementationClaim(ImplementationKind.control, id));
    }
    contributed |= controlIds.isNotEmpty;

    final bindingIds = collectAnnotationIds(
      file,
      constants,
      annotationNames: const {'ZukeBinding'},
      idField: 'bindingId',
      single: true,
    );
    bindings.addAll(bindingIds);
    for (final id in bindingIds) {
      claims.add(ImplementationClaim(ImplementationKind.binding, id));
    }
    contributed |= bindingIds.isNotEmpty;

    if (contributed) sourcePaths.add(file.absolute.path);
  }

  return ImplementationScan(
    implementedRequirementIds: implemented,
    presentedRequirementIds: presented,
    providedControlIds: controls,
    implementedBindingIds: bindings,
    claims: claims,
    sourcePaths: sourcePaths.toList()..sort(),
  );
}
