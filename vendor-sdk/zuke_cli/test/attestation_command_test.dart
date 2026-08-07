import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:zuke_cli/src/attestation_command.dart';
import 'package:zuke_cli/src/external_signing_client.dart';
import 'package:test/test.dart';

void main() {
  group('AttestationCommand input validation', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('zuke-attestation-test-');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test(
      'rejects a future issue timestamp before reading external evidence',
      () {
        final now = DateTime.now().toUtc();
        final command = AttestationCommand(
          _arguments(
            root: root.path,
            issuedAt: now.add(const Duration(minutes: 1)),
            expiresAt: now.add(const Duration(days: 1)),
          ),
        );

        expect(command.create(), throwsFormatException);
      },
    );

    test('rejects validity windows longer than ninety days', () {
      final now = DateTime.now().toUtc();
      final command = AttestationCommand(
        _arguments(
          root: root.path,
          issuedAt: now.subtract(const Duration(minutes: 1)),
          expiresAt: now.add(const Duration(days: 91)),
        ),
      );

      expect(command.create(), throwsFormatException);
    });

    test('rejects an expiry timestamp that is already in the past', () {
      final now = DateTime.now().toUtc();
      final command = AttestationCommand(
        _arguments(
          root: root.path,
          issuedAt: now.subtract(const Duration(days: 2)),
          expiresAt: now.subtract(const Duration(days: 1)),
        ),
      );

      expect(command.create(), throwsFormatException);
    });

    test(
      'rejects an empty gateway artifact without discovering a workspace',
      () {
        final evidence = File('${root.path}/gateway.json')
          ..writeAsStringSync('');
        final now = DateTime.now().toUtc();
        final command = AttestationCommand(
          _arguments(
            root: root.path,
            evidence: evidence.path,
            issuedAt: now.subtract(const Duration(minutes: 1)),
            expiresAt: now.add(const Duration(days: 1)),
          ),
        );

        expect(command.create(), throwsFormatException);
      },
    );

    test('rejects an unknown or non-attested provider', () {
      final evidence = File('${root.path}/gateway.json')
        ..writeAsStringSync('{}');
      _writeWorkspace(root, '''
providers:
  - id: external-gateway
    assurance: proven
''');
      final command = _currentCommand(root, evidence);

      expect(command.create(), throwsFormatException);
    });

    test(
      'requires a provider document and active attestation signer',
      () async {
        final evidence = File('${root.path}/gateway.json')
          ..writeAsStringSync('{}');
        _writeWorkspace(root, '''
providers:
  - id: external-gateway
    assurance: attested
''');
        await expectLater(
          _currentCommand(root, evidence).create(),
          throwsFormatException,
        );

        _writeWorkspace(root, _completeProvider);
        final trust = File(
          '${root.path}/assurance-history/trust/ed25519-v2.json',
        );
        trust.parent.createSync(recursive: true);
        trust.writeAsStringSync(
          jsonEncode({'schemaVersion': 'zuke.ed25519-trust.v2', 'keys': []}),
        );
        await expectLater(
          _currentCommand(root, evidence).create(),
          throwsFormatException,
        );
      },
    );

    test(
      'rejects incomplete provider metadata before contacting a signer',
      () async {
        final evidence = File('${root.path}/gateway.json')
          ..writeAsStringSync('{}');
        _writeWorkspace(
          root,
          _completeProvider.replaceFirst('owner: team\n', ''),
        );
        final publicKey = List<int>.filled(32, 7);
        final trust = File(
          '${root.path}/assurance-history/trust/ed25519-v2.json',
        );
        trust.parent.createSync(recursive: true);
        trust.writeAsStringSync(
          jsonEncode({
            'schemaVersion': 'zuke.ed25519-trust.v2',
            'keys': [
              {
                'signerId': 'attestation-signer',
                'keyId': 'default',
                'algorithm': 'Ed25519',
                'publicKey': base64Encode(publicKey),
                'fingerprint': 'sha256:${sha256.convert(publicKey)}',
                'usages': ['attestation'],
                'status': 'active',
              },
            ],
          }),
        );

        await expectLater(
          _currentCommand(root, evidence).create(),
          throwsFormatException,
        );
      },
    );

    test('writes and post-verifies an externally signed attestation', () async {
      final evidence = File('${root.path}/gateway.json')
        ..writeAsStringSync('{"gateway":"export"}');
      _writeWorkspace(root, _completeProvider);
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPairFromSeed(_signingSeed);
      final publicKey = await keyPair.extractPublicKey();
      final fingerprint = 'sha256:${sha256.convert(publicKey.bytes)}';
      final trust = File(
        '${root.path}/assurance-history/trust/ed25519-v2.json',
      );
      trust.parent.createSync(recursive: true);
      trust.writeAsStringSync(
        jsonEncode({
          'schemaVersion': 'zuke.ed25519-trust.v2',
          'keys': [
            {
              'signerId': 'attestation-signer',
              'keyId': 'default',
              'algorithm': 'Ed25519',
              'publicKey': base64Encode(publicKey.bytes),
              'fingerprint': fingerprint,
              'usages': ['attestation'],
              'status': 'active',
            },
          ],
        }),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final payload = base64Decode(body['payloadBase64'] as String);
        final signature = await algorithm.sign(payload, keyPair: keyPair);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'signerId': 'attestation-signer',
            'keyId': 'default',
            'algorithm': 'Ed25519',
            'publicKeyFingerprint': fingerprint,
            'signature': base64Encode(signature.bytes),
          }),
        );
        await request.response.close();
      });
      final client = ExternalSigningClient(
        environment: {
          'ZUKE_SIGNING_PROVIDER_URL':
              'http://${server.address.host}:${server.port}/sign',
          'ZUKE_SIGNING_PROVIDER_BEARER_TOKEN': 'short-lived-token',
        },
      );
      final now = DateTime.now().toUtc();
      final command = AttestationCommand(
        _arguments(
          root: root.path,
          evidence: evidence.path,
          issuedAt: now.subtract(const Duration(minutes: 1)),
          expiresAt: now.add(const Duration(days: 30)),
        ),
        signingClient: client,
      );

      expect(await command.create(), 0);
      final document = File(
        '${root.path}/assurance-history/attestations/external-gateway.json',
      );
      expect(document.existsSync(), isTrue);
      expect(
        jsonDecode(document.readAsStringSync())['schemaVersion'],
        'zuke.external-attestation.v1',
      );
      expect(
        File('${root.path}/policies/attestations.yaml').readAsStringSync(),
        contains('sha256:${sha256.convert(evidence.readAsBytesSync())}'),
      );
    });
  });
}

