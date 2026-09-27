import 'package:zuke_frontend/zuke_frontend.dart';

import '../ir.dart';
import '../requirement_scopes.dart';
import '../tooling/dart_extractor/zuke_index.dart';
import 'validator.dart';

/// Reports declared requirements that no extracted source implements.
///
/// This is the CLI half of the editor's `zuke_unimplemented_requirement` rule:
/// the analyzer reports it while you type, and this reports it in
/// `zuke validate`/`zuke gate` so a CI gate can fail on it without anyone
/// reading the Problems pane. Both resolve target scoping through
/// [requirementAppliesTo], so they cannot disagree.
class ImplementationCoverageValidator {
  ValidationResult validate(
    WorkspaceDiscoveryResult workspace, {
    List<ExtractedSymbol> extractedSymbols = const [],
  }) {
    final messages = <ValidationMessage>[];
    final scopes = requirementTargetScopes(workspace);
    // One flat set of claims, not one bucket per annotation role. Whether a
    // requirement was implemented or presented does not change *whether* it is
    // implemented, so a per-role key would only invite a reader to believe the
    // two were checked separately.
    //
    // An entry is either a bare requirement ID — the symbol declared no target,
    // so it cannot be pinned to one and satisfies every target — or
    // `target|ID`.
    final implemented = <String>{};
    for (final symbol in extractedSymbols) {
      if (symbol.kind != ExtractedSymbolKind.requirementBoundary &&
          symbol.kind != ExtractedSymbolKind.presentationBoundary) {
        continue;
      }
      if (symbol.requirementIds.isEmpty) continue;
      final target = symbol.target;
      for (final id in symbol.requirementIds) {
        // A symbol with no target is not attributed to one, so it counts for
        // every target — the same lenient direction the editor rule takes.
        if (target == null || target.isEmpty) {
          implemented.add(id);
        } else {
          implemented.add('$target|$id');
        }
      }
    }

    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final id = rule.metadata.id;
        if (id == null || id.isEmpty) continue;
        final targets = scopes[id] ?? const <String>[];
        if (targets.isEmpty) {
          if (_implementedAnywhere(implemented, id)) continue;
        } else {
          final anyTargetImplemented = targets.any(
            (target) => _implementedIn(implemented, id, target),
          );
          if (anyTargetImplemented) continue;
        }
        messages.add(
          ValidationMessage(
            code: 'ZUKE-IMPL-001',
            message:
                'Requirement "$id" is declared'
                '${targets.isEmpty ? '' : ' for target(s) ${targets.join(", ")}'}'
                ' but no @ImplementsRequirement or @PresentsRequirement '
                'implements it',
            severity: Severity.warning,
            source: rule.metadata.source,
            remediation:
                'Add @ImplementsRequirement(["$id"]) (logic) or '
                '@PresentsRequirement(["$id"]) (UI) to a source file under a '
                'configured package root, or narrow the requirement\'s '
                'declared targets.',
          ),
        );
      }
    }
    return ValidationResult(warnings: messages);
  }

  bool _implementedAnywhere(Set<String> implemented, String requirementId) {
    if (implemented.contains(requirementId)) return true;
    return implemented.any((entry) => entry.endsWith('|$requirementId'));
  }

  bool _implementedIn(
    Set<String> implemented,
    String requirementId,
    String target,
  ) {
    // A bare entry is a symbol with no target, which cannot be pinned to one
    // and therefore satisfies every target.
    if (implemented.contains(requirementId)) return true;
    return implemented.contains('$target|$requirementId');
  }
}
