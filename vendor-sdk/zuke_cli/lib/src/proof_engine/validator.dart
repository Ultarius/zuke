import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:zuke_core/zuke_core.dart' show BindingIdentity;
import 'package:zuke_frontend/zuke_frontend.dart';
import 'identity_validator.dart';
import 'reference_resolver.dart';
import 'cardinality_validator.dart';
import 'evidence_validator.dart';
import 'source_mapping_validator.dart';
import 'dominance_validator.dart';
import 'verification_backed_validator.dart';
import 'obligation_catalog.dart';
import '../ir.dart' as ir;
import '../ir.dart';

typedef ValidationMessage = ir.IrDiagnostic;
typedef Severity = ir.IrDiagnosticSeverity;

class ValidationResult {
  final List<ValidationMessage> errors;
  final List<ValidationMessage> warnings;
  final List<ValidationMessage> infos;
  final List<ControlProofResult> controlProofs;
  final List<ir.ImplementationCoverageResult> implementationCoverage;
  final List<String> requiredEvidence;
  final bool hasExpectedProofs;

  const ValidationResult({
    this.errors = const [],
    this.warnings = const [],
    this.infos = const [],
    this.controlProofs = const [],
    this.implementationCoverage = const [],
    this.requiredEvidence = const [],
    this.hasExpectedProofs = false,
  });

  bool get passed => errors.isEmpty;

  ir.ValidationReport toReport({
    List<ir.EvidenceRecord> evidence = const [],
    String workspace = '',
    String profile = 'pullRequest',
    Map<String, String> graphHashes = const {},
    Map<String, ir.CompletenessValue> completeness = const {},
    Map<String, String> adapterHashes = const {},
    List<String> requiredEvidence = const [],
    List<String> staleEvidence = const [],
    List<ir.ImplementationCoverageResult>? implementationCoverage,
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
        evidence.every((record) => record.status == ir.EvidenceStatus.passed) &&
        (implementationCoverage ?? this.implementationCoverage).every(
          (coverage) =>
              coverage.status == ir.ProofStatus.proven ||
              coverage.status == ir.ProofStatus.verified,
        );

    return ir.ValidationReport(
      workspace: workspace,
      profile: profile,
      diagnostics: [...errors, ...warnings, ...infos],
      controlProofs: controlProofs,
      implementationCoverage:
          implementationCoverage ?? this.implementationCoverage,
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
        for (final coverage
            in implementationCoverage ?? this.implementationCoverage)
          if (coverage.status != ir.ProofStatus.proven &&
              coverage.status != ir.ProofStatus.verified)
            'Implementation coverage for ${coverage.binding.key} is ${coverage.status.name}: ${coverage.diagnostics.join("; ")}',
        ...errors.map((e) => e.message),
      ],
    );
  }
}

