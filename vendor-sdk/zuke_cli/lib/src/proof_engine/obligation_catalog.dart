import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import '../ir.dart' as ir;

/// The validator that owns one assurance obligation.
enum ProofOwner { structuralDominance, verificationBacked, attestation }

sealed class AssuranceObligation {
  const AssuranceObligation(this.key, this.owner);

  final String key;
  final ProofOwner owner;
}

/// Coverage obligation for one implementation binding.
final class ImplementationCoverageObligation extends AssuranceObligation {
  ImplementationCoverageObligation({
    required this.binding,
    required this.packageId,
    required this.mode,
  }) : super(binding.key, _ownerForMode(mode));

  final BindingIdentity binding;
  final String packageId;
  final ir.PlacementMode mode;

  static ProofOwner _ownerForMode(ir.PlacementMode mode) => switch (mode) {
    ir.PlacementMode.topologyAuthoritative => ProofOwner.structuralDominance,
    ir.PlacementMode.annotationGoverned => ProofOwner.verificationBacked,
  };
}

/// One specification-declared control obligation.
final class ControlObligation extends AssuranceObligation {
  ControlObligation({
    required this.requirementId,
    required this.controlId,
    required this.target,
    required this.variant,
    required this.slot,
    required this.semantics,
  }) : super(
         '$requirementId|$controlId|$target|$variant|$slot',
         _ownerForSemantics(semantics),
       );

  final String requirementId;
  final String controlId;
  final String target;
  final String variant;
  final String slot;
  final ir.CoverageSemantics semantics;

  static ProofOwner _ownerForSemantics(ir.CoverageSemantics semantics) =>
      switch (semantics) {
        ir.CoverageSemantics.externalAttestation => ProofOwner.attestation,
        ir.CoverageSemantics.verificationBacked =>
          ProofOwner.verificationBacked,
        ir.CoverageSemantics.ingressDominance ||
        ir.CoverageSemantics.failureToPublicEgress ||
        ir.CoverageSemantics.sensitiveDataToLogSink =>
          ProofOwner.structuralDominance,
      };
}

/// Normalized obligation inventory for one validation run.
///
/// This is deliberately CLI-internal. It is the single place where source
/// symbols become semantic binding keys and where control semantics select a
/// proof owner. Package identity is retained only as provenance needed to
/// choose topology authority; it is never part of [BindingIdentity.key].
final class AssuranceObligationCatalog {
  final List<ImplementationCoverageObligation> implementationCoverage;
  final List<ControlObligation> controls;
  final List<ir.IrDiagnostic> diagnostics;

  const AssuranceObligationCatalog({
    this.implementationCoverage = const [],
    this.controls = const [],
    this.diagnostics = const [],
  });

