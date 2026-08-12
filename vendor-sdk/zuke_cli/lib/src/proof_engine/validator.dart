import 'package:zuke_frontend/zuke_frontend.dart';
import 'identity_validator.dart';
import 'reference_resolver.dart';
import 'cardinality_validator.dart';
import 'evidence_validator.dart';
import 'source_mapping_validator.dart';
import 'dominance_validator.dart';
import 'verification_backed_validator.dart';
import '../ir.dart' as ir;
import '../ir.dart';

typedef ValidationMessage = ir.IrDiagnostic;
typedef Severity = ir.IrDiagnosticSeverity;

class ValidationResult {
  final List<ValidationMessage> errors;
  final List<ValidationMessage> warnings;
  final List<ValidationMessage> infos;
  final List<ControlProofResult> controlProofs;
  final List<String> requiredEvidence;
  final bool hasExpectedProofs;

  const ValidationResult({
    this.errors = const [],
    this.warnings = const [],
    this.infos = const [],
    this.controlProofs = const [],
    this.requiredEvidence = const [],
    this.hasExpectedProofs = false,
  });

  bool get passed => errors.isEmpty;

  ir.ValidationReport toReport({
    List<ir.SemanticEvidenceRecord> evidence = const [],
    String workspace = '',
    String profile = 'pullRequest',
    Map<String, String> graphHashes = const {},
    Map<String, ir.CompletenessValue> completeness = const {},
    Map<String, String> adapterHashes = const {},
    List<String> requiredEvidence = const [],
    List<String> staleEvidence = const [],
  }) {
    final eligible =
        errors.isEmpty &&
        (!hasExpectedProofs || controlProofs.isNotEmpty) &&
        (requiredEvidence.isEmpty || evidence.isNotEmpty) &&
        (!hasExpectedProofs ||
            controlProofs.every(
              (proof) =>
                  proof.status == ir.ProofStatus.proven ||
                  proof.status == ir.ProofStatus.verified ||
                  proof.status == ir.ProofStatus.attested,
            )) &&
        evidence.every((record) => record.status == ir.EvidenceStatus.passed);

    return ir.ValidationReport(
      workspace: workspace,
      profile: profile,
      diagnostics: [...errors, ...warnings, ...infos],
      controlProofs: controlProofs,
      evidence: evidence,
      graphHashes: graphHashes,
      completeness: completeness,
      adapterHashes: adapterHashes,
      requiredEvidence: requiredEvidence,
      staleEvidence: staleEvidence,
      eligible: eligible,
      ineligibilityReasons: [
        if (hasExpectedProofs && controlProofs.isEmpty)
          'No control proofs were produced',
        if (requiredEvidence.isNotEmpty && evidence.isEmpty)
          'No execution evidence records were observed',
        for (final proof in controlProofs)
          if (proof.status != ir.ProofStatus.proven &&
              proof.status != ir.ProofStatus.verified &&
              proof.status != ir.ProofStatus.attested)
            'Control proof for ${proof.controlId} is ${proof.status.name}: ${proof.diagnostics.join("; ")}',
        ...errors.map((e) => e.message),
      ],
    );
  }
}

class ValidatorEngine {
  final IdentityValidator identity;
  final ReferenceResolver references;
  final CardinalityValidator cardinality;
  final EvidenceValidator evidence;
  final SourceMappingValidator sourceMappings;
  final DominanceValidator dominance;
  final VerificationBackedValidator verificationBacked;

  ValidatorEngine({
    IdentityValidator? identity,
    ReferenceResolver? references,
    CardinalityValidator? cardinality,
    EvidenceValidator? evidence,
    SourceMappingValidator? sourceMappings,
    DominanceValidator? dominance,
    VerificationBackedValidator? verificationBacked,
  }) : identity = identity ?? IdentityValidator(),
       references = references ?? ReferenceResolver(),
       cardinality = cardinality ?? CardinalityValidator(),
       evidence = evidence ?? EvidenceValidator(),
       sourceMappings = sourceMappings ?? SourceMappingValidator(),
       dominance = dominance ?? DominanceValidator(),
       verificationBacked = verificationBacked ?? VerificationBackedValidator();

