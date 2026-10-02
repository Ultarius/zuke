import 'package:zuke_frontend/zuke_frontend.dart';

import '../implementation_claims.dart';
import '../ir.dart';
import '../requirement_scopes.dart';
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
    // Flattened into the index's claim type so the coverage decision below is
    // literally the same function the editor rule calls. Encoding the target into
    // a string key instead would be free to drift from it.
    final implemented = <ZukeImplementationClaim>[];
    for (final symbol in extractedSymbols) {
      if (symbol.kind != ExtractedSymbolKind.requirementBoundary &&
          symbol.kind != ExtractedSymbolKind.presentationBoundary) {
        continue;
      }
      if (symbol.requirementIds.isEmpty) continue;
      for (final id in symbol.requirementIds) {
        implemented.add(
          ZukeImplementationClaim(
            id: id,
            target: symbol.target == null || symbol.target!.isEmpty
                ? null
                : symbol.target,
          ),
        );
      }
    }

    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final id = rule.metadata.id;
        if (id == null || id.isEmpty) continue;
        final targets = scopes[id] ?? const <String>[];
        final missingTargets = targets
            .where(
              (target) => !claimsSatisfyRequirement(implemented, id, target),
            )
            .toList();
        if (targets.isEmpty
            ? claimsSatisfyRequirement(implemented, id, null)
            : missingTargets.isEmpty) {
          continue;
        }
        messages.add(
          ValidationMessage(
            code: 'ZUKE-IMPL-001',
            message:
                'Requirement "$id" is declared'
                '${targets.isEmpty ? '' : ' for target(s) ${missingTargets.join(", ")}'}'
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
}
