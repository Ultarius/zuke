import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zuke_cli/zuke_cli.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke/runner.dart';
import 'package:test/test.dart';

const _runnerIdentity = ExecutionSourceIdentity(
  sourcePackage: 'fake-supervisor',
  sourceAdapter: 'dart-source',
  sourceCompatibilityId: 'dart-source-package-v1',
);

void main() {
  group('configured runner supervision', () {
    test('forwards a configured runner to the injected supervisor', () async {
      final root = _workspace();
      addTearDown(() => root.delete(recursive: true));
      final supervisor = _FakeSupervisor(ProcessResult(1, 0, 'ok', ''));
      final exitCode = await ZukeCli(
        processSupervisor: supervisor,
      ).run(['test', '--root', root.path]);

      // This test exercises forwarding, not evidence publication. An empty
      // result directory with no required evidence is valid.
      expect(exitCode, 0);
      expect(supervisor.requests, hasLength(1));
      final request = supervisor.requests.single;
      final expectedExec = Platform.isWindows ? 'dart.exe' : 'dart';
      expect(request.executable.toLowerCase(), endsWith(expectedExec));
      expect(request.arguments, [
        '--disable-dart-dev',
        '--suppress-analytics',
        'test',
        'test',
      ]);
      expect(request.workingDirectory, root.path);
      expect(request.startupTimeout, const Duration(seconds: 60));
      expect(request.executionTimeout, const Duration(seconds: 7));
      expect(request.environment['ZUKE_RUNNER_ID'], 'unit-runner');
      expect(request.environment['ZUKE_PROFILE'], 'pullRequest');
      expect(request.environment['ZUKE_RESULT_DIR'], isNotEmpty);
    });

    test('runnerMode comes from YAML and CLI overrides it', () async {
      final root = _workspace(
        runners: '''
    - id: unit-runner
      kind: setup
      target: backend
      sourcePackage: fake-supervisor
      sourceAdapter: dart-source
      sourceCompatibilityId: dart-source-package-v1
      runnerCompatibilityId: fake-supervisor-v1
      executable: flutter
      runnerMode: cli
      args: [test, test]
      timeoutSeconds: 7
''',
      );
      addTearDown(() => root.delete(recursive: true));
      final supervisor = _FakeSupervisor(ProcessResult(1, 0, 'ok', ''));
      expect(
        await ZukeCli(
          processSupervisor: supervisor,
        ).run(['test', '--root', root.path]),
        0,
      );
      expect(supervisor.requests.single.runnerMode, ToolRunnerMode.cli);

      supervisor.requests.clear();
      expect(
        await ZukeCli(
          processSupervisor: supervisor,
        ).run(['test', '--root', root.path, '--runner-mode=directSnapshot']),
        0,
      );
      expect(
        supervisor.requests.single.runnerMode,
        ToolRunnerMode.directSnapshot,
      );
    });

    test('global directSnapshot leaves non-Flutter runners on auto', () async {
      final root = _workspace();
      addTearDown(() => root.delete(recursive: true));
      final supervisor = _FakeSupervisor(ProcessResult(1, 0, 'ok', ''));
      expect(
        await ZukeCli(
          processSupervisor: supervisor,
        ).run(['test', '--root', root.path, '--runner-mode=directSnapshot']),
        0,
      );
      expect(supervisor.requests.single.runnerMode, ToolRunnerMode.auto);
    });

    test('maps execution timeout to a stable tooling exit code', () async {
      final root = _workspace();
      addTearDown(() => root.delete(recursive: true));
      final supervisor = _FakeSupervisor.error(
        const SupervisedProcessException(
          kind: ProcessFailureKind.executionTimeout,
          diagnosticCode: 'ZUKE-TEST-TIMEOUT',
          message: 'runner timed out after 0:00:07.000000',
        ),
      );

      final exitCode = await ZukeCli(
        processSupervisor: supervisor,
      ).run(['test', '--root', root.path]);

      expect(exitCode, 3);
      expect(supervisor.requests, hasLength(1));
    });

    test('maps a termination failure to a stable tooling exit code', () async {
      final root = _workspace();
      addTearDown(() => root.delete(recursive: true));
      final supervisor = _FakeSupervisor.error(
        const SupervisedProcessException(
          kind: ProcessFailureKind.terminationFailure,
          diagnosticCode: 'ZUKE-PROCESS-TERMINATION-FAILED',
          message: 'runner remained alive after tree termination',
        ),
      );

      final exitCode = await ZukeCli(
        processSupervisor: supervisor,
      ).run(['test', '--root', root.path]);

      expect(exitCode, 3);
      expect(supervisor.requests, hasLength(1));
    });

    test('publishes evidence emitted by a configured runner', () async {
      final root = _workspace();
      addTearDown(() => root.delete(recursive: true));
      final config = File('${root.path}/zuke.yaml');
      config.writeAsStringSync(
        config.readAsStringSync().replaceFirst(
          'kind: setup',
          'kind: gherkin\n      evidenceTypes: [domain-unit]',
        ),
      );
      final supervisor = _EvidenceSupervisor();

      expect(
        await ZukeCli(
          processSupervisor: supervisor,
        ).run(['test', '--root', root.path]),
        0,
      );
      expect(
        Directory(
          '${root.path}/generated/evidence/records',
        ).listSync().whereType<File>(),
        hasLength(1),
      );
    });

    test('retains evidence from earlier sequential profiles', () async {
      final root = _workspace();
      addTearDown(() => root.delete(recursive: true));
      final config = File('${root.path}/zuke.yaml');
      config.writeAsStringSync(
        config.readAsStringSync().replaceFirst(
          'kind: setup',
          'kind: test\n      evidenceTypes: [domain-unit]',
        ),
      );
      final cli = ZukeCli(processSupervisor: _ProfileEvidenceSupervisor());

      expect(
        await cli.run([
          'test',
          '--root',
          root.path,
          '--profile',
          'pullRequest',
        ]),
        0,
      );
      expect(
        await cli.run(['test', '--root', root.path, '--profile', 'merge']),
        0,
      );

      final records = Directory('${root.path}/generated/evidence/records')
          .listSync()
          .whereType<File>()
          .map((file) {
            final json = jsonDecode(file.readAsStringSync());
            return json['profile'] as String;
          })
          .toSet();
      expect(records, containsAll({'pullRequest', 'merge'}));
    });

    test('fails closed for malformed configured runner declarations', () async {
      final cases = <({String runner, int exitCode})>[
        (
          runner: '''
    - id: skipped
      profiles: [release]
      executable: dart
''',
          exitCode: 2,
        ),
        (
          runner: '''
    - kind: test
      executable: dart
''',
          exitCode: 2,
        ),
        (
          runner: '''
    - id: invalid-kind
      kind: shell
      executable: dart
''',
          exitCode: 2,
        ),
        (
          runner: '''
    - id: missing-executable
      kind: test
''',
          exitCode: 2,
        ),
        (
          runner: '''
    - id: invalid-args
      kind: test
      executable: dart
      args: command string
''',
          exitCode: 2,
        ),
      ];

      for (final testCase in cases) {
        final root = _workspace(runners: testCase.runner);
        try {
          expect(
            await ZukeCli(
              processSupervisor: _FakeSupervisor(ProcessResult(1, 0, 'ok', '')),
            ).run(['test', '--root', root.path]),
            testCase.exitCode,
          );
        } finally {
          await root.delete(recursive: true);
        }
      }
    });

    test(
      'maps runner failures and missing declared evidence deterministically',
      () async {
        final failed = _workspace();
        addTearDown(() => failed.delete(recursive: true));
        expect(
          await ZukeCli(
            processSupervisor: _FakeSupervisor(
              ProcessResult(1, 9, '', 'failed'),
            ),
          ).run(['test', '--root', failed.path, '--format', 'json']),
          1,
        );

        final missing = _workspace(
          runners: '''
    - id: evidence-runner
      kind: test
      target: backend
      sourcePackage: fake-supervisor
      sourceAdapter: dart-source
      sourceCompatibilityId: dart-source-package-v1
      runnerCompatibilityId: fake-supervisor-v1
      executable: dart
      evidenceTypes: [domain-unit]
''',
        );
        addTearDown(() => missing.delete(recursive: true));
        expect(
          await ZukeCli(
            processSupervisor: _FakeSupervisor(ProcessResult(1, 0, 'ok', '')),
          ).run(['test', '--root', missing.path]),
          1,
        );
      },
    );

    test(
      'rejects malformed, mismatched, duplicate, and failed artifacts',
      () async {
        final invalidPayloads = <String>['[]', '{"schemaVersion":"unknown"}'];
        for (final payload in invalidPayloads) {
          final root = _workspace(
            runners: '''
    - id: artifact-runner
      kind: test
      target: backend
      sourcePackage: fake-supervisor
      sourceAdapter: dart-source
      sourceCompatibilityId: dart-source-package-v1
      runnerCompatibilityId: fake-supervisor-v1
      executable: dart
''',
          );
          try {
            expect(
              await ZukeCli(
                processSupervisor: _RawArtifactSupervisor(payload),
              ).run(['test', '--root', root.path]),
              1,
            );
          } finally {
            await root.delete(recursive: true);
          }
        }

        for (final artifactCase in [
          (artifacts: [_scenario(runnerId: 'other-runner')], expected: 1),
          (artifacts: [_scenario(profile: 'release')], expected: 1),
          (artifacts: [_scenario(), _scenario()], expected: 1),
          (artifacts: [_scenario(status: ScenarioStatus.failed)], expected: 1),
        ]) {
          final root = _workspace(
            runners: '''
    - id: artifact-runner
      kind: test
      target: backend
      sourcePackage: fake-supervisor
      sourceAdapter: dart-source
      sourceCompatibilityId: dart-source-package-v1
      runnerCompatibilityId: fake-supervisor-v1
      executable: dart
''',
          );
          try {
            expect(
              await ZukeCli(
                processSupervisor: _ResultSupervisor(artifactCase.artifacts),
              ).run(['test', '--root', root.path]),
              artifactCase.expected,
            );
          } finally {
            await root.delete(recursive: true);
          }
        }
      },
    );

    test('rejects target-level runner declarations', () async {
      final shell = _workspace(
        runners: '    []',
        targets:
            '  backend:\n'
            '    language: dart\n'
            '    framework: dart\n'
            '    packages:\n'
            '      - id: fake-supervisor\n'
            '        path: .\n'
            '        roots: [lib, test]\n'
            '    runner: dart test\n',
      );
      addTearDown(() => shell.delete(recursive: true));
      expect(
        await ZukeCli(
          processSupervisor: _FakeSupervisor(ProcessResult(1, 0, '', '')),
        ).run(['test', '--root', shell.path]),
        2,
      );

      final missingExecutable = _workspace(
        runners: '    []',
        targets:
            '  backend:\n'
            '    language: dart\n'
            '    framework: dart\n'
            '    packages:\n'
            '      - id: fake-supervisor\n'
            '        path: .\n'
            '        roots: [lib, test]\n'
            '    runner: {args: [test]}\n',
      );
      addTearDown(() => missingExecutable.delete(recursive: true));
      expect(
        await ZukeCli(
          processSupervisor: _FakeSupervisor(ProcessResult(1, 0, '', '')),
        ).run(['test', '--root', missingExecutable.path]),
        2,
      );

      final structured = _workspace(
        runners: '    []',
        targets:
            '  backend:\n'
            '    language: dart\n'
            '    framework: dart\n'
            '    packages:\n'
            '      - id: fake-supervisor\n'
            '        path: .\n'
            '        roots: [lib, test]\n'
            '    path: .\n'
            '    timeoutSeconds: 3\n'
            '    runner: {executable: flutter, runnerMode: cli, args: [test]}\n',
      );
      addTearDown(() => structured.delete(recursive: true));
      expect(
        await ZukeCli(
          processSupervisor: _FakeSupervisor(ProcessResult(1, 0, '', '')),
        ).run(['test', '--root', structured.path]),
        2,
      );

      final structuredWithoutTimeout = _workspace(
        runners: '    []',
        targets:
            '  backend:\n'
            '    language: dart\n'
            '    framework: dart\n'
            '    packages:\n'
            '      - id: fake-supervisor\n'
            '        path: .\n'
            '        roots: [lib, test]\n'
            '    runner: {executable: dart, args: [test]}\n',
      );
      addTearDown(() => structuredWithoutTimeout.delete(recursive: true));
      expect(
        await ZukeCli(
          processSupervisor: _FakeSupervisor(ProcessResult(1, 0, '', '')),
        ).run(['test', '--root', structuredWithoutTimeout.path]),
        2,
      );
    });

    test(
      'publishes a passing suite result through the same evidence boundary',
      () async {
        final root = _workspace(
          runners: '''
    - id: artifact-runner
      kind: test
      target: backend
      sourcePackage: fake-supervisor
      sourceAdapter: dart-source
      sourceCompatibilityId: dart-source-package-v1
      runnerCompatibilityId: fake-supervisor-v1
      executable: dart
      evidenceTypes: [suite]
''',
        );
        addTearDown(() => root.delete(recursive: true));
        const suite = SuiteResult(
          executionId: 'suite-execution',
          status: SuiteStatus.passed,
          requirementId: 'RULE-SUPERVISOR-001',
          evidenceType: 'suite',
          target: 'backend',
          candidateId: 'suite-candidate',
          profile: 'pullRequest',
          runnerId: 'artifact-runner',
          runnerCompatibilityId: 'artifact-runner-v1',
          resultDigest: 'sha256:suite',
          scenarioIds: [ScenarioId('SCN-SUPERVISOR-001')],
          controlIds: ['CTRL-SUPERVISOR-001'],
          attachmentDigests: ['sha256:attachment'],
        );

        expect(
          await ZukeCli(
            processSupervisor: const _ResultSupervisor([suite]),
          ).run(['test', '--root', root.path]),
          0,
        );
        expect(
          Directory(
            '${root.path}/generated/evidence/records',
          ).listSync().whereType<File>(),
          hasLength(1),
        );
      },
    );
  });
}

