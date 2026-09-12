import 'dart:io';

import 'package:test/test.dart';

import 'cli_test_helper.dart';
import 'support/temporary_directory.dart';

void main() {
  test('policy check rejects expired and unauthenticated acceptance', () async {
    final root = Directory.systemTemp.createTempSync('zuke-policy-');
    addTearDown(() => deleteTemporaryDirectory(root));
    final policy = Directory('${root.path}/policies')..createSync();
    File('${policy.path}/project-policy.yaml').writeAsStringSync('''
riskAcceptance:
  requiredApprovalCount: 2
  requiredRoles: [security, product]
  requiredCompensatingRuns: [scan]
''');
    final input = Directory('${root.path}/assurance')..createSync();
    File('${input.path}/risk-acceptance.yaml').writeAsStringSync('''
kind: zuke.risk-acceptance
id: risk-1
acceptedAt: 2026-09-01T00:00:00Z
expiresAt: 2026-09-05T00:00:00Z
commit: old
approvers:
  - id: security-owner
    role: security
compensatingRuns: []
''');

    final result = await runInProcessCli([
      'policy',
      'check',
      '--root',
      root.path,
      '--now',
      '2026-09-06T00:00:00Z',
      '--commit',
      'new',
      '--format',
      'json',
    ]);

    expect(result.exitCode, 1);
    expect(result.stdout, contains('ZK-POLICY-EXPIRED'));
    expect(result.stdout, contains('ZK-POLICY-COMMIT-MISMATCH'));
    expect(result.stdout, contains('ZK-POLICY-APPROVAL-NOT-AUTHENTICATED'));
  });
}
