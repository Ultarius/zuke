import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:zuke_cli/zuke_cli.dart';
import 'package:zuke_cli/src/manifest_command.dart';
import 'package:zuke_cli/src/dart_extractor.dart';
import 'helpers/eligible_workspace.dart';
import 'cli_test_helper.dart';

void main() {
  group('ManifestCommand & DartExtractor', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory(
        'test/temp_fixture_${DateTime.now().millisecondsSinceEpoch}',
      )..createSync(recursive: true);
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: zuke_extractor_fixture
environment:
  sdk: '>=3.10.0 <3.11.0'
''');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test(
      'DartExtractor computes relative path input digests deterministically',
      () async {
        final srcDir = Directory('${tempDir.path}/src')
          ..createSync(recursive: true);
        final file = File('${srcDir.path}/app.dart');
        file.writeAsStringSync('const a = 1;');

        final output1 = await DartExtractor().extract(
          tempDir.path,
          roots: ['src'],
        );
        expect(output1.inputDigest, isNotEmpty);

        // Extracting from another root path with identical relative file structure produces identical digest
        final tempDir2 = Directory.systemTemp.createTempSync('zuke_test2_');
        try {
          File('${tempDir2.path}/pubspec.yaml').writeAsStringSync('''
name: zuke_extractor_fixture
environment:
  sdk: '>=3.10.0 <3.11.0'
''');
          final srcDir2 = Directory('${tempDir2.path}/src')
            ..createSync(recursive: true);
          final file2 = File('${srcDir2.path}/app.dart');
          file2.writeAsStringSync('const a = 1;');

          final output2 = await DartExtractor().extract(
            tempDir2.path,
            roots: ['src'],
          );
          expect(output2.inputDigest, equals(output1.inputDigest));
        } finally {
          if (tempDir2.existsSync()) tempDir2.deleteSync(recursive: true);
        }
      },
    );

    test('handles spread in list literal annotations', () async {
      final file = File('${tempDir.path}/app.dart');
      file.writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_http_runtime/zuke_http_runtime.dart';

const _baseIds = ['RULE-CALC-ADDITION'];

@ImplementsRequirement([..._baseIds, 'RULE-CALC-SUBTRACTION'])
class MyController implements ZukeController {
  @override String get id => 'my-controller';
  @override Future<ZukeHttpResponse> handle(ZukeHttpRequest r) async => ZukeHttpResponse(200);
}
''');

      final output = await DartExtractor().extract(tempDir.path, roots: ['.']);
      final requirementIds = output.symbols
          .where((s) => s.kind == 'requirementBoundary')
          .expand((s) => s.requirementIds)
          .toSet();
      expect(requirementIds, contains('RULE-CALC-ADDITION'));
      expect(requirementIds, contains('RULE-CALC-SUBTRACTION'));
    });

    test('detects mutations on registration lists', () async {
      final file = File('${tempDir.path}/app.dart');
      file.writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_http_runtime/zuke_http_runtime.dart';

@ImplementsRequirement(['RULE-CALC-ADDITION'])
class RealController implements ZukeController {
  @override String get id => 'real';
  @override Future<ZukeHttpResponse> handle(ZukeHttpRequest r) async => ZukeHttpResponse(200);
}

class PublicHttpEgress implements ZukePublicEgress {
  @override String get id => 'egress';
  @override Future<void> write(Object r) async {}
}

class MutatedApp {
  late final ZukeHttpApplication registration;
  MutatedApp() {
    final temp = <ZukeRouteRegistration>[
      ZukeRouteRegistration(
        endpointId: 'x',
        method: 'y',
        path: 'z',
        middleware: [],
        controller: RealController(),
        publicEgress: PublicHttpEgress(),
      ),
    ];
    temp.add(
      ZukeRouteRegistration(
        endpointId: 'x2',
        method: 'y2',
        path: 'z2',
        middleware: [],
        controller: RealController(),
        publicEgress: PublicHttpEgress(),
      ),
    );
    registration = ZukeHttpApplication(routes: temp);
  }
}
''');

      final output = await DartExtractor().extract(tempDir.path, roots: ['.']);
      expect(
        output.diagnostics.any(
          (d) =>
              d.message.contains('mutation') ||
              d.message.contains('list literal'),
        ),
        isTrue,
      );
    });

    test(
      'DartExtractor detects unresolved registrations and list mutations',
      () async {
        final file = File('${tempDir.path}/app.dart');
        file.writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_http_runtime/zuke_http_runtime.dart';

@ImplementsRequirement(['RULE-CALC-ADDITION'])
class RealController implements ZukeController {
  @override String get id => 'real';
  @override Future<ZukeHttpResponse> handle(ZukeHttpRequest r) async => ZukeHttpResponse(200);
}

class PublicHttpEgress implements ZukePublicEgress {
  @override String get id => 'egress';
  @override Future<void> write(Object r) async {}
}

class MyUnresolvedApp {
  late final ZukeHttpApplication registration;
  MyUnresolvedApp() {
    registration = ZukeHttpApplication(
      routes: [
        if (true) ZukeRouteRegistration(
          endpointId: 'x',
          method: 'y',
          path: 'z',
          middleware: [],
          controller: RealController(),
          publicEgress: PublicHttpEgress(),
        )
      ]
    );
  }
}
''');

        final output = await DartExtractor().extract(
          tempDir.path,
          roots: ['.'],
        );
        expect(
          output.diagnostics.any(
            (d) => d.message.contains('mutation or dynamic element'),
          ),
          isTrue,
        );
      },
    );

    test('DartExtractor extracts conditional expressions', () async {
      final file = File('${tempDir.path}/app.dart');
      file.writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_http_runtime/zuke_http_runtime.dart';

@ImplementsRequirement(['RULE-CALC-ADDITION'])
class RealController implements ZukeController {
  @override String get id => 'real';
  @override Future<ZukeHttpResponse> handle(ZukeHttpRequest r) async => ZukeHttpResponse(200);
}

@ImplementsRequirement(['RULE-CALC-ADDITION'])
class MockController implements ZukeController {
  @override String get id => 'mock';
  @override Future<ZukeHttpResponse> handle(ZukeHttpRequest r) async => ZukeHttpResponse(200);
}

class PublicHttpEgress implements ZukePublicEgress {
  @override String get id => 'egress';
  @override Future<void> write(Object r) async {}
}

class MyApp {
  late final ZukeHttpApplication registration;
  MyApp(bool useMock) {
    registration = ZukeHttpApplication(
      routes: [
        ZukeRouteRegistration(
          endpointId: 'my.endpoint',
          method: 'POST',
          path: '/test',
          middleware: [],
          controller: useMock ? MockController() : RealController(),
          publicEgress: PublicHttpEgress(),
        )
      ]
    );
  }
}
''');

      final output = await DartExtractor().extract(tempDir.path, roots: ['.']);
      final nodeIds = output.graph?.nodes.map((n) => n.id).toList() ?? [];
      expect(nodeIds, contains('implementation:MockController'));
      expect(nodeIds, contains('implementation:RealController'));
    });

    test(
      'ManifestCommand enforces active signer enrollment and fails if empty',
      () async {
        File('${tempDir.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: manifest-test
  root: .
specifications:
  features: []
targets: {}
''');
        final emptyTrustDir = Directory(
          '${tempDir.path}/assurance-history/trust',
        )..createSync(recursive: true);
        final emptyTrustFile = File('${emptyTrustDir.path}/ed25519.json');
        emptyTrustFile.writeAsStringSync(
          jsonEncode({'kind': 'zuke.ed25519-trust', 'keys': []}),
        );

        Process.runSync('git', ['init'], workingDirectory: tempDir.path);
        Process.runSync('git', [
          'config',
          'user.name',
          'test',
        ], workingDirectory: tempDir.path);
        Process.runSync('git', [
          'config',
          'user.email',
          'test@test.com',
        ], workingDirectory: tempDir.path);
        Process.runSync('git', ['add', '.'], workingDirectory: tempDir.path);
        Process.runSync('git', [
          'commit',
          '-m',
          'initial commit',
        ], workingDirectory: tempDir.path);

        expect(
          () => ManifestCommand.create(
            root: tempDir.path,
            signerId: 'non-existent',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('No signers enrolled'),
            ),
          ),
        );
      },
    );

    test('lock build includes all required hash inputs', () async {
      await createEligibleWorkspace(tempDir);

      await runInProcessCli(['generate', '--root', tempDir.path]);
      final result = await runInProcessCli(['lock', '--root', tempDir.path]);
      expect(result.exitCode, equals(0));

      final lockPath = '${tempDir.path}/assurance/locks/pullRequest.lock.json';
      final lockFile = File(lockPath);
      expect(lockFile.existsSync(), isTrue);

      final lock = jsonDecode(lockFile.readAsStringSync()) as Map;
      expect(lock.containsKey('policyHash'), isTrue);
      expect(lock['policyHash'], startsWith('sha256:'));
      expect(lock.containsKey('evidenceRequirementsHash'), isTrue);
      expect(lock['evidenceRequirementsHash'], startsWith('sha256:'));
      expect(lock.containsKey('specificationDigest'), isTrue);
      expect(lock['specificationDigest'], startsWith('sha256:'));
      expect(lock.containsKey('generatedManifestDigest'), isTrue);
      expect(lock['generatedManifestDigest'], startsWith('sha256:'));
      expect(lock.containsKey('features'), isTrue);
      final features = lock['features'] as Map;
      expect(
        features.values.every((v) => (v as Map).containsKey('sourceHash')),
        isTrue,
      );
      expect(lock.containsKey('fragments'), isTrue);
      expect(lock['fragments'], isA<List>());
      expect(lock.containsKey('controls'), isTrue);
      final controls = lock['controls'] as Map;
      expect(
        controls.keys.any((k) => k.contains('CTRL-GATEWAY-RATE-LIMIT')),
        isTrue,
      );
      expect(lock.containsKey('requirements'), isTrue);
      expect(lock['requirements'], isA<List>());
    });

    test('policy hashing preserves authored nested metadata', () async {
      await createEligibleWorkspace(tempDir);
      final control = File('${tempDir.path}/specs/controls/gateway.yaml');
      control.writeAsStringSync('''controls:
  - id: CTRL-GATEWAY-RATE-LIMIT
    title: External gateway rate-limit
    target: backend
    coverageSemantics: external-attestation
    metadata:
      _file: authored-one
''');
      await runInProcessCli(['generate', '--root', tempDir.path]);
      var result = await runInProcessCli(['lock', '--root', tempDir.path]);
      expect(result.exitCode, 0, reason: result.stderr);
      final first =
          jsonDecode(
                File(
                  '${tempDir.path}/assurance/locks/pullRequest.lock.json',
                ).readAsStringSync(),
              )
              as Map;

      control.writeAsStringSync(
        control.readAsStringSync().replaceFirst('authored-one', 'authored-two'),
      );
      result = await runInProcessCli(['lock', '--root', tempDir.path]);
      expect(result.exitCode, 0, reason: result.stderr);
      final second =
          jsonDecode(
                File(
                  '${tempDir.path}/assurance/locks/pullRequest.lock.json',
                ).readAsStringSync(),
              )
              as Map;
      expect(second['policyHash'], isNot(first['policyHash']));
    });

    test('policy hashing rejects nested non-string keys', () async {
      await createEligibleWorkspace(tempDir);
      File('${tempDir.path}/specs/controls/gateway.yaml').writeAsStringSync(
        '''controls:
  - id: CTRL-GATEWAY-RATE-LIMIT
    title: External gateway rate-limit
    target: backend
    coverageSemantics: external-attestation
    metadata:
      1: numeric-key
''',
      );
      await runInProcessCli(['generate', '--root', tempDir.path]);
      final result = await runInProcessCli(['lock', '--root', tempDir.path]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('keys must be strings'));
    });

    test('lock --check fails when lock is stale', () async {
      await createEligibleWorkspace(tempDir);

      await runInProcessCli(['generate', '--root', tempDir.path]);
      var result = await runInProcessCli(['lock', '--root', tempDir.path]);
      expect(result.exitCode, equals(0));

      File('${tempDir.path}/specs/features/gateway.feature').writeAsStringSync(
        '''# spec-begin
# schemaVersion: 1
# id: FEAT-GATEWAY-001
# spec-end

@FEAT-GATEWAY-001
Feature: Gateway
  # rule-spec-begin
  # id: RULE-GATEWAY-RATE-LIMIT
  # requiredEvidence: [domain-unit]
  # requires:
  #   - kind: control
  #     id: CTRL-GATEWAY-RATE-LIMIT
  #     target: backend
  #     variant: default
  # rule-spec-end
  @RULE-GATEWAY-RATE-LIMIT
  Rule: Gateway rate-limit
    Scenario: modified scenario
      Given a step
''',
      );

      result = await runInProcessCli([
        'lock',
        '--root',
        tempDir.path,
        '--check',
      ]);
      expect(result.exitCode, isNot(equals(0)));
    });

    test('lock --check fails when the lock file is missing', () async {
      await createEligibleWorkspace(tempDir);

      final generateResult = await runInProcessCli([
        'generate',
        '--root',
        tempDir.path,
      ]);
      expect(generateResult.exitCode, equals(0));

      final result = await runInProcessCli([
        'lock',
        '--root',
        tempDir.path,
        '--check',
      ]);
      expect(result.exitCode, isNot(equals(0)));
      expect(result.stderr, contains('Specification lock is stale or missing'));
      expect(
        File(
          '${tempDir.path}/assurance/locks/pullRequest.lock.json',
        ).existsSync(),
        isFalse,
      );
    });

    test('lock re-generated from fresh evidence passes --check', () async {
      await createEligibleWorkspace(tempDir);

      var result = await runInProcessCli(['generate', '--root', tempDir.path]);
      expect(result.exitCode, equals(0));

      result = await runInProcessCli(['lock', '--root', tempDir.path]);
      expect(result.exitCode, equals(0));

      result = await runInProcessCli([
        'lock',
        '--root',
        tempDir.path,
        '--check',
      ]);
      expect(result.exitCode, equals(0));
    });

    test('ignored tool outputs do not stale the lock', () async {
      await createEligibleWorkspace(tempDir);

      await runInProcessCli(['generate', '--root', tempDir.path]);
      var result = await runInProcessCli(['lock', '--root', tempDir.path]);
      expect(result.exitCode, equals(0));

      for (final path in [
        '.gradle/executionHistory.bin',
        '.zuke/evidence/records/result.json',
        'windows/flutter/ephemeral/flutter_windows.dll.pdb',
      ]) {
        final file = File('${tempDir.path}/$path');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('transient output');
      }

      result = await runInProcessCli([
        'lock',
        '--root',
        tempDir.path,
        '--check',
      ]);
      expect(result.exitCode, equals(0));
    });

    test('manifest creation rejects a committed stale lock', () async {
      await createEligibleWorkspace(tempDir);

      await runInProcessCli(['generate', '--root', tempDir.path]);
      final lockResult = await runInProcessCli([
        'lock',
        '--root',
        tempDir.path,
        '--profile',
        'release',
      ]);
      expect(lockResult.exitCode, equals(0));

      Process.runSync('git', ['init'], workingDirectory: tempDir.path);
      Process.runSync('git', [
        'config',
        'user.name',
        'test',
      ], workingDirectory: tempDir.path);
      Process.runSync('git', [
        'config',
        'user.email',
        'test@test.com',
      ], workingDirectory: tempDir.path);
      Process.runSync('git', ['add', '.'], workingDirectory: tempDir.path);
      Process.runSync('git', [
        'commit',
        '-m',
        'initial lock',
      ], workingDirectory: tempDir.path);

      final feature = File('${tempDir.path}/specs/features/gateway.feature');
      feature.writeAsStringSync(
        feature.readAsStringSync().replaceFirst(
          'Scenario: trivial',
          'Scenario: committed source change',
        ),
      );
      Process.runSync('git', ['add', '.'], workingDirectory: tempDir.path);
      Process.runSync('git', [
        'commit',
        '-m',
        'change source without lock',
      ], workingDirectory: tempDir.path);
      await expectLater(
        ManifestCommand.create(root: tempDir.path, signerId: 'release-signer'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('current lock'),
          ),
        ),
      );
    });

    test(
      'in-process CLI routes the release lifecycle and fail-closed branches',
      () async {
        await createEligibleWorkspace(tempDir);
        final cli = ZukeCli(version: 'test-version');
        final empty = Directory('${tempDir.path}/empty')..createSync();

        expect(await cli.run(const []), 0);
        expect(await cli.run(const ['--help']), 0);
        expect(await cli.run(const ['--version']), 0);
        expect(await cli.run(['doctor', '--root', empty.path]), 1);
        expect(
          await cli.run([
            'init',
            '--root',
            empty.path,
            '--enable-dart-build-hooks',
          ]),
          2,
        );
        expect(await cli.run(['init', '--root', empty.path, '--dry-run']), 0);
        expect(await cli.run(['init', '--root', empty.path]), 0);
        expect(await cli.run(['init', '--root', empty.path]), 1);

        expect(await cli.run(['doctor', '--root', tempDir.path]), 0);
        expect(await cli.run(['generate', '--root', tempDir.path]), 0);
        expect(await cli.run(['validate', '--root', tempDir.path]), 0);
        expect(await cli.run(['lock', '--root', tempDir.path]), 0);
        expect(await cli.run(['lock', '--root', tempDir.path, '--check']), 0);
        expect(
          await cli.run([
            'trace',
            'RULE-GATEWAY-RATE-LIMIT',
            '--root',
            tempDir.path,
          ]),
          1,
        );
        expect(await cli.run(['trace', 'UNKNOWN', '--root', tempDir.path]), 1);
        expect(await cli.run(['extract', 'dart', '--root', tempDir.path]), 1);
        final fragment = File('${tempDir.path}/fragment.json');
        expect(
          await cli.run([
            'extract',
            'dart',
            '--root',
            tempDir.path,
            '--package',
            '.',
            '--emit',
            fragment.path,
          ]),
          0,
        );
        expect(fragment.existsSync(), isTrue);
        expect(await cli.run(const ['extract']), 1);
        expect(await cli.run(const ['manifest']), 1);
        expect(
          await cli.run(['manifest', 'verify', '--root', tempDir.path]),
          0,
        );
        expect(
          await cli.run([
            'manifest',
            'verify',
            '--root',
            tempDir.path,
            '--require-history',
          ]),
          1,
        );
        final exported = File('${tempDir.path}/exported-history.json');
        expect(
          await cli.run([
            'manifest',
            'export',
            '--root',
            tempDir.path,
            '--output',
            exported.path,
          ]),
          0,
        );
        expect(
          jsonDecode(exported.readAsStringSync()),
          containsPair('chain', isEmpty),
        );
        expect(await cli.run(const ['attestation']), 1);
        expect(
          await cli.run([
            'attestation',
            'create',
            '--root',
            tempDir.path,
            '--provider-id',
            'external-gateway',
            '--evidence',
            'invalid',
            '--reference',
            'https://gateway.example',
            '--signer-id',
            'attestation-signer',
            '--issued-at',
            'invalid',
            '--expires-at',
            'invalid',
          ]),
          2,
        );
        expect(await cli.run(const ['gateway']), 1);
        expect(await cli.run(const ['adopt']), 1);
        expect(
          await cli.run(['adopt', 'package', '.', '--root', tempDir.path]),
          2,
        );
        expect(
          await cli.run([
            'adopt',
            'package',
            '../escape',
            '--root',
            tempDir.path,
            '--enable-build-hook',
          ]),
          2,
        );
        expect(
          await cli.run([
            'affected',
            '--root',
            tempDir.path,
            '--changed-since',
            'unknown-ref',
          ]),
          0,
        );
        expect(await cli.run(['affected', '--root', tempDir.path]), 0);
        expect(await cli.run(['test', '--root', tempDir.path]), 0);
        expect(await cli.run(['lock', '--root', tempDir.path]), 0);
        expect(await cli.run(['gate', '--root', tempDir.path]), 0);
      },
    );
  });
}