Directory _workspace({
  String runners = '''
    - id: unit-runner
      kind: setup
      target: backend
      sourcePackage: fake-supervisor
      sourceAdapter: dart-source
      sourceCompatibilityId: dart-source-package-v1
      runnerCompatibilityId: fake-supervisor-v1
      executable: dart
      args: [test, test]
      timeoutSeconds: 7
''',
  String targets = '''
  backend:
    language: dart
    framework: dart
    packages:
      - id: fake-supervisor
        path: .
        roots: [lib, test]
''',
}) {
  final root = Directory.systemTemp.createTempSync('zuke_supervisor_');
  File('${root.path}${Platform.pathSeparator}zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: fake-supervisor
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets:
$targets
execution:
  runners:
$runners
''');
  File('${root.path}${Platform.pathSeparator}pubspec.yaml').writeAsStringSync(
    '''
name: fake_supervisor
environment:
  sdk: '>=3.0.0 <4.0.0'
''',
  );
  final features = Directory(
    '${root.path}${Platform.pathSeparator}specs${Platform.pathSeparator}features',
  )..createSync(recursive: true);
  File(
    '${features.path}${Platform.pathSeparator}unit.feature',
  ).writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-SUPERVISOR-001
# spec-end

Feature: Supervisor
  Scenario: Configured runner
    Given a configured runner
''');
  return root;
}