_ImplementationCoverageEvaluation _implementationCoverage(
  List<IrAdapterOutput> outputs,
  IrGraph? explicitGraph,
  List<ir.EvidenceRecord> evidence,
  AssuranceObligationCatalog catalog,
) {
  final errors = <ValidationMessage>[];
  final graphs = <IrGraph>[
    ...outputs.map((output) => output.graph).whereType<IrGraph>(),
    if (explicitGraph != null) explicitGraph,
  ];
  final mergedNodes = <String, IrNode>{};
  final mergedEdges = <IrEdge>[];
  for (final graph in graphs) {
    mergedNodes.addAll({for (final node in graph.nodes) node.id: node});
    mergedEdges.addAll(graph.edges);
  }
  final bindings = <String, _ImplementationBinding>{};
  for (final obligation in catalog.implementationCoverage) {
    final binding = obligation.binding;
    final nodeCandidates = [
      for (final node in mergedNodes.values)
        if (node.kind == NodeKind.implementation &&
            node.target == binding.target &&
            node.role == 'implementation' &&
            node.variant == binding.variant &&
            node.slot == binding.slot &&
            (node.properties['requirementIds'] as List?)
                    ?.whereType<String>()
                    .contains(binding.subjectId) ==
                true)
          node,
    ];
    bindings[binding.key] = _ImplementationBinding(
      identity: binding,
      packageName: obligation.packageId,
      mode: obligation.mode,
      node: nodeCandidates.length == 1 ? nodeCandidates.single : null,
      nodeCount: nodeCandidates.length,
    );
  }

  final results = <ir.ImplementationCoverageResult>[];
  for (final binding in bindings.values) {
    final mode = binding.mode;
    if (mode == ir.PlacementMode.topologyAuthoritative) {
      final reachable =
          binding.node != null &&
          _reachableImplementation(
            mergedNodes,
            mergedEdges,
            binding.node!.id,
            binding.identity.target,
          );
      final diagnostics = <String>[];
      if (binding.nodeCount == 0) {
        diagnostics.add('No extracted implementation node matches binding');
      } else if (binding.nodeCount > 1) {
        diagnostics.add(
          'Multiple extracted implementation nodes match binding',
        );
      } else if (!reachable) {
        diagnostics.add(
          'Implementation binding is not reachable from a target entry point',
        );
      }
      final status = diagnostics.isEmpty
          ? ir.ProofStatus.proven
          : ir.ProofStatus.failed;
      results.add(
        ir.ImplementationCoverageResult(
          binding: binding.identity,
          mode: mode,
          status: status,
          governedGraphHash: _coverageGraphHash(
            IrGraph(nodes: mergedNodes.values.toList(), edges: mergedEdges),
          ),
          diagnostics: diagnostics,
        ),
      );
      if (diagnostics.isNotEmpty) {
        errors.add(
          ValidationMessage(
            code: binding.nodeCount == 0
                ? 'ZK-IMPL-COVERAGE-MISSING'
                : 'ZK-IMPL-UNREACHABLE',
            message: '${binding.identity.key}: ${diagnostics.join('; ')}',
            severity: Severity.error,
          ),
        );
      }
      continue;
    }

    final sameSemanticBindings = bindings.values
        .where(
          (other) =>
              other.identity.subjectKind == binding.identity.subjectKind &&
              other.identity.subjectId == binding.identity.subjectId &&
              other.identity.target == binding.identity.target &&
              other.identity.variant == binding.identity.variant,
        )
        .toList(growable: false);
    final knownSlots = sameSemanticBindings
        .map((other) => other.identity.slot)
        .toSet();
    for (final record in evidence.where(
      (record) =>
          record.requirementId == binding.identity.subjectId &&
          record.target == binding.identity.target &&
          record.variant == binding.identity.variant &&
          record.status == ir.EvidenceStatus.passed &&
          record.implementationSlots.isNotEmpty,
    )) {
      final unknownSlots = record.implementationSlots
          .where((slot) => !knownSlots.contains(slot))
          .toList(growable: false);
      if (unknownSlots.isNotEmpty) {
        errors.add(
          ValidationMessage(
            code: 'ZK-IMPL-SLOT-CLAIM-UNKNOWN',
            message:
                '${binding.identity.key}: evidence claimed unknown '
                'implementation slot(s): ${unknownSlots.join(', ')}',
            severity: Severity.error,
          ),
        );
      }
    }

    final candidates = evidence.where((record) {
      if (record.requirementId != binding.identity.subjectId ||
          record.target != binding.identity.target ||
          record.variant != binding.identity.variant ||
          record.status != ir.EvidenceStatus.passed) {
        return false;
      }
      if (record.implementationSlots.contains(binding.identity.slot)) {
        return true;
      }
      return sameSemanticBindings.length == 1 &&
          record.implementationSlots.isEmpty;
    }).toList();
    final missingCode =
        candidates.isEmpty &&
            sameSemanticBindings.length > 1 &&
            evidence.any(
              (record) =>
                  record.requirementId == binding.identity.subjectId &&
                  record.target == binding.identity.target &&
                  record.variant == binding.identity.variant &&
                  record.status == ir.EvidenceStatus.passed &&
                  record.implementationSlots.isEmpty,
            )
        ? 'ZK-IMPL-SLOT-CLAIM-REQUIRED'
        : 'ZK-IMPL-EVIDENCE-MISSING';
    final diagnostics = candidates.isEmpty
        ? [
            'No current passing managed evidence claims implementation slot ${binding.identity.slot}',
          ]
        : const <String>[];
    results.add(
      ir.ImplementationCoverageResult(
        binding: binding.identity,
        mode: mode,
        status: diagnostics.isEmpty
            ? ir.ProofStatus.verified
            : ir.ProofStatus.missing,
        evidenceDigests: candidates
            .expand((record) => record.digests.values)
            .toSet()
            .toList(),
        diagnostics: diagnostics,
      ),
    );
    if (diagnostics.isNotEmpty) {
      errors.add(
        ValidationMessage(
          code: missingCode,
          message: '${binding.identity.key}: ${diagnostics.join('; ')}',
          severity: Severity.error,
        ),
      );
    }
  }
  return _ImplementationCoverageEvaluation(results, errors);
}

