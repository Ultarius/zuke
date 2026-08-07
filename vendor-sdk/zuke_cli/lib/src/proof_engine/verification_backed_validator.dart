import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'validator.dart';

/// Verifies Flutter/application controls from a resolved provider declaration
/// and current passing execution evidence. This deliberately does not claim
/// all-path dominance: the resulting assurance state is [ProofStatus.verified].
class VerificationBackedValidator {
  ValidationResult validate(
    WorkspaceDiscoveryResult workspace,
    List<AdapterOutput> outputs,
    List<EvidenceRecord> evidence,
  ) {
    final proofs = <ControlProofResult>[];
    final providers = <_Provider>[];
    for (final output in outputs) {
      for (final symbol in output.symbols) {
        if (symbol.kind == 'controlProvider') {
          providers.add(_Provider(symbol, output.completeness));
        }
      }
    }
    for (final expected in _expected(workspace)) {
      final definition =
          workspace.data.controls[expected.controlId] ?? const {};
      final candidates = providers
          .where(
            (provider) =>
                provider.symbol.controlIds.contains(expected.controlId) &&
                provider.symbol.target == expected.target &&
                provider.symbol.variant == expected.variant,
          )
          .toList();
      final allowedKinds =
          (definition['acceptableProviderKinds'] as List? ?? const [])
              .map((value) => value.toString())
              .toSet();
      final requiredLayers = (definition['requiredLayers'] as List? ?? const [])
          .map((value) => value.toString())
          .toSet();
      final validProviders = candidates.where((provider) {
        final kind = _wire(provider.symbol.providerKind);
        final layer = _wire(provider.symbol.layer);
        return (allowedKinds.isEmpty || allowedKinds.contains(kind)) &&
            (requiredLayers.isEmpty || requiredLayers.contains(layer));
      }).toList();
      final matchedEvidence = evidence.where((record) {
        return record.requirementId == expected.requirementId &&
            record.target == expected.target &&
            record.variant == expected.variant &&
            record.status == EvidenceStatus.passed &&
            record.controlIds.contains(expected.controlId) &&
            _hasRequiredDigests(record);
      }).toList();
      final diagnostics = <String>[];
      if (validProviders.isEmpty) {
        diagnostics.add(
          'No resolved provider matches control kind, layer, target, and variant',
        );
      }
      final providedLayers = validProviders
          .map((provider) => _wire(provider.symbol.layer))
          .whereType<String>()
          .toSet();
      final missingLayers = requiredLayers.difference(providedLayers);
      if (missingLayers.isNotEmpty) {
        final ordered = missingLayers.toList()..sort();
        diagnostics.add(
          'Required defense-in-depth layers have no qualifying provider: '
          '${ordered.join(', ')}',
        );
      }
      final completeProviders = validProviders.where(_isComplete).toList();
      if (validProviders.isNotEmpty && completeProviders.isEmpty) {
        diagnostics.add(
          'Resolved annotation extraction is incomplete; verification-backed assurance is unavailable',
        );
      }
      if (matchedEvidence.isEmpty) {
        diagnostics.add('No current passing evidence references this control');
      }
      proofs.add(
        ControlProofResult(
          requirementId: expected.requirementId,
          controlId: expected.controlId,
          target: expected.target,
          variant: expected.variant,
          semantics: CoverageSemantics.verificationBacked,
          status: diagnostics.isEmpty
              ? ProofStatus.verified
              : ProofStatus.missing,
          providerIds:
              completeProviders
                  .map((provider) => provider.symbol.symbolId)
                  .toList()
                ..sort(),
          completeness: completeProviders.isEmpty
              ? const {}
              : {
                  'annotationTargets': CompletenessValue.complete,
                  'generatedParts': CompletenessValue.complete,
                },
          evidenceDigests:
              matchedEvidence
                  .expand((record) => record.digests.values)
                  .toSet()
                  .toList()
                ..sort(),
          diagnostics: diagnostics,
        ),
      );
    }
    return ValidationResult(controlProofs: proofs);
  }

  bool _isComplete(_Provider provider) =>
      provider.completeness.annotationTargets == CompletenessValue.complete &&
      provider.completeness.generatedParts == CompletenessValue.complete;

  List<_Expected> _expected(WorkspaceDiscoveryResult workspace) {
    final result = <String, _Expected>{};
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final requirementId = rule.metadata.id;
        if (requirementId == null) continue;
        final refs = <ParsedControlRef>[...?rule.metadata.requires];
        final profile = rule.metadata.securityProfile;
        if (profile != null) {
          for (final policy in workspace.data.policies.values) {
            final profiles = policy['securityProfiles'];
            final definition = profiles is Map ? profiles[profile] : null;
            final requires = definition is Map ? definition['requires'] : null;
            if (requires is List) {
              refs.addAll(
                requires.whereType<Map>().map(
                  (raw) => ParsedControlRef(
                    kind: raw['kind']?.toString() ?? 'control',
                    id: raw['id']!.toString(),
                    target: raw['target']?.toString() ?? 'backend',
                    cardinality: raw['cardinality']?.toString() ?? 'oneOrMore',
                    variant: raw['variant']?.toString() ?? 'default',
                  ),
                ),
              );
            }
          }
        }
        for (final ref in refs.where((ref) => ref.kind == 'control')) {
          final semantic =
              workspace.data.controls[ref.id]?['coverageSemantics'];
          if (semantic != 'verification-backed') continue;
          final expected = _Expected(
            requirementId,
            ref.id,
            ref.target,
            ref.variant,
          );
          result[expected.key] = expected;
        }
      }
    }
    return result.values.toList();
  }

  bool _hasRequiredDigests(EvidenceRecord record) =>
      const [
        'source',
        'contract',
        'mapping',
        'specificationIndex',
        'result',
      ].every(
        (key) => RegExp(
          r'^sha256:[a-f0-9]{64}$',
        ).hasMatch(record.digests[key] ?? ''),
      );

  String? _wire(String? value) => value?.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)}-${match.group(2)!.toLowerCase()}',
  );
}

class _Provider {
  final ExtractedSymbol symbol;
  final AdapterCompleteness completeness;
  const _Provider(this.symbol, this.completeness);
}

class _Expected {
  final String requirementId;
  final String controlId;
  final String target;
  final String variant;
  const _Expected(
    this.requirementId,
    this.controlId,
    this.target,
    this.variant,
  );
  String get key => '$requirementId|$controlId|$target|$variant';
}
