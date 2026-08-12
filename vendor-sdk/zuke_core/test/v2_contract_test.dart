import 'package:test/test.dart';
import 'package:zuke_core/zuke_core.dart';

void main() {
  test('diagnostics default null ownership to unknown', () {
    final diagnostic = Diagnostic.fromJson({
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
        () => Diagnostic.fromJson({
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
    const result = CommandResult(
      command: 'gate',
      stage: 'gate',
      exitCode: 1,
      status: CommandStatus.failed,
      eligible: false,
    );
    expect(CommandResult.fromJson(result.toJson()).succeeded, isFalse);

    for (final field in const ['command', 'stage', 'status']) {
      final json = result.toJson()..remove(field);
      expect(() => CommandResult.fromJson(json), throwsFormatException);
    }
    expect(
      () => CommandResult.fromJson({
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
      () => EvidenceRecord.fromJson({
        'kind': 'zuke.evidence-record.legacy',
      }),
      throwsFormatException,
    );
    expect(
      () => EvidenceRecord.fromJson({
        'kind': 'zuke.evidence-record',
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