final class _FakeSupervisor implements ProcessSupervisor {
  _FakeSupervisor(this.result) : error = null;
  _FakeSupervisor.error(this.error) : result = null;

  final ProcessResult? result;
  final SupervisedProcessException? error;
  final List<ProcessRunRequest> requests = [];

  @override
  Future<ProcessResult> run(ProcessRunRequest request) async {
    requests.add(request);
    if (error != null) throw error!;
    return result!;
  }
}

final class _EvidenceSupervisor implements ProcessSupervisor {
  @override
  Future<ProcessResult> run(ProcessRunRequest request) async {
    final directory = request.environment['ZUKE_RESULT_DIR']!;
    const ExecutionResultWriter(identity: _runnerIdentity).writeScenario(
      directory,
      const ScenarioResult(
        executionId: 'evidence-run',
        status: ScenarioStatus.passed,
        requirementId: 'RULE-SUPERVISOR-001',
        evidenceType: 'domain-unit',
        target: 'backend',
        candidateId: 'SCN-SUPERVISOR-001',
        profile: 'pullRequest',
        runnerId: 'unit-runner',
        runnerCompatibilityId: 'unit-runner-v1',
        scenarioIds: [ScenarioId('SCN-SUPERVISOR-001')],
      ),
    );
    return ProcessResult(1, 0, 'ok', '');
  }
}