  factory AssuranceObligationCatalog.build(
    WorkspaceDiscoveryResult workspace,
    List<ir.IrAdapterOutput> outputs,
  ) {
    final diagnostics = <ir.IrDiagnostic>[];
    final authoritative = <String>{};
    for (final output in outputs) {
      final graph = output.graph;
      if (graph == null ||
          !graph.nodes.any((node) => node.kind == ir.NodeKind.entryPoint)) {
        continue;
      }
      for (final target
          in graph.nodes.map((node) => node.target).whereType<String>()) {
        authoritative.add('${output.packageName ?? ''}|$target');
      }
    }

    final bindings = <String, ImplementationCoverageObligation>{};
    for (final output in outputs) {
      for (final symbol in output.symbols.where(
        (symbol) => symbol.kind == 'requirementBoundary',
      )) {
        final target = symbol.target;
        if (target == null || target.isEmpty) {
          diagnostics.add(
            const ir.IrDiagnostic(
              code: 'ZK-BINDING-IDENTITY-MISSING',
              message: 'Implementation binding is missing an extraction target',
              severity: ir.IrDiagnosticSeverity.error,
            ),
          );
          continue;
        }
        if (!isValidBindingSlot(symbol.slot)) {
          diagnostics.add(
            ir.IrDiagnostic(
              code: 'ZK-BINDING-SLOT-INVALID',
              message:
                  'Implementation binding has an invalid slot: ${symbol.slot}',
              severity: ir.IrDiagnosticSeverity.error,
            ),
          );
          continue;
        }
        final mode =
            authoritative.contains('${output.packageName ?? ''}|$target')
            ? ir.PlacementMode.topologyAuthoritative
            : ir.PlacementMode.annotationGoverned;
        for (final requirementId in symbol.requirementIds) {
          final binding = BindingIdentity(
            subjectKind: 'requirement',
            subjectId: requirementId,
            target: target,
            role: 'implementation',
            variant: symbol.variant,
            slot: symbol.slot,
          );
          if (bindings.containsKey(binding.key)) {
            diagnostics.add(
              ir.IrDiagnostic(
                code: 'ZK-BINDING-IDENTITY-DUPLICATE',
                message:
                    'Duplicate implementation binding identity: ${binding.key}',
                severity: ir.IrDiagnosticSeverity.error,
              ),
            );
            continue;
          }
          bindings[binding.key] = ImplementationCoverageObligation(
            binding: binding,
            packageId: output.packageName ?? '',
            mode: mode,
          );
        }
      }
    }

    final controls = <String, ControlObligation>{};
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final requirementId = rule.metadata.id;
        if (requirementId == null) continue;
        void addControl({
          required String controlId,
          required String target,
          required String variant,
          required String slot,
        }) {
          final obligation = ControlObligation(
            requirementId: requirementId,
            controlId: controlId,
            target: target,
            variant: variant,
            slot: slot,
            semantics: _semanticsFor(workspace, controlId),
          );
          controls[obligation.key] = obligation;
        }

        for (final ref
            in rule.metadata.requires ?? const <ParsedControlRef>[]) {
          if (ref.kind != 'control') continue;
          addControl(
            controlId: ref.id,
            target: ref.target,
            variant: ref.variant,
            slot: ref.slot,
          );
        }
        final profile = rule.metadata.securityProfile;
        if (profile == null) continue;
        for (final policy in workspace.data.policies.values) {
          final profiles = policy['securityProfiles'];
          final definition = profiles is Map ? profiles[profile] : null;
          final requires = definition is Map ? definition['requires'] : null;
          if (requires is! List) continue;
          for (final raw in requires.whereType<Map>()) {
            final controlId = raw['id']?.toString();
            if (controlId == null || controlId.isEmpty) continue;
            final target = raw['target']?.toString();
            if (target == null || target.isEmpty) {
              diagnostics.add(
                ir.IrDiagnostic(
                  code: 'ZK-BINDING-IDENTITY-MISSING',
                  message:
                      'Security profile control $controlId is missing target identity',
                  severity: ir.IrDiagnosticSeverity.error,
                ),
              );
              continue;
            }
            addControl(
              controlId: controlId,
              target: target,
              variant: raw['variant']?.toString() ?? 'default',
              slot: raw['slot']?.toString() ?? 'primary',
            );
          }
        }
      }
    }

    return AssuranceObligationCatalog(
      implementationCoverage: bindings.values.toList(growable: false),
      controls: controls.values.toList(growable: false),
      diagnostics: diagnostics,
    );
  }

  static ir.CoverageSemantics _semanticsFor(
    WorkspaceDiscoveryResult workspace,
    String controlId,
  ) => switch (workspace.data.controls[controlId]?['coverageSemantics']) {
    'failure-to-public-egress' => ir.CoverageSemantics.failureToPublicEgress,
    'sensitive-data-to-log-sink' => ir.CoverageSemantics.sensitiveDataToLogSink,
    'external-attestation' => ir.CoverageSemantics.externalAttestation,
    'verification-backed' => ir.CoverageSemantics.verificationBacked,
    _ => ir.CoverageSemantics.ingressDominance,
  };
}
