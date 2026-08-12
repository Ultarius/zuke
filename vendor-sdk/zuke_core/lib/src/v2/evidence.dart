import 'digest.dart';
import 'identity.dart';

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

final class EvidenceRecord extends EvidenceSlot {
  final String executionId;
  final String profile;
  final String status;
  final String sourceCompatibilityId;
  final String runnerId;
  final String runnerCompatibilityId;
  final String sourceDigest;
  final List<String> scenarioIds;
  final List<String> controlIds;

  const EvidenceRecord({
    required super.requirementId,
    required super.evidenceType,
    required super.target,
    super.variant,
    required super.sourcePackage,
    required super.sourceAdapter,
    required this.executionId,
    required this.profile,
    required this.status,
    required this.sourceCompatibilityId,
    required this.runnerId,
    required this.runnerCompatibilityId,
    required this.sourceDigest,
    this.scenarioIds = const [],
    this.controlIds = const [],
  });

  Map<String, Object?> toJson() {
    Sha256Digest.parse(sourceDigest);
    return {
      'kind': 'zuke.evidence-record',
      ...super.toJson(),
      'executionId': executionId,
      'profile': profile,
      'status': status,
      'sourceAdapter': sourceAdapter,
      'sourceCompatibilityId': sourceCompatibilityId,
      'runnerId': runnerId,
      'runnerCompatibilityId': runnerCompatibilityId,
      'sourceDigest': sourceDigest,
      'scenarioIds': [...scenarioIds]..sort(),
      'controlIds': [...controlIds]..sort(),
    };
  }

  factory EvidenceRecord.fromJson(Map<Object?, Object?> json) {
    if (json['kind'] != 'zuke.evidence-record') {
      throw const FormatException(
        'Unsupported evidence record format; regenerate with the current Zuke CLI',
      );
    }
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Evidence record requires non-empty $key');
      }
      return value;
    }

    List<String> strings(String key) {
      final value = json[key] ?? const [];
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('Evidence record $key must be a string list');
      }
      return value.cast<String>();
    }

    final status = requiredString('status');
    if (!const {'passed', 'failed', 'skipped'}.contains(status)) {
      throw FormatException('Unknown evidence status: $status');
    }
    final digest = requiredString('sourceDigest');
    Sha256Digest.parse(digest);
    return EvidenceRecord(
      requirementId: requiredString('requirementId'),
      evidenceType: requiredString('evidenceType'),
      target: requiredString('target'),
      variant: requiredString('variant'),
      sourcePackage: requiredString('sourcePackage'),
      sourceAdapter: requiredString('sourceAdapter'),
      executionId: requiredString('executionId'),
      profile: requiredString('profile'),
      status: status,
      sourceCompatibilityId: requiredString('sourceCompatibilityId'),
      runnerId: requiredString('runnerId'),
      runnerCompatibilityId: requiredString('runnerCompatibilityId'),
      sourceDigest: digest,
      scenarioIds: strings('scenarioIds'),
      controlIds: strings('controlIds'),
    );
  }
}