final class _ProfileEvidenceSupervisor implements ProcessSupervisor {
  @override
  Future<ProcessResult> run(ProcessRunRequest request) async {
    final profile = request.environment['ZUKE_PROFILE']!;
    const identity = ExecutionSourceIdentity(
      sourcePackage: 'fake-supervisor',
      sourceAdapter: 'dart-source',
      sourceCompatibilityId: 'dart-source-package-v1',
    );
    ExecutionResultWriter(identity: identity).writeScenario(
      request.environment['ZUKE_RESULT_DIR']!,
      ScenarioResult(
        executionId: 'evidence-$profile',
        status: ScenarioStatus.passed,
        requirementId: 'RULE-SUPERVISOR-001',
        evidenceType: 'domain-unit',
        target: 'backend',
        candidateId: 'SCN-SUPERVISOR-001',
        profile: profile,
        runnerId: 'unit-runner',
        runnerCompatibilityId: 'unit-runner-v1',
        scenarioIds: const [ScenarioId('SCN-SUPERVISOR-001')],
      ),
    );
    return ProcessResult(1, 0, 'ok', '');
  }
}

final class _RawArtifactSupervisor implements ProcessSupervisor {
  final String payload;

  const _RawArtifactSupervisor(this.payload);

  @override
  Future<ProcessResult> run(ProcessRunRequest request) async {
    File(
      '${request.environment['ZUKE_RESULT_DIR']}/artifact.json',
    ).writeAsStringSync(payload);
    return ProcessResult(1, 0, 'ok', '');
  }
}

