import 'ir.dart';
import 'adapter_models.dart';
import '../evidence.dart';
import '../binding_identity.dart';

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
  final String slot;

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
    this.slot = 'primary',
  });

  Map<String, Object?> toJson() => {
    'controlId': controlId,
    if (requirementId != null) 'requirementId': requirementId,
    'status': status.name,
    'semantics': semantics.wireValue,
    'target': target,
    'variant': variant,
    'slot': slot,
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

/// Authority used to discharge an implementation binding.
enum PlacementMode { topologyAuthoritative, annotationGoverned }

/// Deterministic result for one implementation binding obligation.
final class ImplementationCoverageResult {
  final BindingIdentity binding;
  final PlacementMode mode;
  final ProofStatus status;
  final String? governedGraphHash;
  final List<String> evidenceDigests;
  final List<String> diagnostics;

  const ImplementationCoverageResult({
    required this.binding,
    required this.mode,
    required this.status,
    this.governedGraphHash,
    this.evidenceDigests = const [],
    this.diagnostics = const [],
  });

  factory ImplementationCoverageResult.fromJson(Map<Object?, Object?> raw) {
    final binding = raw['binding'];
    if (binding is! Map) {
      throw const FormatException(
        'Implementation coverage requires a binding identity',
      );
    }
    String requiredString(String key) {
      final value = raw[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Implementation coverage requires $key');
      }
      return value;
    }

    final mode = PlacementMode.values.byName(requiredString('mode'));
    final status = ProofStatus.values.byName(requiredString('status'));
    final evidence = raw['evidenceDigests'];
    final diagnostics = raw['diagnostics'];
    List<String> strings(Object? value, String field) {
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('Implementation coverage requires $field list');
      }
      return value.cast<String>();
    }

    return ImplementationCoverageResult(
      binding: BindingIdentity.fromJson(Map<String, Object?>.from(binding)),
      mode: mode,
      status: status,
      governedGraphHash: raw['governedGraphHash'] as String?,
      evidenceDigests: strings(evidence ?? const [], 'evidenceDigests'),
      diagnostics: strings(diagnostics ?? const [], 'diagnostics'),
    );
  }

  Map<String, Object?> toJson() => {
    'binding': binding.toJson(),
    'mode': mode.name,
    'status': status.name,
    if (governedGraphHash != null) 'governedGraphHash': governedGraphHash,
    'evidenceDigests': [...evidenceDigests]..sort(),
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
  final List<ImplementationCoverageResult> implementationCoverage;
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
    this.implementationCoverage = const [],
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
    'implementationCoverage': implementationCoverage
        .map((p) => p.toJson())
        .toList(),
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
