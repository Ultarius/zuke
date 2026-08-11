import 'package:test/test.dart';
import 'package:zuke_core/v2.dart';

void main() {
  test('diagnostics default null ownership to unknown', () {
    final diagnostic = DiagnosticV2.fromJson({
      'code': 'ZK-TEST-001',
      'stage': 'test',
      'severity': 'error',
      'owner': null,
      'message': 'failure',
    });
    expect(diagnostic.owner, DiagnosticOwner.unknown);
  });

  test('empty or unknown diagnostic owners fail closed', () {
    for (final owner in ['', 'package-owner']) {
      expect(
        () => DiagnosticV2.fromJson({
          'code': 'ZK-TEST-002',
          'stage': 'test',
          'severity': 'error',
          'owner': owner,
          'message': 'failure',
        }),
        throwsFormatException,
      );
    }
  });

  test('command result requires identity fields and consistent status', () {
    const result = CommandResultV2(
      command: 'gate',
      stage: 'gate',
      exitCode: 1,
      status: CommandStatus.failed,
      eligible: false,
    );
    expect(CommandResultV2.fromJson(result.toJson()).succeeded, isFalse);

    for (final field in const ['command', 'stage', 'status']) {
      final json = result.toJson()..remove(field);
      expect(() => CommandResultV2.fromJson(json), throwsFormatException);
    }
    expect(
      () => CommandResultV2.fromJson({
        ...result.toJson(),
        'status': 'passed',
      }),
      throwsFormatException,
    );
  });

  test('execution identity requires all environment variables together', () {
    const environment = {
      'ZUKE_SOURCE_PACKAGE': 'contract',
      'ZUKE_SOURCE_ADAPTER': 'dart-source',
      'ZUKE_SOURCE_COMPATIBILITY_ID': 'dart-source-v2',
    };
    final identity = ExecutionSourceIdentity.fromEnvironment(environment);
    expect(identity.toJson()['sourcePackage'], 'contract');
    expect(
      () => ExecutionSourceIdentity.fromEnvironment({
        'ZUKE_SOURCE_PACKAGE': 'contract',
      }),
      throwsFormatException,
    );
  });

  test('sha256 digest accepts only canonical lowercase values', () {
    final value = 'sha256:${List.filled(64, 'a').join()}';
    expect(Sha256Digest.parse(value).value, value);
    expect(
      () => Sha256Digest.parse('sha256:${List.filled(64, 'A').join()}'),
      throwsFormatException,
    );
  });

  test('evidence record rejects malformed schema and digest', () {
    expect(
      () => EvidenceRecordV2.fromJson({
        'schemaVersion': 'zuke.evidence-record.v1',
      }),
      throwsFormatException,
    );
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
        'sourceCompatibilityId': 'dart-source-v2',
        'runnerId': 'runner',
        'runnerCompatibilityId': 'runner-v2',
        'sourceDigest': 'invalid',
      }),
      throwsFormatException,
    );
  });
}
