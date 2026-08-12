import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:zuke_cli/src/trust_bundle.dart';
import 'cli_test_helper.dart';

void main() {
  group('Gate command trust eligibility (ZUKE-TRUST-001)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory(
        'test/temp_trust_${DateTime.now().millisecondsSinceEpoch}',
      )..createSync(recursive: true);
    });

    test('configured trust bundle stays within the workspace', () {
      expect(
        () => configuredTrustBundle(
          tempDir.path,
          configuredPath: '../trust.json',
        ),
        throwsFormatException,
      );
      expect(
        () => configuredTrustBundle(
          tempDir.path,
          configuredPath: Platform.isWindows ? r'C:\trust.json' : '/trust.json',
        ),
        throwsFormatException,
      );
    });

    test('reads the trust bundle path from schema-v3 configuration', () {
      File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
targets: {}
trust:
  bundle: trust/custom-ed25519.json
''');

      final bundle = configuredTrustBundle(tempDir.path);

      expect(
        bundle.path.replaceAll('\\', '/'),
        endsWith('/trust/custom-ed25519.json'),
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    Future<void> prepareWorkspace() async {
      final runnerExec = Platform.isWindows ? 'cmd' : 'true';
      final runnerArgs = Platform.isWindows ? ['/c', 'exit 0'] : <String>[];
      final yamlArgs = runnerArgs.isEmpty
          ? ''
          : '\n${runnerArgs.map((a) => '        - $a').join('\n')}';

      File('${tempDir.path}/zuke.yaml').writeAsStringSync('''schemaVersion: 3
specifications:
  features: [specs/features/**/*.feature]
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: backend
        path: .
        roots: [lib]
lock:
  directory: assurance/locks
  profiles: [pullRequest, merge, release, nightly]
execution:
  runners:
    - id: trivial
      target: backend
      sourcePackage: backend
      sourceAdapter: dart-test
      sourceCompatibilityId: dart-test-v2
      executable: '$runnerExec'
      args:$yamlArgs
      timeoutSeconds: 30
''');

      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: trust_gate_fixture
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  zuke_core:
    path: '${Directory.current.path.replaceAll('\\', '/')}/vendor-sdk/zuke_core'
  zuke:
    path: '${Directory.current.path.replaceAll('\\', '/')}/vendor-sdk/zuke'
  zuke_annotations:
    path: '${Directory.current.path.replaceAll('\\', '/')}/vendor-sdk/zuke_annotations'
  zuke_frontend:
    path: '${Directory.current.path.replaceAll('\\', '/')}/vendor-sdk/zuke_frontend'
dependency_overrides:
  zuke_core:
    path: '${Directory.current.path.replaceAll('\\', '/')}/vendor-sdk/zuke_core'
  zuke_annotations:
    path: '${Directory.current.path.replaceAll('\\', '/')}/vendor-sdk/zuke_annotations'
  zuke_frontend:
    path: '${Directory.current.path.replaceAll('\\', '/')}/vendor-sdk/zuke_frontend'
''');
      final pubGet = await Process.run(
        Platform.resolvedExecutable,
        ['pub', 'get', '--offline'],
        workingDirectory: tempDir.path,
      );
      if (pubGet.exitCode != 0) {
        throw Exception('pub get failed: ${pubGet.stdout}\n${pubGet.stderr}');
      }
      Directory('${tempDir.path}/lib').createSync(recursive: true);

      final featureDir = Directory('${tempDir.path}/specs/features')
        ..createSync(recursive: true);
      File('${featureDir.path}/test.feature').writeAsStringSync('''# spec-begin
# schemaVersion: 1
# id: FEAT-TEST-001
# spec-end

@FEAT-TEST-001
Feature: Dummy
  # rule-spec-begin
  # id: RULE-TEST-001
  # requiredEvidence: []
  # rule-spec-end
  @RULE-TEST-001
  Rule: Dummy rule
    @SCN-TEST-001
    Scenario: Dummy
      Given a step
''');

      final genResult = await runInProcessCli([
        'generate',
        '--root',
        tempDir.path,
      ]);
      if (genResult.exitCode != 0) {
        throw Exception('generate failed: ${genResult.stderr}');
      }
      final lockResult = await runInProcessCli([
        'lock',
        '--root',
        tempDir.path,
      ]);
      if (lockResult.exitCode != 0) {
        throw Exception('lock failed: ${lockResult.stderr}');
      }
    }

    test(
      'gate with --profile release fails with ZUKE-TRUST-001 when no trust dir exists',
      () async {
        await prepareWorkspace();

        final trustDir = Directory('${tempDir.path}/assurance-history/trust');
        if (trustDir.existsSync()) {
          trustDir.deleteSync(recursive: true);
        }

        final result = await runInProcessCli([
          'gate',
          '--root',
          tempDir.path,
          '--profile',
          'release',
        ]);

        expect(result.stderr, contains('ZUKE-TRUST-001'));
        expect(result.exitCode, isNot(0));
      },
    );

    test(
      'gate with --profile release fails with ZUKE-TRUST-001 when trust has no active keys',
      () async {
        await prepareWorkspace();

        final trustDir = Directory('${tempDir.path}/assurance-history/trust')
          ..createSync(recursive: true);
        File('${trustDir.path}/ed25519.json').writeAsStringSync(
          jsonEncode({'kind': 'zuke.ed25519-trust', 'keys': []}),
        );

        final result = await runInProcessCli([
          'gate',
          '--root',
          tempDir.path,
          '--profile',
          'release',
        ]);

        expect(result.stderr, contains('ZUKE-TRUST-001'));
        expect(result.exitCode, isNot(0));
      },
    );

    test(
      'gate without --profile release passes even without trust dir',
      () async {
        await prepareWorkspace();

        final trustDir = Directory('${tempDir.path}/assurance-history/trust');
        if (trustDir.existsSync()) {
          trustDir.deleteSync(recursive: true);
        }

        final result = await runInProcessCli(['gate', '--root', tempDir.path]);
        expect(result.exitCode, equals(0));
      },
    );

    test('gate --format json emits one machine-readable envelope', () async {
      await prepareWorkspace();

      final result = await runInProcessCli([
        'gate',
        '--root',
        tempDir.path,
        '--format',
        'json',
      ]);

      expect(result.exitCode, equals(0));
      final decoded = jsonDecode(result.stdout) as Map<String, dynamic>;
      expect(decoded['kind'], equals('zuke.command-result'));
      expect(decoded['command'], equals('gate'));
      expect(decoded['stage'], equals('gate'));
      expect(decoded['status'], equals('passed'));
      expect(decoded['exitCode'], equals(0));
      expect(decoded['eligible'], isTrue);
      expect(decoded['diagnostics'], isA<List>());
    });
  });
}
