import 'package:test/test.dart';
import 'package:zuke_core/zuke_core.dart';

void main() {
  final now = DateTime.utc(2026, 9, 6);

  Map<Object?, Object?> record({
    List<Map<String, Object?>>? approvers,
    String? expiresAt,
    String commit = 'abc',
  }) => {
    'kind': 'zuke.risk-acceptance',
    'id': 'risk-1',
    'acceptedAt': '2026-09-01T00:00:00Z',
    'expiresAt': expiresAt ?? '2026-09-30T00:00:00Z',
    'commit': commit,
    'approvers':
        approvers ??
        [
          {
            'id': 'security-owner',
            'role': 'security',
            'authenticated': true,
            'proof': {'digest': 'proof-1'},
          },
          {
            'id': 'product-owner',
            'role': 'product',
            'authenticated': true,
            'proof': {'digest': 'proof-2'},
          },
        ],
    'compensatingRuns': [
      {'id': 'scan', 'status': 'passed'},
    ],
  };

  test('validates consumer requirements independently of the record', () {
    final result = const RiskAcceptanceVerifier().verify(
      record(),
      requirements: const RiskAcceptanceRequirements(
        requiredApprovalCount: 2,
        requiredRoles: {'security', 'product'},
        requiredCompensatingRuns: {'scan'},
      ),
      expectedCommit: 'abc',
      expectedRelease: 'release-1',
      now: now,
    );

    // The fixture deliberately has no release field, so release binding fails.
    expect(result.valid, isFalse);
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      contains('ZK-POLICY-RELEASE-MISMATCH'),
    );
  });

  test('rejects duplicate approvers and unauthenticated names', () {
    final result = const RiskAcceptanceVerifier().verify(
      record(
        approvers: [
          {'id': 'same', 'role': 'security'},
          {'id': 'same', 'role': 'product'},
        ],
      ),
      requirements: const RiskAcceptanceRequirements(requiredApprovalCount: 2),
      now: now,
    );

    expect(result.valid, isFalse);
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      containsAll([
        'ZK-POLICY-DUPLICATE-APPROVER',
        'ZK-POLICY-APPROVAL-NOT-AUTHENTICATED',
      ]),
    );
  });

  test('rejects expired acceptance and mismatched commit', () {
    final result = const RiskAcceptanceVerifier().verify(
      record(expiresAt: '2026-09-05T00:00:00Z', commit: 'old'),
      expectedCommit: 'new',
      now: now,
    );

    expect(result.valid, isFalse);
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      containsAll(['ZK-POLICY-EXPIRED', 'ZK-POLICY-COMMIT-MISMATCH']),
    );
  });

  test('does not trust self-declared approval proof fields', () {
    final result = const RiskAcceptanceVerifier().verify(
      record(),
      requirements: const RiskAcceptanceRequirements(requiredApprovalCount: 2),
      expectedCommit: 'abc',
      now: now,
    );

    expect(result.authenticated, isFalse);
    expect(result.valid, isFalse);
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      contains('ZK-POLICY-APPROVAL-NOT-AUTHENTICATED'),
    );
  });
}