bool _reachableImplementation(
  Map<String, IrNode> nodes,
  List<IrEdge> edges,
  String implementationId,
  String target,
) {
  final entries = nodes.values
      .where(
        (node) =>
            node.kind == NodeKind.entryPoint &&
            (node.target == null || node.target == target),
      )
      .map((node) => node.id)
      .toList();
  final adjacency = <String, List<String>>{};
  for (final edge in edges) {
    if ({
      EdgeKind.routesTo,
      EdgeKind.precedes,
      EdgeKind.invokes,
      EdgeKind.flowsTo,
    }.contains(edge.kind)) {
      (adjacency[edge.sourceId] ??= []).add(edge.targetId);
    }
  }
  final queue = [...entries];
  final visited = <String>{};
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    if (!visited.add(current)) continue;
    if (current == implementationId) return true;
    queue.addAll(adjacency[current] ?? const []);
  }
  return false;
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
    List<ir.EvidenceRecord> evidenceRecords = const [],
    List<ControlProofResult> verifiedAttestationProofs = const [],
    String profile = 'pullRequest',
    List<String>? selectedScenarioIds,
  }) {
    final allErrors = <ValidationMessage>[];
    final allWarnings = <ValidationMessage>[];
    final allInfos = <ValidationMessage>[];
    final allControlProofs = <ControlProofResult>[];
    final allImplementationCoverage = <ir.ImplementationCoverageResult>[];
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
    final obligationCatalog = AssuranceObligationCatalog.build(
      workspace,
      effectiveOutputs,
    );
    allErrors.addAll(obligationCatalog.diagnostics);
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
            obligations: obligationCatalog.controls,
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
        dominance.validate(
          irGraph,
          workspace: workspace,
          obligations: obligationCatalog.controls,
        ),
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
      verificationBacked.validate(
        workspace,
        effectiveOutputs,
        profileEvidence,
        obligations: obligationCatalog.controls,
      ),
    );

    final implementationCoverage = _implementationCoverage(
      effectiveOutputs,
      irGraph,
      profileEvidence,
      obligationCatalog,
    );
    allImplementationCoverage.addAll(implementationCoverage.results);
    allErrors.addAll(implementationCoverage.errors);

    final reconciledProofs = _reconcileProofOwnership(
      allControlProofs,
      allErrors,
    );
    allControlProofs
      ..clear()
      ..addAll(reconciledProofs);

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
        '${proof.requirementId ?? ''}|${proof.controlId}|${proof.target}|${proof.variant}|${proof.slot}',
    };
    for (final expected in expectedProofs) {
      final key =
          '${expected.requirementId}|${expected.controlId}|${expected.target}|${expected.variant}|${expected.slot}';
      if (actualProofKeys.contains(key)) continue;
      controlProofs.add(
        ControlProofResult(
          controlId: expected.controlId,
          requirementId: expected.requirementId,
          target: expected.target,
          variant: expected.variant,
          slot: expected.slot,
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
      implementationCoverage: allImplementationCoverage,
      requiredEvidence: _requiredEvidence(workspace, selectedScenarioIds),
      hasExpectedProofs: expectedProofs.isNotEmpty,
    );
  }

  List<ControlProofResult> _reconcileProofOwnership(
    List<ControlProofResult> proofs,
    List<ValidationMessage> errors,
  ) {
    final grouped = <String, List<ControlProofResult>>{};
    for (final proof in proofs) {
      (grouped[_proofKey(proof)] ??= []).add(proof);
    }
    final reconciled = <ControlProofResult>[];
    for (final entry in grouped.entries) {
      final candidates = entry.value;
      if (candidates.length == 1) {
        reconciled.add(candidates.single);
        continue;
      }
      final semantics = candidates.map((proof) => proof.semantics).toSet();
      final providerIds =
          candidates.expand((proof) => proof.providerIds).toSet().toList()
            ..sort();
      final evidenceDigests =
          candidates.expand((proof) => proof.evidenceDigests).toSet().toList()
            ..sort();
      final diagnostics =
          candidates.expand((proof) => proof.diagnostics).toSet().toList()
            ..sort();
      final first = candidates.first;
      final conflict = semantics.length > 1;
      if (conflict) {
        errors.add(
          ValidationMessage(
            code: 'ZK-PROOF-OWNER-CONFLICT',
            message:
                'Multiple proof owners produced results for ${entry.key}: '
                '${semantics.map((value) => value.wireValue).join(', ')}',
            severity: Severity.error,
          ),
        );
      }
      final status =
          candidates.any((proof) => proof.status == ProofStatus.failed)
          ? ProofStatus.failed
          : candidates.any(
              (proof) =>
                  proof.status == ProofStatus.indeterminate ||
                  proof.status == ProofStatus.missing ||
                  proof.status == ProofStatus.expired,
            )
          ? candidates
                .firstWhere(
                  (proof) =>
                      proof.status == ProofStatus.indeterminate ||
                      proof.status == ProofStatus.missing ||
                      proof.status == ProofStatus.expired,
                )
                .status
          : first.status;
      reconciled.add(
        ControlProofResult(
          controlId: first.controlId,
          requirementId: first.requirementId,
          target: first.target,
          variant: first.variant,
          slot: first.slot,
          status: conflict ? ProofStatus.failed : status,
          semantics: first.semantics,
          providerIds: providerIds,
          evidenceDigests: evidenceDigests,
          bypassPaths:
              candidates.expand((proof) => proof.bypassPaths).toSet().toList()
                ..sort(),
          governedGraphHash:
              candidates
                      .map((proof) => proof.governedGraphHash)
                      .toSet()
                      .length ==
                  1
              ? first.governedGraphHash
              : null,
          completeness: first.completeness,
          diagnostics: [
            ...diagnostics,
            if (conflict)
              'Exactly one validator must own each control obligation',
          ],
        ),
      );
    }
    return reconciled;
  }

  String _proofKey(ControlProofResult proof) =>
      '${proof.requirementId ?? ''}|${proof.controlId}|${proof.target}|${proof.variant}|${proof.slot}';

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
            slot: ref.slot,
            semantics: semantic,
          );
          result['${expected.requirementId}|${expected.controlId}|${expected.target}|${expected.variant}|${expected.slot}'] =
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
              final target = raw['target']?.toString();
              if (target == null || target.isEmpty) continue;
              final variant = raw['variant']?.toString() ?? 'default';
              final slot = raw['slot']?.toString() ?? 'primary';
              final expected = _ExpectedProof(
                requirementId: requirementId,
                controlId: controlId,
                target: target,
                variant: variant,
                slot: slot,
                semantics: _semanticsFor(workspace, controlId),
              );
              result['${expected.requirementId}|${expected.controlId}|${expected.target}|${expected.variant}|${expected.slot}'] =
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
            if (ref.kind == 'control')
              '${ref.id}|${ref.target}|${ref.variant}|${ref.slot}',
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
            final target = raw['target']?.toString();
            if (target == null || target.isEmpty) continue;
            final key =
                '$id|$target|${raw['variant'] ?? 'default'}|${raw['slot'] ?? 'primary'}';
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
  final String slot;
  final ir.CoverageSemantics semantics;

  const _ExpectedProof({
    required this.requirementId,
    required this.controlId,
    required this.target,
    required this.variant,
    required this.slot,
    required this.semantics,
  });
}

final class _ImplementationBinding {
  final BindingIdentity identity;
  final String packageName;
  final ir.PlacementMode mode;
  final IrNode? node;
  final int nodeCount;

  const _ImplementationBinding({
    required this.identity,
    required this.packageName,
    required this.mode,
    required this.node,
    required this.nodeCount,
  });
}

final class _ImplementationCoverageEvaluation {
  final List<ir.ImplementationCoverageResult> results;
  final List<ValidationMessage> errors;

  const _ImplementationCoverageEvaluation(this.results, this.errors);
}

String _coverageGraphHash(IrGraph graph) =>
    'sha256:${sha256.convert(utf8.encode(canonicalJson(graph.toJson())))}';
