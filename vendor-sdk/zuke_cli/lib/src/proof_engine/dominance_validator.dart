import 'package:zuke_frontend/zuke_frontend.dart';
import '../ir.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'obligation_catalog.dart';
import 'validator.dart';

/// Framework-neutral control proof analysis.
///
/// Ingress controls use dominance. Error and logging controls use independent
/// all-path flow coverage. The validator never manufactures a path or treats
/// provider-node existence as proof.
class DominanceValidator {
  ValidationResult validate(
    IrGraph graph, {
    WorkspaceDiscoveryResult? workspace,
    Iterable<ControlObligation>? obligations,
  }) {
    final errors = <ValidationMessage>[];
    final proofs = <ControlProofResult>[];
    final ids = graph.nodeIds;

    for (final dangling in graph.danglingEdges()) {
      errors.add(
        ValidationMessage(
          code: 'IR-GRAPH-001',
          message: 'Graph contains dangling edge $dangling',
          severity: Severity.error,
        ),
      );
    }

    final ruleControls = _ruleControls(workspace, graph);
    final routeDominators = _dominators(
      graph,
      allowedKinds: {EdgeKind.precedes, EdgeKind.routesTo},
    );
    final implementations = graph.nodes.where(
      (node) => node.kind == NodeKind.implementation,
    );
    final structuralKeys = obligations
        ?.where(
          (obligation) => obligation.owner == ProofOwner.structuralDominance,
        )
        .map((obligation) => obligation.key)
        .toSet();

    for (final implementation in implementations) {
      final implementationTarget = implementation.target;
      final implementationVariant = implementation.variant;
      if (implementationTarget == null || implementationVariant == null) {
        errors.add(
          const ValidationMessage(
            code: 'ZK-BINDING-IDENTITY-MISSING',
            message: 'Implementation binding is missing target or variant',
            severity: Severity.error,
          ),
        );
        continue;
      }
      final requirementIds =
          (implementation.properties['requirementIds'] as List?)
              ?.whereType<String>()
              .toList() ??
          const <String>[];
      final requiredControls = <String>{};
      for (final requirementId in requirementIds) {
        requiredControls.addAll(ruleControls[requirementId] ?? const {});
      }
      if (requirementIds.isEmpty) {
        requiredControls.addAll(ruleControls[implementation.id] ?? const {});
      }

      for (final controlId in requiredControls) {
        final controlReference = _controlReference(
          workspace,
          requirementIds,
          controlId,
        );
        final controlTarget = controlReference?.target ?? implementationTarget;
        final controlVariant =
            controlReference?.variant ?? implementationVariant;
        final controlSlot = controlReference?.slot ?? 'primary';
        if (structuralKeys != null) {
          final subjects = requirementIds.isEmpty
              ? [implementation.id]
              : requirementIds;
          final owned = subjects.any(
            (subject) => structuralKeys.contains(
              '$subject|$controlId|$controlTarget|$controlVariant|$controlSlot',
            ),
          );
          if (!owned) continue;
        }
        // A rule may govern multiple targets. A control requirement belongs
        // to the target declared by its exact reference; it must not be
        // evaluated against an implementation extracted from another target.
        // This prevents a Flutter/domain annotation from becoming an
        // uncovered backend path merely because both sides mention the same
        // control identifier.
        if (!_appliesToTarget(
          workspace,
          requirementIds,
          controlId,
          implementationTarget,
        )) {
          continue;
        }
        final providers = graph.nodes
            .where(
              (node) =>
                  node.kind == NodeKind.provider &&
                  node.target == controlTarget &&
                  node.variant == controlVariant &&
                  node.slot == controlSlot &&
                  (node.properties['controlId'] == controlId ||
                      (node.properties['controlIds'] is List &&
                          (node.properties['controlIds'] as List).contains(
                            controlId,
                          ))),
            )
            .toList();
        final providerIds = providers.map((provider) => provider.id).toList();
        final configuredSemantics =
            workspace?.data.controls[controlId]?['coverageSemantics'] ??
            implementation.properties['coverageSemantics'];
        if (configuredSemantics is! String || configuredSemantics.isEmpty) {
          if (workspace == null) {
            // Legacy unit fixtures predate explicit control metadata. This
            // compatibility path is never used for workspace assurance.
          } else {
            final missing = ControlProofResult(
              controlId: controlId,
              requirementId: requirementIds.isEmpty
                  ? null
                  : requirementIds.first,
              status: ProofStatus.indeterminate,
              semantics: CoverageSemantics.ingressDominance,
              providerIds: providerIds,
              slot: controlSlot,
              completeness: _completenessMap(graph.completeness),
              diagnostics: const [
                'Control coverageSemantics is not configured',
              ],
            );
            proofs.add(missing);
            errors.add(
              ValidationMessage(
                code: 'CONTROL-SEMANTICS-001',
                message: '$controlId has no explicit coverageSemantics',
                severity: Severity.error,
              ),
            );
            continue;
          }
        }
        // Verification-backed controls have a different proof contract from
        // structural controls.  They are proved by
        // VerificationBackedValidator using a resolved provider and current
        // passing evidence, not by graph dominance.  Do not emit a competing
        // structural proof (or a structural error) for the same control.
        // Skipping here is not an auto-pass: the dedicated validator remains
        // responsible for producing the required verified proof.
        if (workspace != null && configuredSemantics == 'verification-backed') {
          continue;
        }
        final completeness = _completenessMap(graph.completeness);
        final semantics = _semantics(workspace, controlId, graph);
        if (semantics == null) {
          // A workspace control without an explicit semantic is never
          // defaulted to ingress.  Defaulting would turn a configuration
          // omission into a false proof.
          final missing = ControlProofResult(
            controlId: controlId,
            requirementId: requirementIds.isEmpty ? null : requirementIds.first,
            status: ProofStatus.indeterminate,
            semantics: CoverageSemantics.ingressDominance,
            providerIds: providerIds,
            slot: controlSlot,
            completeness: completeness,
            diagnostics: const ['Unknown coverageSemantics value'],
          );
          proofs.add(missing);
          errors.add(
            ValidationMessage(
              code: 'CONTROL-SEMANTICS-001',
              message: '$controlId has an unknown coverageSemantics value',
              severity: Severity.error,
            ),
          );
          continue;
        }
        final requiresExternalVisibility = _requiresExternalVisibility(
          workspace,
          controlId,
          implementation,
        );
        final result = switch (semantics) {
          CoverageSemantics.failureToPublicEgress => _flowProof(
            graph,
            implementation,
            providers,
            controlId,
            semantics,
            targetKind: NodeKind.entryPoint,
            targetFlow: 'public-egress',
            sourceFlow: 'failure',
            completenessKey: 'failureFlow',
            requiresExternalVisibility: requiresExternalVisibility,
            legacyFixture: workspace == null,
          ),
          CoverageSemantics.sensitiveDataToLogSink => _flowProof(
            graph,
            implementation,
            providers,
            controlId,
            semantics,
            targetKind: NodeKind.sink,
            targetFlow: 'log-sink',
            sourceFlow: 'sensitive-data',
            completenessKey: 'logFlow',
            requiresExternalVisibility: requiresExternalVisibility,
            legacyFixture: workspace == null,
          ),
          CoverageSemantics.externalAttestation => _attestationProof(
            workspace,
            controlId,
            semantics,
            completeness,
          ),
          // Ingress is the only remaining supported application-flow proof.
          _ => _ingressProof(
            graph,
            implementation,
            providers,
            routeDominators,
            controlId,
            semantics,
            completeness,
            requiresExternalVisibility: requiresExternalVisibility,
          ),
        };
        final matchingRequirementIds = requirementIds
            .where((reqId) => ruleControls[reqId]?.contains(controlId) ?? false)
            .toList();
        final targetReqIds = matchingRequirementIds.isEmpty
            ? (requirementIds.isEmpty
                  ? [
                      <String?>[null].single,
                    ]
                  : [requirementIds.first])
            : matchingRequirementIds;
        for (final reqId in targetReqIds) {
          final normalized = ControlProofResult(
            controlId: controlId,
            requirementId: reqId,
            target: semantics == CoverageSemantics.externalAttestation
                ? controlTarget
                : implementationTarget,
            variant: controlVariant,
            slot: controlSlot,
            status: result.status,
            semantics: semantics,
            providerIds: providerIds,
            bypassPaths: result.bypassPaths,
            governedGraphHash: result.governedGraphHash ?? _graphHash(graph),
            completeness: completeness,
          );
          proofs.add(normalized);
        }

        if (result.status == ProofStatus.failed) {
          errors.add(
            ValidationMessage(
              code: semantics == CoverageSemantics.ingressDominance
                  ? 'CONTROL-DOMINANCE-002'
                  : semantics == CoverageSemantics.failureToPublicEgress
                  ? 'CONTROL-ERROR-FLOW-003'
                  : 'CONTROL-LOG-FLOW-004',
              message: _failureMessage(proofs.last, implementation.id),
              severity: Severity.error,
            ),
          );
        } else if ((result.status == ProofStatus.indeterminate ||
                result.status == ProofStatus.missing) &&
            semantics != CoverageSemantics.externalAttestation) {
          errors.add(
            ValidationMessage(
              code: 'CONTROL-PROVIDER-001',
              message:
                  '$controlId cannot be proven for ${implementation.id}: ${result.status}',
              severity: Severity.error,
            ),
          );
        }
      }
    }

    // Prevent an empty graph from accidentally passing a proof call.
    if (ids.isNotEmpty && implementations.isEmpty && ruleControls.isNotEmpty) {
      errors.add(
        const ValidationMessage(
          code: 'CONTROL-PROVIDER-001',
          message: 'No implementation nodes are present in the governed graph',
          severity: Severity.error,
        ),
      );
    }
    return ValidationResult(errors: errors, controlProofs: proofs);
  }

