import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:zuke_core/zuke_core.dart';

void main() {
  test(
    'Ed25519 records are not verified without trusted public material',
    () async {
      final seed = List<int>.filled(32, 7);
      final record = await Ed25519ReleaseSigner().sign(
        body: {
          'workspace': 'test',
          'repositoryState': 'clean',
          'engineVersion': '1.0.0',
          'lockDigest': List.filled(64, '0').join(),
          'policyHash': 'sha256:${List.filled(64, '1').join()}',
          'evidenceRequirementsHash': 'sha256:${List.filled(64, '2').join()}',
          'assurance': const [],
          'evidenceDigests': const [],
          'previousRecord': null,
        },
        seed: seed,
        signerId: 'ci',
        keyId: 'release-1',
      );
      expect(record.containsKey('publicKey'), isFalse);
      expect(await Ed25519ReleaseSigner().verify(record), isFalse);
      final pair = await Ed25519().newKeyPairFromSeed(seed);
      final public = await pair.extractPublicKey();
      expect(
        await Ed25519ReleaseSigner().verify(
          record,
          trustedPublicKey: public.bytes,
        ),
        isTrue,
      );
      expect(base64Encode(public.bytes), isNotEmpty);
    },
  );

  test('trusted bundle enforces usage and revocation', () async {
    final seed = List<int>.filled(32, 9);
    final pair = await Ed25519().newKeyPairFromSeed(seed);
    final public = await pair.extractPublicKey();
    final fingerprint = 'sha256:${sha256.convert(public.bytes)}';
    final active = TrustBundle.fromJson({
      'schemaVersion': 'zuke.ed25519-trust.v2',
      'keys': [
        {
          'signerId': 'ci',
          'keyId': 'release-1',
          'algorithm': 'Ed25519',
          'publicKey': base64Encode(public.bytes),
          'fingerprint': fingerprint,
          'usages': ['release'],
          'status': 'active',
        },
      ],
    });
    final record = await Ed25519ReleaseSigner().sign(
      body: {
        'workspace': 'test',
        'repositoryState': 'clean',
        'engineVersion': '1.0.0',
        'lockDigest': List.filled(64, '0').join(),
        'policyHash': 'sha256:${List.filled(64, '1').join()}',
        'evidenceRequirementsHash': 'sha256:${List.filled(64, '2').join()}',
        'assurance': const [],
        'evidenceDigests': const [],
        'previousRecord': null,
      },
      seed: seed,
      signerId: 'ci',
      keyId: 'release-1',
    );
    expect(await TrustedReleaseVerifier().verify(record, active), isTrue);
    final placeholder = await Ed25519ReleaseSigner().sign(
      body: {
        'workspace': 'test',
        'repositoryState': '0000000000000000000000000000000000000000',
        'engineVersion': '1.0.0',
        'lockDigest': List.filled(64, '0').join(),
        'policyHash': 'sha256:${List.filled(64, '1').join()}',
        'evidenceRequirementsHash': 'sha256:${List.filled(64, '2').join()}',
        'assurance': const [],
        'evidenceDigests': const [],
        'previousRecord': null,
      },
      seed: seed,
      signerId: 'ci',
      keyId: 'release-1',
    );
    expect(await TrustedReleaseVerifier().verify(placeholder, active), isFalse);
    final revoked = TrustBundle.fromJson({
      'schemaVersion': 'zuke.ed25519-trust.v2',
      'keys': [
        {
          'signerId': 'ci',
          'keyId': 'release-1',
          'algorithm': 'Ed25519',
          'publicKey': base64Encode(public.bytes),
          'fingerprint': fingerprint,
          'usages': ['release'],
          'status': 'revoked',
        },
      ],
    });
    expect(await TrustedReleaseVerifier().verify(record, revoked), isFalse);
  });
}
