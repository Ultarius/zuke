import 'package:assurance_ir/assurance_ir.dart';
import 'package:test/test.dart';

void main() {
  test('diagnostics default unknown ownership and round trip', () {
    const diagnostic = DiagnosticV2(
      code: 'ZK-TEST-001',
      stage: 'test',
      severity: DiagnosticSeverity.error,
      message: 'failure',
    );
    final decoded = DiagnosticV2.fromJson(diagnostic.toJson());
    expect(decoded.owner, DiagnosticOwner.unknown);
    expect(decoded.code, 'ZK-TEST-001');
  });

  test('command result is failed when status and exit code fail', () {
    const result = CommandResultV2(
      command: 'gate',
      stage: 'gate',
      exitCode: 1,
      status: 'failed',
      eligible: false,
    );
    final decoded = CommandResultV2.fromJson(result.toJson());
    expect(decoded.succeeded, isFalse);
  });

  test('evidence slots include all source identity fields', () {
    const slot = EvidenceSlot(
      requirementId: 'RULE-1',
      evidenceType: 'contract',
      target: 'contract',
      sourcePackage: 'secret-society-contract',
      sourceAdapter: 'dart-source',
    );
    expect(slot.exactKey, contains('secret-society-contract|dart-source'));
  });

  test('malformed evidence digest fails closed', () {
    expect(
      () => EvidenceRecordV2.fromJson({
        'schemaVersion': 'zuke.evidence-record.v2',
        'requirementId': 'RULE-1',
        'evidenceType': 'contract',
        'target': 'contract',
        'variant': 'default',
        'sourcePackage': 'contract',
        'sourceAdapter': 'dart-source',
        'executionId': 'exec-1',
        'profile': 'pullRequest',
        'status': 'passed',
        'sourceCompatibilityId': 'v1',
        'runnerId': 'runner',
        'runnerCompatibilityId': 'runner-v1',
        'sourceDigest': 'not-a-digest',
      }),
      throwsFormatException,
    );
  });
}
