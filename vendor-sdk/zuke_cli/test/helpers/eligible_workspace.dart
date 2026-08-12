import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:zuke_core/zuke_core.dart';

Future<Directory> createEligibleWorkspace(
  Directory tempDir, {
  DateTime? attestationIssuedAt,
  DateTime? attestationExpiresAt,
}) async {
  if (!tempDir.existsSync()) {
    tempDir.createSync(recursive: true);
  }

  // 1. Key generation for attestation & release signers
  final algo = Ed25519();
  final attestationKeyPair = await algo.newKeyPair();
  final attestationPublicKey = await attestationKeyPair.extractPublicKey();
  final attestationPubBytes = attestationPublicKey.bytes;
  final attestationPubB64 = base64Encode(attestationPubBytes);
  final attestationFingerprint =
      'sha256:${sha256.convert(attestationPubBytes)}';

  final releaseKeyPair = await algo.newKeyPair();
  final releasePublicKey = await releaseKeyPair.extractPublicKey();
  final releasePubBytes = releasePublicKey.bytes;
  final releasePubB64 = base64Encode(releasePubBytes);
  final releaseFingerprint = 'sha256:${sha256.convert(releasePubBytes)}';

  // 2. Trust bundle
  final trustDir = Directory('${tempDir.path}/assurance-history/trust')
    ..createSync(recursive: true);
  File('${trustDir.path}/ed25519.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'kind': 'zuke.ed25519-trust',
      'keys': [
        {
          'signerId': 'attestation-signer',
          'keyId': 'default',
          'algorithm': 'Ed25519',
          'publicKey': attestationPubB64,
          'fingerprint': attestationFingerprint,
          'usages': ['attestation'],
          'status': 'active',
        },
        {
          'signerId': 'release-signer',
          'keyId': 'default',
          'algorithm': 'Ed25519',
          'publicKey': releasePubB64,
          'fingerprint': releaseFingerprint,
          'usages': ['release'],
          'status': 'active',
        },
      ],
    }),
  );

  // 3. zuke.yaml
  final runnerExec = Platform.isWindows ? 'cmd' : 'true';
  final runnerArgs = Platform.isWindows ? ['/c', 'exit 0'] : <String>[];
  final yamlArgs = runnerArgs.isEmpty
      ? ''
      : '\n${runnerArgs.map((a) => '        - $a').join('\n')}';

  File('${tempDir.path}/zuke.yaml').writeAsStringSync('''schemaVersion: 3
workspace:
  name: test-workspace
  root: .
specifications:
  features: [specs/features/**/*.feature]
  epics: [specs/epics/**/*.yaml]
  controls: [specs/controls/**/*.yaml]
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
policies:
  project: specs/policies/project.yaml
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
  final packageConfig = _workspacePackageConfig();
  final repositoryRoot = packageConfig.parent.parent.path.replaceAll('\\', '/');
  File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_workspace
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  zuke_core:
    path: '$repositoryRoot/vendor-sdk/zuke_core'
  zuke_annotations:
    path: '$repositoryRoot/vendor-sdk/zuke_annotations'
  zuke_http_runtime:
    path: '$repositoryRoot/vendor-sdk/zuke_http_runtime'
dependency_overrides:
  zuke_core:
    path: '$repositoryRoot/vendor-sdk/zuke_core'
''');
  final pubGet = await Process.run(
    Platform.resolvedExecutable,
    ['--suppress-analytics', 'pub', 'get', '--offline'],
    workingDirectory: tempDir.path,
  );
  if (pubGet.exitCode != 0) {
    throw StateError('Fixture pub get failed: ${pubGet.stdout}\n${pubGet.stderr}');
  }

  // 4. Feature file
  final featureDir = Directory('${tempDir.path}/specs/features')
    ..createSync(recursive: true);
  File('${featureDir.path}/gateway.feature').writeAsStringSync('''# spec-begin
# schemaVersion: 1
# id: FEAT-GATEWAY-001
# spec-end

@FEAT-GATEWAY-001
Feature: Gateway
  # rule-spec-begin
  # id: RULE-GATEWAY-RATE-LIMIT
  # requiredEvidence: []
  # rule-spec-end
  @RULE-GATEWAY-RATE-LIMIT
  Rule: Gateway rate-limit
    @SCN-GATEWAY-001
    Scenario: trivial
      Given a step
''');

  // 5. Control YAML
  final controlDir = Directory('${tempDir.path}/specs/controls')
    ..createSync(recursive: true);
  File('${controlDir.path}/gateway.yaml').writeAsStringSync('''controls:
  - id: CTRL-GATEWAY-RATE-LIMIT
    title: External gateway rate-limit
    target: backend
    coverageSemantics: external-attestation
''');

  // 6. Policy YAML
  final scopeMap = {'endpoint': '/add', 'method': 'POST'};
  final scopeHash =
      'sha256:${sha256.convert(utf8.encode(canonicalJson(scopeMap)))}';
  const evidenceDigest =
      'sha256:1111111111111111111111111111111111111111111111111111111111111111';
  final now = DateTime.now().toUtc();
  final issuedAt =
      (attestationIssuedAt ?? now.subtract(const Duration(days: 1)))
          .toIso8601String();
  final expiresAt = (attestationExpiresAt ?? now.add(const Duration(days: 30)))
      .toIso8601String();

  final policyDir = Directory('${tempDir.path}/specs/policies')
    ..createSync(recursive: true);
  File('${policyDir.path}/project.yaml').writeAsStringSync(
    '''preset: secure-product-v1
providers:
  - id: external-gateway
    provides: CTRL-GATEWAY-RATE-LIMIT
    assurance: attested
    target: backend
    variant: default
    kind: rate-limit
    layer: edge
    owner: platform-team
    system: gateway
    reference: https://gateway.example/control/CTRL-GATEWAY-RATE-LIMIT
    attestedAt: '$issuedAt'
    expiresAt: '$expiresAt'
    scope:
      endpoint: /add
      method: POST
    evidence:
      type: signed-attestation
      digest: $evidenceDigest
    document: attestations/gateway.json
''',
  );

  // 7. Attestation document body & signature
  final attestationBody = <String, Object?>{
    'providerId': 'external-gateway',
    'controlId': 'CTRL-GATEWAY-RATE-LIMIT',
    'target': 'backend',
    'variant': 'default',
    'kind': 'rate-limit',
    'layer': 'edge',
    'owner': 'platform-team',
    'system': 'gateway',
    'reference': 'https://gateway.example/control/CTRL-GATEWAY-RATE-LIMIT',
    'scopeHash': scopeHash,
    'evidenceType': 'signed-attestation',
    'evidenceDigest': evidenceDigest,
    'issuedAt': issuedAt,
    'expiresAt': expiresAt,
  };

  final attestationUnsigned = <String, Object?>{
    'kind': 'zuke.external-attestation',
    'signer': {
      'signerId': 'attestation-signer',
      'keyId': 'default',
      'algorithm': 'Ed25519',
    },
    'body': attestationBody,
  };

  const domain = 'Zuke external control attestation\u0000';
  final bytesToSign = utf8.encode(
    '$domain${canonicalJson(attestationUnsigned)}',
  );
  final signatureObj = await algo.sign(
    bytesToSign,
    keyPair: attestationKeyPair,
  );
  final signatureB64 = base64Encode(signatureObj.bytes);

  final attestationRecord = <String, Object?>{
    ...attestationUnsigned,
    'signature': signatureB64,
  };

  final attestDir = Directory('${tempDir.path}/attestations')
    ..createSync(recursive: true);
  File('${attestDir.path}/gateway.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(attestationRecord),
  );

  return tempDir;
}

File _workspacePackageConfig() {
  var directory = Directory.current.absolute;
  while (true) {
    final packageConfig = File(
      '${directory.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}package_config.json',
    );
    if (packageConfig.existsSync() &&
        File('${directory.path}${Platform.pathSeparator}melos.yaml')
            .existsSync()) {
      return packageConfig;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate the workspace package config.');
    }
    directory = parent;
  }
}