final class _ResultSupervisor implements ProcessSupervisor {
  final List<Object> artifacts;

  const _ResultSupervisor(this.artifacts);

  @override
  Future<ProcessResult> run(ProcessRunRequest request) async {
    final directory = request.environment['ZUKE_RESULT_DIR']!;
    for (var index = 0; index < artifacts.length; index++) {
      final json = switch (artifacts[index]) {
        ScenarioResult value =>
          value.withSourceIdentity(_runnerIdentity).toJson(),
        SuiteResult value => value.withSourceIdentity(_runnerIdentity).toJson(),
        _ => throw StateError('Unsupported test artifact'),
      };
      File(
        '$directory/artifact-$index.json',
      ).writeAsStringSync(jsonEncode(json));
    }
    return ProcessResult(1, 0, 'ok', '');
  }
}

ScenarioResult _scenario({
  ScenarioStatus status = ScenarioStatus.passed,
  String profile = 'pullRequest',
  String runnerId = 'artifact-runner',
}) => ScenarioResult(
  executionId: 'execution',
  status: status,
  requirementId: 'RULE-SUPERVISOR-001',
  evidenceType: 'domain-unit',
  target: 'backend',
  candidateId: 'SCN-SUPERVISOR-001',
  profile: profile,
  runnerId: runnerId,
  runnerCompatibilityId: 'artifact-runner-v1',
  scenarioIds: const [ScenarioId('SCN-SUPERVISOR-001')],
);