const _completeProvider = '''
providers:
  - id: external-gateway
    assurance: attested
    document: assurance-history/attestations/external-gateway.json
    provides: CTRL-GATEWAY
    target: backend
    variant: default
    kind: gateway-policy
    layer: edge
    owner: team
    system: apim
    reference: EDGE-OLD
    attestedAt: 2026-01-01T00:00:00Z
    expiresAt: 2026-02-01T00:00:00Z
    scope: {path: /api}
    evidence:
      type: gateway-export
      digest: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
''';

final _signingSeed = _hex(
  '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
);

void _writeWorkspace(Directory root, String policy) {
  File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 2
specifications:
  features: [specs/features/**/*.feature]
  controls: [specs/controls/**/*.yaml]
policies:
  project: policies/attestations.yaml
trust:
  bundle: assurance-history/trust/ed25519-v2.json
''');
  final feature = File('${root.path}/specs/features/gateway.feature');
  feature.parent.createSync(recursive: true);
  feature.writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-GATEWAY
# spec-end
Feature: Gateway
  # rule-spec-begin
  # id: RULE-GATEWAY
  # requires:
  #   - id: CTRL-GATEWAY
  #     target: backend
  # rule-spec-end
  Rule: Gateway enforcement
    @SCN-GATEWAY
    Scenario: gateway policy
      Given the gateway is configured
''');
  final controls = File('${root.path}/specs/controls/controls.yaml');
  controls.parent.createSync(recursive: true);
  controls.writeAsStringSync('''
controls:
  - id: CTRL-GATEWAY
    coverageSemantics: external-attestation
''');
  final file = File('${root.path}/policies/attestations.yaml');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(policy);
}

AttestationCommand _currentCommand(Directory root, File evidence) {
  final now = DateTime.now().toUtc();
  return AttestationCommand(
    _arguments(
      root: root.path,
      evidence: evidence.path,
      issuedAt: now.subtract(const Duration(minutes: 1)),
      expiresAt: now.add(const Duration(days: 1)),
    ),
  );
}

List<int> _hex(String value) => [
  for (var index = 0; index < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
];

ArgResults _arguments({
  required String root,
  String evidence = 'does-not-need-to-exist.json',
  required DateTime issuedAt,
  required DateTime expiresAt,
}) =>
    (ArgParser()
          ..addOption('root')
          ..addOption('provider-id')
          ..addOption('evidence')
          ..addOption('reference')
          ..addOption('signer-id')
          ..addOption('key-id')
          ..addOption('issued-at')
          ..addOption('expires-at'))
        .parse([
          '--root',
          root,
          '--provider-id',
          'external-gateway',
          '--evidence',
          evidence,
          '--reference',
          'EDGE-POLICY-2841',
          '--signer-id',
          'attestation-signer',
          '--issued-at',
          issuedAt.toIso8601String(),
          '--expires-at',
          expiresAt.toIso8601String(),
        ]);
