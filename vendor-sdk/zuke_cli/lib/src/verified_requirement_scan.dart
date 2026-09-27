import 'dart:io';

import 'package:zuke_frontend/zuke_frontend.dart';

import 'tooling/source_constants.dart';

/// Requirement IDs declared by `@VerifiesRequirement` plus the source files
/// that contributed them, so generate can index verification coverage and
/// invalidate the index when those sources change.
final class VerifiedRequirementScan {
  final Set<String> requirementIds;
  final List<String> sourcePaths;

  const VerifiedRequirementScan({
    required this.requirementIds,
    required this.sourcePaths,
  });
}

VerifiedRequirementScan scanVerifiedRequirements(
  String root,
  WorkspaceDiscoveryResult workspace,
) {
  final requirementIds = <String>{};
  final sourcePaths = <String>{};
  final constants = SourceConstants();

  // Two phases, and the order matters. Every file is scanned for constants
  // first, then every list alias is resolved against the complete value map,
  // and only then are annotations read. A list alias may reference constants
  // declared in a file that sorts after the alias, so reading annotations
  // during the walk would resolve it to nothing.
  //
  // Generated contracts are scanned first because annotations in the package
  // roots routinely reference IDs declared in the contract files.
  for (final file in generatedContractFiles(root, workspace)) {
    collectSourceConstants(file, constants);
  }
  final annotationFiles = <File>[];
  for (final file in packageDartFiles(root, workspace)) {
    collectSourceConstants(file, constants);
    if (!isGeneratedSource(file)) annotationFiles.add(file);
  }
  constants.resolveLists();

  for (final file in annotationFiles) {
    final ids = collectAnnotationIds(
      file,
      constants,
      annotationNames: const {'VerifiesRequirement'},
      idField: 'requirementIds',
    );
    if (ids.isEmpty) continue;
    requirementIds.addAll(ids);
    sourcePaths.add(file.absolute.path);
  }
  return VerifiedRequirementScan(
    requirementIds: requirementIds,
    sourcePaths: sourcePaths.toList()..sort(),
  );
}
