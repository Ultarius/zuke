import 'package:zuke_frontend/zuke_frontend.dart';

import 'path_safety.dart';

/// Package path to target ID for every configured package.
///
/// The single source of that mapping, so the implementation scan and the index
/// cannot disagree about which target owns a file.
Map<String, String> workspacePackageTargets(
  WorkspaceDiscoveryResult workspace,
) {
  final result = <String, String>{};
  for (final entry in workspace.config.workspaceTargets.entries) {
    for (final package in entry.value.packages) {
      final path = normalizePackagePath(package.path);
      if (path.isEmpty) continue;
      result[path] = entry.key;
    }
  }
  return result;
}

/// The targets each declared requirement ID applies to.
///
/// Specifications declare `targets:` once per feature and rarely repeat it on a
/// rule, so a rule inherits its feature's targets unless it narrows them. Every
/// feature and rule ID is a key, including one whose effective target list is
/// empty: the empty list is dropped when the map reaches the index, so that "no
/// declared targets" and "declared no targets" are the same thing downstream —
/// unscoped, and therefore applicable everywhere.
///
/// Both the analyzer index and the CLI validator resolve scopes through this
/// function, so the editor and `zuke validate` can never disagree about which
/// target a requirement belongs to.
Map<String, List<String>> requirementTargetScopes(
  WorkspaceDiscoveryResult workspace,
) {
  final scopes = <String, List<String>>{};
  for (final feature in workspace.data.features) {
    final featureTargets = feature.metadata.targets ?? const <String>[];
    final featureId = feature.metadata.id;
    if (featureId != null && featureId.isNotEmpty) {
      scopes[featureId] = _normalized(featureTargets);
    }
    for (final rule in feature.rules) {
      final ruleId = rule.metadata.id;
      if (ruleId == null || ruleId.isEmpty) continue;
      // A rule that narrows its targets wins; otherwise it inherits the
      // feature's, which is the common case.
      final declared = rule.metadata.targets;
      final effective = declared != null && declared.isNotEmpty
          ? declared
          : featureTargets;
      scopes[ruleId] = _normalized(effective);
    }
  }
  return scopes;
}

List<String> _normalized(List<String> targets) {
  final result =
      targets
          .map((target) => target.replaceAll('\\', '/').trim())
          .where((target) => target.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return List.unmodifiable(result);
}