  Map<String, Set<String>> _ruleControls(
    WorkspaceDiscoveryResult? workspace,
    IrGraph graph,
  ) {
    final result = <String, Set<String>>{};
    if (workspace == null) {
      for (final node in graph.nodes.where(
        (node) => node.kind == NodeKind.implementation,
      )) {
        final controls = node.properties['requiredControls'];
        final requirements = node.properties['requirementIds'];
        if (controls is List) {
          final key = requirements is List && requirements.isNotEmpty
              ? requirements.first.toString()
              : node.id;
          result[key] = controls.whereType<String>().toSet();
        }
      }
      return result;
    }
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final id = rule.metadata.id;
        if (id == null) continue;
        result[id] = {
          ...?result[id],
          ...?(rule.metadata.requires
              ?.where((ref) => ref.kind == 'control')
              .map((ref) => ref.id)
              .toSet()),
        };
        final profile = rule.metadata.securityProfile;
        if (profile != null) {
          for (final policy in workspace.data.policies.values) {
            final profiles = policy['securityProfiles'];
            final definition = profiles is Map ? profiles[profile] : null;
            final requires = definition is Map ? definition['requires'] : null;
            if (requires is List) {
              result[id]!.addAll(
                requires
                    .whereType<Map>()
                    .map((ref) => ref['id'])
                    .whereType<String>(),
              );
            }
          }
        }
      }
    }
    return result;
  }

  bool _appliesToTarget(
    WorkspaceDiscoveryResult? workspace,
    List<String> requirementIds,
    String controlId,
    String implementationTarget,
  ) {
    if (workspace == null || requirementIds.isEmpty) return true;
    final declaredTargets = <String>[];
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        if (!requirementIds.contains(rule.metadata.id)) continue;
        for (final reference
            in rule.metadata.requires ?? const <ParsedControlRef>[]) {
          if (reference.kind == 'control' && reference.id == controlId) {
            declaredTargets.add(reference.target);
          }
        }
        final profile = rule.metadata.securityProfile;
        if (profile == null) continue;
        for (final policy in workspace.data.policies.values) {
          final profiles = policy['securityProfiles'];
          final definition = profiles is Map ? profiles[profile] : null;
          final requires = definition is Map ? definition['requires'] : null;
          if (requires is! List) continue;
          for (final raw in requires.whereType<Map>()) {
            if (raw['id']?.toString() == controlId) {
              final target = raw['target']?.toString();
              if (target != null && target.isNotEmpty) {
                declaredTargets.add(target);
              }
            }
          }
        }
      }
    }
    // Preserve the legacy unit-fixture behavior when no target declaration
    // exists. Workspace references with an explicit target remain exact.
    return declaredTargets.isEmpty ||
        declaredTargets.contains(implementationTarget);
  }

  ParsedControlRef? _controlReference(
    WorkspaceDiscoveryResult? workspace,
    List<String> requirementIds,
    String controlId,
  ) {
    if (workspace == null) return null;
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        if (!requirementIds.contains(rule.metadata.id)) continue;
        for (final reference
            in rule.metadata.requires ?? const <ParsedControlRef>[]) {
          if (reference.kind == 'control' && reference.id == controlId) {
            return reference;
          }
        }
      }
    }
    return null;
  }

  String _graphHash(IrGraph graph) =>
      'sha256:${sha256.convert(utf8.encode(canonicalJson(graph.toJson())))}';

  CoverageSemantics? _semantics(
    WorkspaceDiscoveryResult? workspace,
    String controlId,
    IrGraph graph,
  ) {
    final configured =
        workspace?.data.controls[controlId]?['coverageSemantics'];
    final graphConfigured = graph.nodes
        .map((node) => node.properties['coverageSemantics'])
        .whereType<String>()
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final value = configured is String && configured.isNotEmpty
        ? configured
        : graphConfigured;
    return switch (value) {
      'ingress-dominance' => CoverageSemantics.ingressDominance,
      'failure-to-public-egress' => CoverageSemantics.failureToPublicEgress,
      'sensitive-data-to-log-sink' => CoverageSemantics.sensitiveDataToLogSink,
      'external-attestation' => CoverageSemantics.externalAttestation,
      _ => workspace == null ? CoverageSemantics.ingressDominance : null,
    };
  }

  ControlProofResult _attestationProof(
    WorkspaceDiscoveryResult? workspace,
    String controlId,
    CoverageSemantics semantics,
    Map<String, CompletenessValue> completeness,
  ) {
    if (workspace == null) {
      return ControlProofResult(
        controlId: controlId,
        status: ProofStatus.missing,
        semantics: semantics,
        completeness: completeness,
      );
    }
    final now = DateTime.now().toUtc();
    var expired = false;
    var invalid = false;
    for (final policy in workspace.data.policies.values) {
      final providers = policy['providers'];
      if (providers is! List) continue;
      for (final provider in providers.whereType<Map>()) {
        if (provider['provides'] != controlId ||
            provider['assurance'] != 'attested') {
          continue;
        }
        for (final field in [
          'id',
          'target',
          'variant',
          'kind',
          'layer',
          'owner',
          'system',
          'reference',
          'scope',
          'document',
        ]) {
          if (provider[field] == null || '${provider[field]}'.isEmpty) {
            invalid = true;
          }
        }
        final digest = provider['evidence'] is Map
            ? (provider['evidence'] as Map)['digest']?.toString()
            : provider['evidenceDigest']?.toString();
        final expires = DateTime.tryParse('${provider['expiresAt'] ?? ''}');
        if (expires != null && !expires.isAfter(now)) {
          expired = true;
          continue;
        }
        if (digest == null ||
            !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest)) {
          invalid = true;
          continue;
        }
        final document = provider['document'];
        if (document is! String || document.isEmpty) {
          invalid = true;
          continue;
        }
        // Dominance is deliberately synchronous.  The orchestration layer
        // supplies a separately verified attestation proof; this structural
        // pass must fail closed rather than treating a document's existence as
        // a signature verification result.
        invalid = true;
      }
    }
    return ControlProofResult(
      controlId: controlId,
      status: expired ? ProofStatus.expired : ProofStatus.missing,
      semantics: semantics,
      completeness: completeness,
      diagnostics: invalid
          ? const ['External attestation requires a verified signed document']
          : const [],
    );
  }

  ControlProofResult _ingressProof(
    IrGraph graph,
    IrNode implementation,
    List<IrNode> providers,
    Map<String, Set<String>> dominators,
    String controlId,
    CoverageSemantics semantics,
    Map<String, CompletenessValue> completeness, {
    required bool requiresExternalVisibility,
  }) {
    if (providers.isEmpty) {
      return ControlProofResult(
        controlId: controlId,
        status: ProofStatus.missing,
        semantics: semantics,
        completeness: completeness,
      );
    }
    if (_isIncomplete(graph.completeness.routeRegistration) ||
        _isIncomplete(graph.completeness.middlewareOrder) ||
        _isIncomplete(graph.completeness.dynamicRegistration) ||
        (requiresExternalVisibility &&
            _isIncomplete(graph.completeness.externalVisibility))) {
      return ControlProofResult(
        controlId: controlId,
        status: ProofStatus.indeterminate,
        semantics: semantics,
        completeness: completeness,
      );
    }
    final dominates = providers.any(
      (provider) =>
          dominators[implementation.id]?.contains(provider.id) == true,
    );
    final bypass = dominates
        ? const <String>[]
        : (_findUnprotectedPathFromRoots(
                graph,
                implementation.id,
                providers.map((p) => p.id).toSet(),
              ) ??
              [implementation.id]);
    return ControlProofResult(
      controlId: controlId,
      status: dominates ? ProofStatus.proven : ProofStatus.failed,
      semantics: semantics,
      bypassPaths: dominates ? const [] : [bypass.join(' -> ')],
      completeness: completeness,
    );
  }

  List<String>? _findUnprotectedPathFromRoots(
    IrGraph graph,
    String target,
    Set<String> providerIds,
  ) {
    final predecessors = <String, List<String>>{};
    for (final edge in graph.edges) {
      if ({EdgeKind.precedes, EdgeKind.routesTo}.contains(edge.kind)) {
        predecessors.putIfAbsent(edge.targetId, () => []).add(edge.sourceId);
      }
    }
    final roots =
        graph.nodeIds
            .where((id) => (predecessors[id] ?? const []).isEmpty)
            .toList()
          ..sort();
    final queue = <List<String>>[
      ...roots.map((root) => [root]),
    ];
    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      final current = path.last;
      if (current == target) return path;
      final nextNodes =
          graph.edges
              .where(
                (edge) =>
                    edge.sourceId == current &&
                    {EdgeKind.precedes, EdgeKind.routesTo}.contains(edge.kind),
              )
              .map((edge) => edge.targetId)
              .toList()
            ..sort();
      for (final next in nextNodes) {
        if (providerIds.contains(next) || path.contains(next)) continue;
        queue.add([...path, next]);
      }
    }
    return null;
  }

  ControlProofResult _flowProof(
    IrGraph graph,
    IrNode implementation,
    List<IrNode> providers,
    String controlId,
    CoverageSemantics semantics, {
    required NodeKind targetKind,
    required String targetFlow,
    required String sourceFlow,
    required String completenessKey,
    required bool requiresExternalVisibility,
    bool legacyFixture = false,
  }) {
    final completeness = _completenessMap(graph.completeness);
    if (_isIncomplete(
          _completenessByName(graph.completeness, completenessKey),
        ) ||
        (requiresExternalVisibility &&
            _isIncomplete(graph.completeness.externalVisibility))) {
      return ControlProofResult(
        controlId: controlId,
        status: ProofStatus.indeterminate,
        semantics: semantics,
        completeness: completeness,
      );
    }
    final sources = graph.nodes.where(
      (node) =>
          node.properties['flow'] == sourceFlow ||
          (legacyFixture && node.id == implementation.id),
    );
    final targets = graph.nodes.where(
      (node) =>
          (node.kind == targetKind && node.properties['flow'] == targetFlow) ||
          (legacyFixture &&
              targetFlow == 'public-egress' &&
              node.id.startsWith('egress:')) ||
          (legacyFixture &&
              targetFlow == 'log-sink' &&
              node.id.startsWith('sink:')),
    );
    if (sources.isEmpty || targets.isEmpty) {
      return ControlProofResult(
        controlId: controlId,
        status: providers.isEmpty
            ? ProofStatus.missing
            : ProofStatus.indeterminate,
        semantics: semantics,
        completeness: completeness,
      );
    }
    final providerIds = providers.map((provider) => provider.id).toSet();
    final bypasses = <String>[];
    for (final source in sources) {
      for (final target in targets) {
        // A source that cannot reach its governed terminating destination is
        // not protected.  Treating the absence of a path as "no bypass" would
        // make an incomplete or dead-end failure/log topology look proven.
        final terminatingPath = _findPath(graph, source.id, target.id);
        if (terminatingPath == null) {
          bypasses.add('${source.id} -> <no path to> ${target.id}');
          continue;
        }
        final path = _findUnprotectedPath(
          graph,
          source.id,
          target.id,
          providerIds,
        );
        if (path != null) bypasses.add(path.join(' -> '));
      }
    }
    return ControlProofResult(
      controlId: controlId,
      status: bypasses.isEmpty ? ProofStatus.proven : ProofStatus.failed,
      semantics: semantics,
      bypassPaths: bypasses,
      completeness: completeness,
    );
  }

  Map<String, Set<String>> _dominators(
    IrGraph graph, {
    required Set<EdgeKind> allowedKinds,
  }) {
    final ids = graph.nodeIds;
    final predecessors = <String, Set<String>>{
      for (final id in ids) id: <String>{},
    };
    for (final edge in graph.edges.where(
      (edge) => allowedKinds.contains(edge.kind),
    )) {
      if (!ids.contains(edge.sourceId) || !ids.contains(edge.targetId)) {
        continue;
      }
      predecessors[edge.targetId]!.add(edge.sourceId);
    }
    final roots = ids.where((id) => predecessors[id]!.isEmpty).toSet();
    final dominators = <String, Set<String>>{
      for (final id in ids) id: roots.contains(id) ? {id} : {...ids},
    };
    var changed = true;
    while (changed) {
      changed = false;
      for (final id in ids.where((id) => !roots.contains(id))) {
        final preds = predecessors[id]!;
        if (preds.isEmpty) continue;
        final intersection = preds
            .map((pred) => dominators[pred]!)
            .reduce((left, right) => left.intersection(right).toSet());
        final next = {...intersection, id};
        if (!_same(dominators[id]!, next)) {
          dominators[id] = next;
          changed = true;
        }
      }
    }
    return dominators;
  }

  List<String>? _findUnprotectedPath(
    IrGraph graph,
    String source,
    String target,
    Set<String> providerIds,
  ) {
    final adjacency = <String, List<String>>{};
    for (final edge in graph.edges) {
      if (edge.kind != EdgeKind.flowsTo &&
          edge.kind != EdgeKind.routesTo &&
          edge.kind != EdgeKind.precedes) {
        continue;
      }
      adjacency.putIfAbsent(edge.sourceId, () => []).add(edge.targetId);
    }
    final queue = <List<String>>[
      [source],
    ];
    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      final current = path.last;
      if (current == target) return path;
      for (final next in adjacency[current] ?? const <String>[]) {
        if (providerIds.contains(next) || path.contains(next)) continue;
        queue.add([...path, next]);
      }
    }
    return null;
  }

  List<String>? _findPath(IrGraph graph, String source, String target) {
    final adjacency = <String, List<String>>{};
    for (final edge in graph.edges) {
      if (!{
        EdgeKind.flowsTo,
        EdgeKind.routesTo,
        EdgeKind.precedes,
      }.contains(edge.kind)) {
        continue;
      }
      adjacency.putIfAbsent(edge.sourceId, () => <String>[]).add(edge.targetId);
    }
    final queue = <List<String>>[
      [source],
    ];
    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      final current = path.last;
      if (current == target) return path;
      final next = [...?adjacency[current]]..sort();
      for (final id in next) {
        if (!path.contains(id)) queue.add([...path, id]);
      }
    }
    return null;
  }

  bool _isIncomplete(CompletenessValue value) =>
      value == CompletenessValue.indeterminate ||
      value == CompletenessValue.notVisible;

  CompletenessValue _completenessByName(GraphCompleteness value, String name) =>
      switch (name) {
        'failureFlow' => value.failureFlow,
        'logFlow' => value.logFlow,
        _ => CompletenessValue.notApplicable,
      };

  bool _requiresExternalVisibility(
    WorkspaceDiscoveryResult? workspace,
    String controlId,
    IrNode implementation,
  ) {
    final target =
        workspace?.data.controls[controlId]?['target']?.toString() ??
        implementation.target;
    return target == 'edge' || target == 'external';
  }

  Map<String, CompletenessValue> _completenessMap(GraphCompleteness value) => {
    'routeRegistration': value.routeRegistration,
    'middlewareOrder': value.middlewareOrder,
    'failureFlow': value.failureFlow,
    'logFlow': value.logFlow,
    'dynamicRegistration': value.dynamicRegistration,
    'externalVisibility': value.externalVisibility,
  };

  String _failureMessage(ControlProofResult result, String implementation) {
    if (result.bypassPaths.isEmpty) {
      return '${result.controlId} is not applied on every governed path to $implementation';
    }
    return '${result.controlId} has an uncovered governed path: ${result.bypassPaths.first}';
  }

  bool _same(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);
}
