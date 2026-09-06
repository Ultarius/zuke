import 'package:test/test.dart';
import 'package:zuke_cli/src/consumer_policy.dart';

void main() {
  test('programmatic defaults remain available', () {
    const document = ConsumerPolicyDocument();
    final requirements = document.toRequirements();
    expect(requirements.requiredApprovalCount, 1);
    expect(requirements.requiredRoles, isEmpty);
    expect(requirements.requiredCompensatingRuns, isEmpty);
  });

  test('parses explicit risk acceptance thresholds', () {
    final document = ConsumerPolicyDocument.fromMap({
      'riskAcceptance': {
        'requiredApprovalCount': 2,
        'requiredRoles': ['security'],
        'requiredCompensatingRuns': ['scan'],
      },
    });
    final requirements = document.toRequirements();
    expect(requirements.requiredApprovalCount, 2);
    expect(requirements.requiredRoles, {'security'});
    expect(requirements.requiredCompensatingRuns, {'scan'});
  });

  test('supports requiredApprovals alias and retains extensions', () {
    final document = ConsumerPolicyDocument.fromMap({
      'customField': 'keep',
      'riskAcceptance': {'requiredApprovals': 3, 'futureFlag': true},
    });
    expect(document.toRequirements().requiredApprovalCount, 3);
    expect(document.extensions['customField'], 'keep');
    expect(document.riskAcceptance.extensions['futureFlag'], isTrue);
  });

  test('rejects malformed recognized values', () {
    for (final invalid in [
      <String, Object?>{},
      {'riskAcceptance': null},
      {
        'riskAcceptance': {'requiredApprovalCount': 0},
      },
      {
        'riskAcceptance': {'requiredRoles': 'security'},
      },
      {
        'riskAcceptance': {
          'requiredRoles': ['ok', 42],
        },
      },
      {
        'riskAcceptance': {
          'requiredCompensatingRuns': [''],
        },
      },
      {'riskAcceptance': 'yes'},
    ]) {
      expect(
        () => ConsumerPolicyDocument.fromMap(invalid),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
