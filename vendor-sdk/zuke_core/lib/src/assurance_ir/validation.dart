import 'ir.dart';
import 'adapter_models.dart';
import 'scenario_id.dart';

enum ProofStatus {
  proven,
  verified,
  attested,
  failed,
  indeterminate,
  missing,
  expired,
}

enum EvidenceStatus { passed, failed, skipped }

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

class EvidenceRecord {
  final String requirementId;
  final String evidenceType;
  final String target;
  final String variant;
  final String executionId;
  final EvidenceStatus status;
  final List<ScenarioId> scenarioIds;
  final List<String> controlIds;
  final Map<String, String> digests;
  final String? candidateId;
  final String profile;
  final String? runnerId;
  final String? runnerCompatibilityId;
  final String? sourcePackage;
  final String? sourceAdapter;
  final String? sourceCompatibilityId;
  final List<String> attachmentDigests;

  const EvidenceRecord({
    required this.requirementId,
    required this.evidenceType,
    required this.target,
    this.variant = 'default',
    required this.executionId,
    this.status = EvidenceStatus.passed,
    this.scenarioIds = const [],
    this.controlIds = const [],
    this.digests = const {},
    this.candidateId,
    this.profile = 'pullRequest',
    this.runnerId,
    this.runnerCompatibilityId,
    this.sourcePackage,
    this.sourceAdapter,
    this.sourceCompatibilityId,
    this.attachmentDigests = const [],
  });

  Map<String, Object?> toJson() => {
    'schemaVersion':
        sourcePackage == null &&
                sourceAdapter == null &&
                sourceCompatibilityId == null
            ? 'zuke.evidence-record.v1'
            : 'zuke.evidence-record.v2',
    'requirementId': requirementId,
    'evidenceType': evidenceType,
    'target': target,
    'variant': variant,
    'executionId': executionId,
    'status': status.name,
    'scenarioIds': scenarioIds.map((id) => id.value).toList()..sort(),
    'controlIds': [...controlIds]..sort(),
    if (digests.isNotEmpty) 'digests': digests,
    if (candidateId != null) 'candidateId': candidateId,
    'profile': profile,
    if (runnerId != null) 'runnerId': runnerId,
    if (runnerCompatibilityId != null)
      'runnerCompatibilityId': runnerCompatibilityId,
    if (sourcePackage != null) 'sourcePackage': sourcePackage,
    if (sourceAdapter != null) 'sourceAdapter': sourceAdapter,
    if (sourceCompatibilityId != null)
      'sourceCompatibilityId': sourceCompatibilityId,
    if (attachmentDigests.isNotEmpty)
      'attachmentDigests': [...attachmentDigests]..sort(),
  };

  /// Validates the semantic record at the filesystem boundary.  A record
  /// which merely resembles evidence must not silently acquire defaults that
  /// allow it to satisfy a required-evidence slot.
  factory EvidenceRecord.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 'zuke.evidence-record.v1' &&
        json['schemaVersion'] != 'zuke.evidence-record.v2') {
      throw const FormatException('Unsupported evidence record schema');
    }
    String required(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Evidence record requires non-empty $key');
      }
      return value;
    }

    String? optional(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.isEmpty) {
        throw FormatException('Evidence record requires non-empty $key');
      }
      return value;
    }

    final status = switch (required('status')) {
      'passed' => EvidenceStatus.passed,
      'failed' => EvidenceStatus.failed,
      'skipped' => EvidenceStatus.skipped,
      final value => throw FormatException('Unknown evidence status: $value'),
    };
    final digests = <String, String>{};
    final rawDigests = json['digests'];
    if (rawDigests is! Map) {
      throw const FormatException('Evidence digests must be an object');
    }
    for (final entry in rawDigests.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Evidence digest entries must be strings');
      }
      if (!RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(entry.value as String)) {
        throw FormatException('Invalid evidence digest for ${entry.key}');
      }
      digests[entry.key as String] = entry.value as String;
    }
    for (final key in const [
      'source',
      'contract',
      'mapping',
      'specificationIndex',
      'result',
    ]) {
      if (!digests.containsKey(key)) {
        throw FormatException('Evidence record is missing $key digest');
      }
    }
    List<String> strings(String key) {
      final value = json[key] ?? const [];
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('Evidence $key must be a string list');
      }
      return value.cast<String>();
    }

    final isV2 = json['schemaVersion'] == 'zuke.evidence-record.v2';
    final sourcePackage = isV2 ? required('sourcePackage') : optional('sourcePackage');
    final sourceAdapter = isV2 ? required('sourceAdapter') : optional('sourceAdapter');
    final sourceCompatibilityId = isV2
        ? required('sourceCompatibilityId')
        : optional('sourceCompatibilityId');
    return EvidenceRecord(
      requirementId: required('requirementId'),
      evidenceType: required('evidenceType'),
      target: required('target'),
      variant: required('variant'),
      executionId: required('executionId'),
      status: status,
      scenarioIds: [
        for (final id in strings('scenarioIds')) ScenarioId.parse(id),
      ],
      controlIds: strings('controlIds'),
      digests: digests,
      candidateId: required('candidateId'),
      profile: required('profile'),
      runnerId: required('runnerId'),
      runnerCompatibilityId: required('runnerCompatibilityId'),
      sourcePackage: sourcePackage,
      sourceAdapter: sourceAdapter,
      sourceCompatibilityId: sourceCompatibilityId,
      attachmentDigests: strings('attachmentDigests'),
    );
  }
}

class ValidationReport {
  final String engineVersion;
  final String workspace;
  final String profile;
  final List<Diagnostic> diagnostics;
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
    'schemaVersion': 'zuke.validation-report.v1',
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