  ValidationResult validate(
    WorkspaceDiscoveryResult workspace, {
    List<ExtractedSymbol> extractedSymbols = const [],
    IrGraph? irGraph,
    List<IrAdapterOutput> outputs = const [],
    List<ir.SemanticEvidenceRecord> evidenceRecords = const [],
    List<ControlProofResult> verifiedAttestationProofs = const [],
    String profile = 'pullRequest',
    List<String>? selectedScenarioIds,
  }) {
    final allErrors = <ValidationMessage>[];
    final allWarnings = <ValidationMessage>[];
    final allInfos = <ValidationMessage>[];
    final allControlProofs = <ControlProofResult>[];
    final profileEvidence = evidenceRecords
        .where((record) => record.profile == profile)
        .toList();
    final selectedRuleIds = _selectedRuleIds(workspace, selectedScenarioIds);

    _add(
      allErrors,
      allWarnings,
      allInfos,
      allControlProofs,
      identity.validate(workspace),
    );
    _add(
      allErrors,
      allWarnings,
      allInfos,
      allControlProofs,
      references.validate(workspace),
    );
    final effectiveOutputs = outputs.isNotEmpty
        ? outputs
        : extractedSymbols.isEmpty
        ? const <IrAdapterOutput>[]
        : [
            IrAdapterOutput(
              adapter: const AdapterInfo(id: 'zuke.compat', version: '1.0.0'),
              completeness: const IrAdapterCompleteness(),
              symbols: extractedSymbols,
              inputDigest: '',
            ),
          ];
    _add(
      allErrors,
      allWarnings,
      allInfos,
      allControlProofs,
      cardinality.validate(
        workspace,
        extractedSymbols: effectiveOutputs.expand((o) => o.symbols).toList(),
      ),
    );
    if (effectiveOutputs.isNotEmpty) {
      _add(
        allErrors,
        allWarnings,
        allInfos,
        allControlProofs,
        sourceMappings.validate(workspace, effectiveOutputs),
      );
      final graphs = effectiveOutputs
          .map((output) => output.graph)
          .whereType<IrGraph>()
          .toList();
      if (graphs.isNotEmpty) {
        final nodes = <String, IrNode>{};
        final edges = <IrEdge>[];
        var completeness = const GraphCompleteness();
        for (final graph in graphs) {
          for (final node in graph.nodes) {
            if (nodes.containsKey(node.id) && nodes[node.id] != node) {
              allErrors.add(
                const ValidationMessage(
                  code: 'IR-DUPLICATE-NODE',
                  message: 'Merged adapter graphs contain conflicting node IDs',
                  severity: Severity.error,
                ),
              );
            }
            nodes[node.id] = node;
          }
          edges.addAll(graph.edges);
          completeness = _mergeCompleteness(completeness, graph.completeness);
        }
        _add(
          allErrors,
          allWarnings,
          allInfos,
          allControlProofs,
          dominance.validate(
            IrGraph(
              nodes: nodes.values.toList(),
              edges: edges,
              completeness: completeness,
            ),
            workspace: workspace,
          ),
        );
      }
    }
    if (irGraph != null) {
      _add(
        allErrors,
        allWarnings,
        allInfos,
        allControlProofs,
        dominance.validate(irGraph, workspace: workspace),
      );
    }

    // Attestation verification is asynchronous and performed by the
    // orchestration layer. Its verified output replaces the deliberately
    // fail-closed structural placeholder for the same normalized proof key
    // before evidence eligibility is evaluated.
    if (verifiedAttestationProofs.isNotEmpty) {
      final keys = {
        for (final proof in verifiedAttestationProofs)
          '${proof.requirementId ?? ''}|${proof.controlId}|${proof.target}|${proof.variant}',
      };
      allControlProofs.removeWhere(
        (proof) =>
            proof.semantics == ir.CoverageSemantics.externalAttestation &&
            keys.contains(
              '${proof.requirementId ?? ''}|${proof.controlId}|${proof.target}|${proof.variant}',
            ),
      );
      allControlProofs.addAll(verifiedAttestationProofs);
    }

    _add(
      allErrors,
      allWarnings,
      allInfos,
      allControlProofs,
      verificationBacked.validate(workspace, effectiveOutputs, profileEvidence),
    );

    _add(
      allErrors,
      allWarnings,
      allInfos,
      allControlProofs,
      evidence.validate(
        workspace,
        records: profileEvidence,
        controlProofs: allControlProofs,
        outputs: effectiveOutputs,
        selectedScenarioIds: selectedScenarioIds,
      ),
    );

    _addDuplicateProfileWarnings(workspace, allWarnings);
    final expectedProofs = _expectedProofs(
      workspace,
      selectedRuleIds: selectedRuleIds,
    );
    final controlProofs = selectedRuleIds == null
        ? allControlProofs
        : allControlProofs
              .where(
                (proof) =>
                    proof.requirementId == null ||
                    selectedRuleIds.contains(proof.requirementId),
              )
              .toList();
    final actualProofKeys = {
      for (final proof in controlProofs)
        '${proof.requirementId ?? ''}|${proof.controlId}|${proof.target}|${proof.variant}',
    };
    for (final expected in expectedProofs) {
      final key =
          '${expected.requirementId}|${expected.controlId}|${expected.target}|${expected.variant}';
      if (actualProofKeys.contains(key)) continue;
      controlProofs.add(
        ControlProofResult(
          controlId: expected.controlId,
          requirementId: expected.requirementId,
          target: expected.target,
          variant: expected.variant,
          status: ir.ProofStatus.missing,
          semantics: expected.semantics,
          diagnostics: const [
            'No proof result was produced for required control',
          ],
        ),
      );
      allErrors.add(
        ValidationMessage(
          code: 'CONTROL-PROOF-MISSING',
          message:
              'No proof result was produced for ${expected.controlId} on ${expected.requirementId}',
          severity: Severity.error,
        ),
      );
    }

    return ValidationResult(
      errors: allErrors,
      warnings: allWarnings,
      infos: allInfos,
      controlProofs: controlProofs,
      requiredEvidence: _requiredEvidence(workspace, selectedScenarioIds),
      hasExpectedProofs: expectedProofs.isNotEmpty,
    );
  }

