import 'digest.dart';
import 'identity.dart';
import 'scenario_id.dart';

enum EvidenceMode { record, scenarioRecord, controlBacked, attestation }

final class EvidenceTypeDefinition {
  final String id;
  final EvidenceMode mode;

  const EvidenceTypeDefinition({required this.id, required this.mode});

  Map<String, Object?> toJson() => {'mode': mode.name};
}

final class EvidenceRequirement extends EvidenceSlot {
  final String? controlId;

  const EvidenceRequirement({
    required super.requirementId,
    required super.evidenceType,
    required super.target,
    super.variant,
    required super.sourcePackage,
    required super.sourceAdapter,
    this.controlId,
  });

  Map<String, Object?> toJson() => {
    ...super.toJson(),
    if (controlId != null) 'controlId': controlId,
  };
}

enum EvidenceStatus { passed, failed, skipped }

/// The one current semantic evidence record.
///
/// Test processes emit [ScenarioResult] or [SuiteResult]. The CLI binds those
/// results to this model after success and adds current workspace digests. The
/// nullable fields are retained only so the validator can report incomplete
/// in-memory fixtures; [fromJson] is strict and accepts only a complete final
/// record.
final class EvidenceRecord {
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

  String? get sourceDigest => digests['source'];

  Map<String, Object?> toJson() {
    for (final digest in digests.values) {
      Sha256Digest.parse(digest);
    }
    return {
      'kind': 'zuke.evidence-record',
      'requirementId': requirementId,
      'evidenceType': evidenceType,
      'target': target,
      'variant': variant,
      'executionId': executionId,
      'status': status.name,
      'scenarioIds': scenarioIds.map((id) => id.value).toList()..sort(),
      'controlIds': [...controlIds]..sort(),
      if (digests.isNotEmpty) 'digests': Map<String, String>.from(digests),
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
  }

  factory EvidenceRecord.fromJson(Map<Object?, Object?> raw) {
    if (raw['kind'] != 'zuke.evidence-record') {
      throw const FormatException(
        'Unsupported evidence record format; regenerate with the current Zuke CLI',
      );
    }
    final json = Map<Object?, Object?>.from(raw);
    String required(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Evidence record requires non-empty $key');
      }
      return value;
    }

    List<String> strings(String key) {
      final value = json[key] ?? const [];
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('Evidence $key must be a string list');
      }
      return value.cast<String>();
    }

    final rawDigests = json['digests'];
    if (rawDigests is! Map) {
      throw const FormatException('Evidence digests must be an object');
    }
    final digests = <String, String>{};
    for (final entry in rawDigests.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Evidence digest entries must be strings');
      }
      final digest = entry.value as String;
      Sha256Digest.parse(digest);
      digests[entry.key as String] = digest;
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

    final status = switch (required('status')) {
      'passed' => EvidenceStatus.passed,
      'failed' => EvidenceStatus.failed,
      'skipped' => EvidenceStatus.skipped,
      final value => throw FormatException('Unknown evidence status: $value'),
    };
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
      sourcePackage: required('sourcePackage'),
      sourceAdapter: required('sourceAdapter'),
      sourceCompatibilityId: required('sourceCompatibilityId'),
      attachmentDigests: strings('attachmentDigests'),
    );
  }
}
