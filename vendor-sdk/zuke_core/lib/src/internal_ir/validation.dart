import 'ir.dart';
import 'adapter_models.dart';
import '../evidence.dart';

enum ProofStatus {
  proven,
  verified,
  attested,
  failed,
  indeterminate,
  missing,
  expired,
}

/// Stable wire representation.  Do not use `CoverageSemantics.name` in a
/// persisted artifact: enum spelling is an implementation detail while these
/// values are a public schema contract.
extension CoverageSemanticsWire on CoverageSemantics {
  String get wireValue => switch (this) {
    CoverageSemantics.ingressDominance => 'ingress-dominance',
    CoverageSemantics.failureToPublicEgress => 'failure-to-public-egress',
    CoverageSemantics.sensitiveDataToLogSink => 'sensitive-data-to-log-sink',
    CoverageSemantics.externalAttestation => 'external-attestation',
    CoverageSemantics.verificationBacked => 'verification-backed',
  };

  static CoverageSemantics parse(Object? value) => switch (value) {
    'ingress-dominance' => CoverageSemantics.ingressDominance,
    'failure-to-public-egress' => CoverageSemantics.failureToPublicEgress,
    'sensitive-data-to-log-sink' => CoverageSemantics.sensitiveDataToLogSink,
    'external-attestation' => CoverageSemantics.externalAttestation,
    'verification-backed' => CoverageSemantics.verificationBacked,
    _ => throw FormatException('Unknown coverage semantics: $value'),
  };
}

class ControlProofResult {
  final String controlId;
  final String? requirementId;
  final ProofStatus status;
  final CoverageSemantics semantics;
  final List<String> providerIds;
  final List<String> bypassPaths;
  final String? governedGraphHash;
  final Map<String, CompletenessValue> completeness;
  final List<String> diagnostics;
  final List<String> evidenceDigests;
  final String target;
  final String variant;

  const ControlProofResult({
    required this.controlId,
    this.requirementId,
    required this.status,
    required this.semantics,
    this.providerIds = const [],
    this.bypassPaths = const [],
    this.governedGraphHash,
    this.completeness = const {},
    this.diagnostics = const [],
    this.evidenceDigests = const [],
    this.target = 'workspace',
    this.variant = 'default',
  });

  Map<String, Object?> toJson() => {
    'controlId': controlId,
    if (requirementId != null) 'requirementId': requirementId,
    'status': status.name,
    'semantics': semantics.wireValue,
    'target': target,
    'variant': variant,
    'providerIds': [...providerIds]..sort(),
    'evidenceDigests': [...evidenceDigests]..sort(),
    'bypassPaths': bypassPaths,
    if (governedGraphHash != null) 'governedGraphHash': governedGraphHash,
    'completeness': {
      for (final entry in completeness.entries) entry.key: entry.value.name,
    },
    'diagnostics': diagnostics,
  };
}

/// Compatibility name for internal source imports during this source-level
/// migration. It is not exported as a second wire model or public API.
class ValidationReport {
  final String engineVersion;
  final String workspace;
  final String profile;
  final List<IrDiagnostic> diagnostics;
  final List<ControlProofResult> controlProofs;
  final List<EvidenceRecord> evidence;
  final Map<String, String> graphHashes;
  final Map<String, CompletenessValue> completeness;
  final Map<String, String> adapterHashes;
  final List<String> requiredEvidence;
  final List<String> staleEvidence;
  final List<String> ineligibilityReasons;
  final bool eligible;

  const ValidationReport({
    this.engineVersion = '0.1.0',
    this.workspace = '',
    this.profile = 'pullRequest',
    this.diagnostics = const [],
    this.controlProofs = const [],
    this.evidence = const [],
    this.graphHashes = const {},
    this.completeness = const {},
    this.adapterHashes = const {},
    this.requiredEvidence = const [],
    this.staleEvidence = const [],
    this.ineligibilityReasons = const [],
    this.eligible = false,
  });

  Map<String, Object?> toJson() => {
    'kind': 'zuke.validation-report',
    'status': eligible ? 'passed' : 'failed',
    'engineVersion': engineVersion,
    'workspace': workspace,
    'profile': profile,
    'eligible': eligible,
    'diagnostics': diagnostics.map((d) => d.toJson()).toList(),
    'controlProofs': controlProofs.map((p) => p.toJson()).toList(),
    'evidence': evidence.map((e) => e.toJson()).toList(),
    'graphHashes': graphHashes,
    'adapterHashes': adapterHashes,
    'requiredEvidence': requiredEvidence,
    'staleEvidence': staleEvidence,
    'ineligibilityReasons': ineligibilityReasons,
    'completeness': {
      for (final entry in completeness.entries) entry.key: entry.value.name,
    },
  };
}
