import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_verifier/zuke_verifier.dart';
import 'package:test/test.dart';

void main() {
  test('verifies a trusted ordered release export', () async {
    const seed = [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      26,
      27,
      28,
      29,
      30,
      31,
      32,
    ];
    final signer = Ed25519ReleaseSigner();
    final keyPair = await Ed25519().newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    final trust = TrustBundle.fromJson({
      'kind': 'zuke.ed25519-trust',
      'keys': [
        {
          'signerId': 'release-test',
          'keyId': 'test-key',
          'algorithm': 'Ed25519',
          'publicKey': base64Encode(publicKey.bytes),
          'fingerprint': 'sha256:${sha256.convert(publicKey.bytes)}',
          'usages': ['release'],
          'status': 'active',
        },
      ],
    });
    final previous = await signer.sign(
      body: _body(previousRecord: null, version: 'previous'),
      seed: seed,
      signerId: 'release-test',
      keyId: 'test-key',
    );
    final head = await signer.sign(
      body: _body(
        previousRecord: previous['recordDigest'] as String,
        version: 'head',
      ),
      seed: seed,
      signerId: 'release-test',
      keyId: 'test-key',
    );

    final result = await const ExportedReleaseVerifier().verify({
      'kind': 'zuke.behavioral-assurance-release-export',
      'chain': [head, previous],
    }, trust);

    expect(result.valid, isTrue);
    expect(result.recordDigests, [
      head['recordDigest'],
      previous['recordDigest'],
    ]);
  });

  test(
    'rejects a valid record chain with an incorrect predecessor order',
    () async {
      const seed = [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        18,
        19,
        20,
        21,
        22,
        23,
        24,
        25,
        26,
        27,
        28,
        29,
        30,
        31,
        32,
      ];
      final signer = Ed25519ReleaseSigner();
      final keyPair = await Ed25519().newKeyPairFromSeed(seed);
      final publicKey = await keyPair.extractPublicKey();
      final trust = TrustBundle.fromJson({
        'kind': 'zuke.ed25519-trust',
        'keys': [
          {
            'signerId': 'release-test',
            'keyId': 'test-key',
            'algorithm': 'Ed25519',
            'publicKey': base64Encode(publicKey.bytes),
            'fingerprint': 'sha256:${sha256.convert(publicKey.bytes)}',
            'usages': ['release'],
            'status': 'active',
          },
        ],
      });
      final first = await signer.sign(
        body: _body(previousRecord: null, version: 'first'),
        seed: seed,
        signerId: 'release-test',
        keyId: 'test-key',
      );
      final second = await signer.sign(
        body: _body(previousRecord: null, version: 'second'),
        seed: seed,
        signerId: 'release-test',
        keyId: 'test-key',
      );

      final result = await const ExportedReleaseVerifier().verify({
        'kind': 'zuke.behavioral-assurance-release-export',
        'chain': [first, second],
      }, trust);

      expect(result.valid, isFalse);
      expect(result.diagnostics.single, contains('predecessor'));
    },
  );

  group('adversarial export corpus', () {
    const verifier = ExportedReleaseVerifier();
    const emptyTrust = TrustBundle([]);

    test('rejects an unsupported export schema', () async {
      final result = await verifier.verify({
        'schemaVersion': 'other',
        'chain': const [],
      }, emptyTrust);
      expect(result.valid, isFalse);
      expect(result.diagnostics.single, contains('Unsupported'));
    });

    test('rejects an empty chain', () async {
      final result = await verifier.verify({
        'kind': 'zuke.behavioral-assurance-release-export',
        'chain': const [],
      }, emptyTrust);
      expect(result.valid, isFalse);
      expect(result.diagnostics.single, contains('empty'));
    });

    test('rejects malformed records before any trust decision', () async {
      final result = await verifier.verify({
        'kind': 'zuke.behavioral-assurance-release-export',
        'chain': [
          {'recordDigest': 'not-a-digest'},
        ],
      }, emptyTrust);
      expect(result.valid, isFalse);
      expect(result.diagnostics.single, contains('invalid recordDigest'));
    });

    test(
      'rejects malformed JSON objects through the standalone entry point',
      () async {
        final result = await verifier.verifyJson('[]', '{}');
        expect(result.valid, isFalse);
        expect(result.diagnostics.single, contains('JSON objects'));
      },
    );
  });
}

Map<String, Object?> _body({
  required String? previousRecord,
  required String version,
}) => {
  'workspace': 'fixture',
  'repositoryState': '0123456789abcdef0123456789abcdef01234567',
  'engineVersion': version,
  'lockDigest':
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  'policyHash':
      'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  'evidenceRequirementsHash':
      'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  'assurance': const [],
  'evidenceDigests': const [],
  'previousRecord': previousRecord,
};
