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
    expect(
      () => Diagnostic.fromJson({
        'code': 'ZK-TEST-003',
        'stage': 'test',
        'severity': 'error',
        'owner': 'unknown',
        'message': 'failure',
        'remediation': 42,
      }),
      throwsFormatException,
    );
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
      () => CommandResult.fromJson({...result.toJson(), 'status': 'passed'}),
      throwsFormatException,
    );
    for (final fields in const [
      {'exitCode': 0, 'eligible': false},
      {'exitCode': 1, 'eligible': true},
    ]) {
      expect(
        () => CommandResult.fromJson({...result.toJson(), ...fields}),
        throwsFormatException,
      );
    }
  });

  test('nested profile stages and diagnostics are validated', () {
    const result = CommandResult(
      command: 'gate',
      stage: 'gate',
      exitCode: 0,
      status: CommandStatus.passed,
      eligible: true,
      details: {
        'profiles': [
          {
            'profile': 'pullRequest',
            'status': 'passed',
            'exitCode': 0,
            'eligible': true,
            'diagnostics': <Object?>[],
            'stages': [
              {
                'name': 'lock',
                'status': 'passed',
                'exitCode': 0,
                'eligible': true,
                'diagnostics': <Object?>[],
              },
            ],
          },
        ],
      },
    );
    expect(CommandResult.fromJson(result.toJson()).succeeded, isTrue);
    final malformed = {
      ...result.toJson(),
      'profiles': [
        {
          'profile': 'pullRequest',
          'diagnostics': <Object?>[],
          'stages': [
            {
              'name': 'lock',
              'status': 'passed',
              'exitCode': 1,
              'eligible': false,
              'diagnostics': <Object?>[],
            },
          ],
        },
      ],
    };
    expect(() => CommandResult.fromJson(malformed), throwsFormatException);
    expect(
      () => CommandResult.fromJson({
        ...result.toJson(),
        'profiles': [
          {
            'profile': 'pullRequest',
            'status': 'passed',
            'exitCode': 1,
            'eligible': false,
            'diagnostics': <Object?>[],
            'stages': <Object?>[],
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('command-result details cannot overwrite envelope fields', () {
    const result = CommandResult(
      command: 'gate',
      stage: 'gate',
      exitCode: 0,
      status: CommandStatus.passed,
      eligible: true,
      details: {'status': 'failed'},
    );
    expect(() => result.toJson(), throwsStateError);
  });

  test('nested failed and skipped stages fail closed on contradictions', () {
    const result = CommandResult(
      command: 'gate',
      stage: 'gate',
      exitCode: 0,
      status: CommandStatus.passed,
      eligible: true,
    );
    for (final stage in const [
      {
        'name': 'failed-with-zero-exit',
        'status': 'failed',
        'exitCode': 0,
        'eligible': false,
        'diagnostics': <Object?>[],
      },
      {
        'name': 'failed-but-eligible',
        'status': 'failed',
        'exitCode': 1,
        'eligible': true,
        'diagnostics': <Object?>[],
      },
      {
        'name': 'skipped-with-error',
        'status': 'skipped',
        'exitCode': 1,
        'eligible': false,
        'diagnostics': <Object?>[],
      },
      {
        'name': 'skipped-and-eligible',
        'status': 'skipped',
        'exitCode': 0,
        'eligible': true,
        'diagnostics': <Object?>[],
      },
    ]) {
      expect(
        () => CommandResult.fromJson({
          ...result.toJson(),
          'stages': [stage],
        }),
        throwsFormatException,
        reason: '${stage['name']}',
      );
    }
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

  test('runner execution context is absent when unmanaged', () {
    expect(RunnerExecutionContext.fromEnvironment(const {}), isNull);
  });

  test('runner execution context rejects partial managed environments', () {
    expect(
      () => RunnerExecutionContext.fromEnvironment(const {
        'ZUKE_RESULT_DIR': '/tmp/results',
      }),
      throwsFormatException,
    );
    expect(
      () =>
          RunnerExecutionContext.fromEnvironment(const {'ZUKE_RESULT_DIR': ''}),
      throwsFormatException,
    );
  });

  test('runner execution context round trips all managed identities', () {
    const context = {
      'ZUKE_RESULT_DIR': '/tmp/results',
      'ZUKE_PROFILE': 'pullRequest',
      'ZUKE_TARGET': 'backend',
      'ZUKE_RUNNER_ID': 'backend-tests',
      'ZUKE_RUNNER_COMPATIBILITY_ID': 'backend-runner-v1',
      'ZUKE_SOURCE_PACKAGE': 'backend',
      'ZUKE_SOURCE_ADAPTER': 'dart-frog',
      'ZUKE_SOURCE_COMPATIBILITY_ID': 'dart-frog-gen-v1',
    };
    final parsed = RunnerExecutionContext.fromEnvironment(context);
    expect(parsed, isNotNull);
    expect(parsed!.toEnvironment(), context);
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
      () => EvidenceRecord.fromJson({'kind': 'zuke.evidence-record.legacy'}),
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
