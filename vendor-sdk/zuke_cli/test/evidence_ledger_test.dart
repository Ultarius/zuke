import 'dart:convert';

import 'package:test/test.dart';
import 'package:zuke_cli/src/evidence_ledger.dart';
import 'package:zuke_core/zuke_core.dart';

void main() {
  final digests = {
    for (final key in const [
      'source',
      'contract',
      'mapping',
      'specificationIndex',
      'result',
    ])
      key: 'sha256:${List.filled(64, 'a').join()}',
  };
  final record = EvidenceRecord(
    requirementId: 'RULE-LEDGER-001',
    evidenceType: 'contract',
    target: 'contract',
    sourcePackage: 'contract-package',
    sourceAdapter: 'dart-source',
    executionId: 'execution-1',
    profile: 'pullRequest',
    status: EvidenceStatus.passed,
    sourceCompatibilityId: 'dart-source-package-v1',
    runnerId: 'contract-runner',
    runnerCompatibilityId: 'contract-runner-v2',
    candidateId: 'SCN-LEDGER-001',
    digests: digests,
  );

  test('ledger entry round-trips with an independent entry digest', () {
    final entry = EvidenceLedgerEntry(record);
    final decoded = EvidenceLedgerEntry.fromJson(entry.toJson());

    expect(decoded.record.toJson(), record.toJson());
    expect(decoded.digest, entry.digest);
    expect(decoded.toJson()['digest'], startsWith('sha256:'));
  });

  test('ledger digest mismatch fails closed', () {
    final entry = EvidenceLedgerEntry(record).toJson();
    final tampered = jsonDecode(jsonEncode(entry)) as Map<String, Object?>;
    tampered['digest'] = 'sha256:${List.filled(64, 'b').join()}';

    expect(() => EvidenceLedgerEntry.fromJson(tampered), throwsFormatException);
  });
}
