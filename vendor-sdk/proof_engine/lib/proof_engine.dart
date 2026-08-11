import 'package:assurance_ir/assurance_ir.dart';

/// Exact stale-matching key used by the V2 proof engine.
String evidenceSlotKey(EvidenceSlot slot) => slot.exactKey;

final class EvidenceMatchResult {
  final EvidenceRecordV2? record;
  final String? diagnostic;

  const EvidenceMatchResult({this.record, this.diagnostic});

  bool get matched => record != null && diagnostic == null;
}

EvidenceMatchResult matchEvidence(
  EvidenceRequirementV2 requirement,
  Iterable<EvidenceRecordV2> records,
) {
  final matches = records.where(
    (record) => record.exactKey == requirement.exactKey,
  ).toList();
  if (matches.length > 1) {
    return const EvidenceMatchResult(
      diagnostic: 'ZK-EVIDENCE-AMBIGUOUS-SOURCE: multiple exact source matches',
    );
  }
  if (matches.isEmpty) {
    return const EvidenceMatchResult(
      diagnostic: 'ZK-EVIDENCE-MISSING-SOURCE: no exact source match',
    );
  }
  return EvidenceMatchResult(record: matches.single);
}