  Set<String>? _selectedRuleIds(
    WorkspaceDiscoveryResult workspace,
    List<String>? selectedScenarioIds,
  ) {
    if (selectedScenarioIds == null) return null;
    final selected = selectedScenarioIds.toSet();
    final ruleIds = <String>{};
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        for (final scenario in rule.scenarios) {
          final scenarioIds = <String>{
            ...feature.tags.map((tag) => tag.name),
            ...rule.tags.map((tag) => tag.name),
            ...scenario.tags.map((tag) => tag.name),
            for (final examples in scenario.examples)
              ...examples.tags.map((tag) => tag.name),
          };
          if (scenarioIds.any(selected.contains) && rule.metadata.id != null) {
            ruleIds.add(rule.metadata.id!);
          }
        }
      }
    }
    return ruleIds;
  }

  List<String> _requiredEvidence(
    WorkspaceDiscoveryResult workspace,
    List<String>? selectedScenarioIds,
  ) {
    final selectedRuleIds = _selectedRuleIds(workspace, selectedScenarioIds);
    return [
      for (final feature in workspace.data.features)
        for (final rule in feature.rules)
          if (selectedScenarioIds == null ||
              selectedRuleIds!.contains(rule.metadata.id))
            for (final type
                in rule.metadata.requiredEvidence ?? const <String>[])
              '${rule.metadata.id ?? '<unknown>'}|$type',
    ]..sort();
  }

  List<_ExpectedProof> _expectedProofs(
    WorkspaceDiscoveryResult workspace, {
    Set<String>? selectedRuleIds,
  }) {
    final result = <String, _ExpectedProof>{};
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final requirementId = rule.metadata.id;
        if (requirementId == null) continue;
        if (selectedRuleIds != null &&
            !selectedRuleIds.contains(requirementId)) {
          continue;
        }
        for (final ref
            in rule.metadata.requires ?? const <ParsedControlRef>[]) {
          if (ref.kind != 'control') continue;
          final semantic = _semanticsFor(workspace, ref.id);
          final expected = _ExpectedProof(
            requirementId: requirementId,
            controlId: ref.id,
            target: ref.target,
            variant: ref.variant,
            semantics: semantic,
          );
          result['${expected.requirementId}|${expected.controlId}|${expected.target}|${expected.variant}'] =
              expected;
        }
        final profile = rule.metadata.securityProfile;
        if (profile != null) {
          for (final policy in workspace.data.policies.values) {
            final profiles = policy['securityProfiles'];
            final definition = profiles is Map ? profiles[profile] : null;
            final requires = definition is Map ? definition['requires'] : null;
            if (requires is! List) continue;
            for (final raw in requires.whereType<Map>()) {
              final controlId = raw['id']?.toString();
              if (controlId == null || controlId.isEmpty) continue;
              final target = raw['target']?.toString() ?? 'backend';
              final variant = raw['variant']?.toString() ?? 'default';
              final expected = _ExpectedProof(
                requirementId: requirementId,
                controlId: controlId,
                target: target,
                variant: variant,
                semantics: _semanticsFor(workspace, controlId),
              );
              result['${expected.requirementId}|${expected.controlId}|${expected.target}|${expected.variant}'] =
                  expected;
            }
          }
        }
      }
    }
    return result.values.toList();
  }

  void _addDuplicateProfileWarnings(
    WorkspaceDiscoveryResult workspace,
    List<ValidationMessage> warnings,
  ) {
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final requirementId = rule.metadata.id;
        final profileName = rule.metadata.securityProfile;
        if (requirementId == null || profileName == null) continue;
        final direct = {
          for (final ref
              in rule.metadata.requires ?? const <ParsedControlRef>[])
            if (ref.kind == 'control') '${ref.id}|${ref.target}|${ref.variant}',
        };
        for (final policy in workspace.data.policies.values) {
          final profiles = policy['securityProfiles'];
          final profile = profiles is Map ? profiles[profileName] : null;
          final requires = profile is Map ? profile['requires'] : null;
          if (requires is! List) continue;
          for (final raw in requires.whereType<Map>()) {
            if (raw['kind']?.toString() != 'control') continue;
            final id = raw['id']?.toString();
            if (id == null || id.isEmpty) continue;
            final key =
                '${id}|${raw['target'] ?? 'backend'}|${raw['variant'] ?? 'default'}';
            if (direct.contains(key)) {
              warnings.add(
                ValidationMessage(
                  code: 'ZUKE-POLICY-DUPLICATE-CONTROL',
                  message:
                      'Rule $requirementId declares $id directly and through security profile $profileName',
                  severity: Severity.warning,
                  source: rule.metadata.source,
                ),
              );
            }
          }
        }
      }
    }
  }

  ir.CoverageSemantics _semanticsFor(
    WorkspaceDiscoveryResult workspace,
    String controlId,
  ) => switch (workspace.data.controls[controlId]?['coverageSemantics']) {
    'failure-to-public-egress' => ir.CoverageSemantics.failureToPublicEgress,
    'sensitive-data-to-log-sink' => ir.CoverageSemantics.sensitiveDataToLogSink,
    'external-attestation' => ir.CoverageSemantics.externalAttestation,
    'verification-backed' => ir.CoverageSemantics.verificationBacked,
    _ => ir.CoverageSemantics.ingressDominance,
  };

  void _add(
    List<ValidationMessage> errors,
    List<ValidationMessage> warnings,
    List<ValidationMessage> infos,
    List<ControlProofResult> controlProofs,
    ValidationResult result,
  ) {
    errors.addAll(result.errors);
    warnings.addAll(result.warnings);
    infos.addAll(result.infos);
    controlProofs.addAll(result.controlProofs);
  }

  GraphCompleteness _mergeCompleteness(
    GraphCompleteness left,
    GraphCompleteness right,
  ) {
    CompletenessValue merge(CompletenessValue a, CompletenessValue b) {
      if (a == CompletenessValue.indeterminate ||
          b == CompletenessValue.indeterminate) {
        return CompletenessValue.indeterminate;
      }
      if (a == CompletenessValue.notVisible ||
          b == CompletenessValue.notVisible) {
        return CompletenessValue.notVisible;
      }
      if (a == CompletenessValue.complete || b == CompletenessValue.complete) {
        return CompletenessValue.complete;
      }
      return CompletenessValue.notApplicable;
    }

    return GraphCompleteness(
      routeRegistration: merge(left.routeRegistration, right.routeRegistration),
      middlewareOrder: merge(left.middlewareOrder, right.middlewareOrder),
      failureFlow: merge(left.failureFlow, right.failureFlow),
      logFlow: merge(left.logFlow, right.logFlow),
      dynamicRegistration: merge(
        left.dynamicRegistration,
        right.dynamicRegistration,
      ),
      externalVisibility: merge(
        left.externalVisibility,
        right.externalVisibility,
      ),
    );
  }
}

class _ExpectedProof {
  final String requirementId;
  final String controlId;
  final String target;
  final String variant;
  final ir.CoverageSemantics semantics;

  const _ExpectedProof({
    required this.requirementId,
    required this.controlId,
    required this.target,
    required this.variant,
    required this.semantics,
  });
}
