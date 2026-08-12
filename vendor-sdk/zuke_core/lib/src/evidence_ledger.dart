/// Published implementation dependency; not an extension contract.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'canonical_json.dart';

/// Deterministic Ed25519 release-record signer. Private key material is
/// supplied by the caller and is never persisted by this package.
class Ed25519ReleaseSigner {
  static const _domain = 'Zuke behavioral assurance release\u0000';
  final Ed25519 algorithm;
  Ed25519ReleaseSigner({Ed25519? algorithm})
    : algorithm = algorithm ?? Ed25519();

  Future<Map<String, Object?>> sign({
    required Map<String, Object?> body,
    required List<int> seed,
    required String signerId,
    required String keyId,
  }) async {
    if (seed.length != 32) {
      throw ArgumentError.value(
        seed.length,
        'seed',
        'Ed25519 seed must be 32 bytes',
      );
    }
    const requiredBody = [
      'workspace',
      'repositoryState',
      'engineVersion',
      'lockDigest',
      'policyHash',
      'evidenceRequirementsHash',
      'assurance',
      'evidenceDigests',
      'previousRecord',
    ];
    for (final key in requiredBody) {
      if (!body.containsKey(key) ||
          ((key.endsWith('Hash') || key == 'lockDigest') &&
              body[key] is! String)) {
        throw FormatException('Release body is missing $key');
      }
    }
    final unsigned = <String, Object?>{
      'kind': 'zuke.behavioral-assurance-release',
      'signer': {'signerId': signerId, 'keyId': keyId, 'algorithm': 'Ed25519'},
      'body': body,
    };
    final bytes = utf8.encode('$_domain${canonicalJson(unsigned)}');
    final digest = sha256.convert(bytes).toString();
    final keyPair = await algorithm.newKeyPairFromSeed(seed);
    final signature = await algorithm.sign(bytes, keyPair: keyPair);
    return {
      ...unsigned,
      'recordDigest': digest,
      'signature': base64Encode(signature.bytes),
    };
  }

  Future<bool> verify(
    Map<String, Object?> record, {
    List<int>? trustedPublicKey,
  }) async {
    final signer = (record['signer'] as Map?)?.cast<String, Object?>();
    final signatureText = record['signature'];
    final expectedDigest = record['recordDigest'];
    if (signer == null ||
        signatureText is! String ||
        expectedDigest is! String) {
      return false;
    }
    final unsigned = <String, Object?>{
      'kind': record['kind'],
      'signer': signer,
      'body': record['body'],
    };
    final bytes = utf8.encode('$_domain${canonicalJson(unsigned)}');
    if (sha256.convert(bytes).toString() != expectedDigest) return false;
    if (trustedPublicKey == null) return false;
    final signature = Signature(
      base64Decode(signatureText),
      publicKey: SimplePublicKey(
        trustedPublicKey,
        type: KeyPairType.ed25519,
      ),
    );
    return algorithm.verify(bytes, signature: signature);
  }
}

class TrustKey {
  final String signerId;
  final String keyId;
  final String algorithm;
  final List<int> publicKey;
  final String fingerprint;
  final Set<String> usages;
  final String status;

  const TrustKey({
    required this.signerId,
    required this.keyId,
    required this.algorithm,
    required this.publicKey,
    required this.fingerprint,
    required this.usages,
    required this.status,
  });

  bool get active => status == 'active' && algorithm == 'Ed25519';

  factory TrustKey.fromJson(Map value) {
    final encoded = value['publicKey'];
    if (encoded is! String) {
      throw const FormatException('Trust key publicKey missing');
    }
    final bytes = base64Decode(encoded);
    if (bytes.length != 32 || value['algorithm'] != 'Ed25519') {
      throw const FormatException('Invalid Ed25519 trust key');
    }
    final expected = 'sha256:${sha256.convert(bytes)}';
    if (value['fingerprint'] != expected) {
      throw const FormatException('Trust key fingerprint mismatch');
    }
    final status = value['status'];
    if (status != 'active' && status != 'revoked') {
      throw const FormatException('Invalid trust key status');
    }
    return TrustKey(
      signerId: value['signerId'] as String,
      keyId: value['keyId'] as String,
      algorithm: value['algorithm'] as String,
      publicKey: bytes,
      fingerprint: value['fingerprint'] as String,
      usages: (value['usages'] as List? ?? const [])
          .whereType<String>()
          .toSet(),
      status: status as String,
    );
  }
}

class TrustBundle {
  final List<TrustKey> keys;
  const TrustBundle(this.keys);

  factory TrustBundle.fromJson(Map value) {
    if (value['kind'] != 'zuke.ed25519-trust') {
      throw const FormatException(
        'Invalid Ed25519 trust bundle format; regenerate it for the current Zuke release',
      );
    }
    final keys = (value['keys'] as List? ?? const [])
        .whereType<Map>()
        .map(TrustKey.fromJson)
        .toList();
    final identities = <String>{};
    for (final key in keys) {
      if (!identities.add('${key.signerId}|${key.keyId}')) {
        throw const FormatException('Duplicate trust key identity');
      }
    }
    return TrustBundle(keys);
  }

  TrustKey? find(String signerId, String keyId, String usage) {
    for (final key in keys) {
      if (key.signerId == signerId &&
          key.keyId == keyId &&
          key.active &&
          key.usages.contains(usage)) {
        return key;
      }
    }
    return null;
  }
}

class TrustedReleaseVerifier {
  final Ed25519ReleaseSigner signer;
  TrustedReleaseVerifier({Ed25519ReleaseSigner? signer})
    : signer = signer ?? Ed25519ReleaseSigner();

  Future<bool> verify(Map<String, Object?> record, TrustBundle trust) async {
    final signerMap = (record['signer'] as Map?)?.cast<String, Object?>();
    final signerId = signerMap?['signerId'];
    final keyId = signerMap?['keyId'];
    if (signerId is! String ||
        keyId is! String ||
        signerMap?['algorithm'] != 'Ed25519' ||
        record['kind'] != 'zuke.behavioral-assurance-release' ||
        record['body'] is! Map) {
      return false;
    }
    final digest = record['recordDigest'];
    if (digest is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      return false;
    }
    final body = Map<String, Object?>.from(record['body'] as Map);
    for (final field in const [
      'workspace',
      'repositoryState',
      'engineVersion',
      'lockDigest',
      'policyHash',
      'evidenceRequirementsHash',
      'previousRecord',
    ]) {
      if (!body.containsKey(field)) return false;
    }
    if (body['workspace'] is! String ||
        body['repositoryState'] is! String ||
        body['engineVersion'] is! String ||
        body['lockDigest'] is! String ||
        body['policyHash'] is! String ||
        body['evidenceRequirementsHash'] is! String ||
        (body['previousRecord'] != null && body['previousRecord'] is! String) ||
        body['assurance'] is! List ||
        body['evidenceDigests'] is! List) {
      return false;
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(body['lockDigest'] as String) ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(
          body['policyHash'] as String,
        ) ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(
          body['evidenceRequirementsHash'] as String,
        )) {
      return false;
    }
    if (body['repositoryState'] ==
        '0000000000000000000000000000000000000000') {
      return false;
    }
    final key = trust.find(signerId, keyId, 'release');
    if (key == null) return false;
    return signer.verify(record, trustedPublicKey: key.publicKey);
  }
}

/// Verifies a separately signed external-control attestation.
class SignedAttestationVerifier {
  static const _domain = 'Zuke external control attestation\u0000';
  final Ed25519 algorithm;

  SignedAttestationVerifier({Ed25519? algorithm})
    : algorithm = algorithm ?? Ed25519();

  Future<bool> verify(Map<String, Object?> record, TrustBundle trust) async {
    if (record['kind'] != 'zuke.external-attestation') {
      return false;
    }
    final signer = (record['signer'] as Map?)?.cast<String, Object?>();
    final body = (record['body'] as Map?)?.cast<String, Object?>();
    final signatureText = record['signature'];
    if (signer == null ||
        body == null ||
        signatureText is! String ||
        signer['algorithm'] != 'Ed25519') {
      return false;
    }
    for (final field in const [
      'providerId',
      'controlId',
      'target',
      'variant',
      'kind',
      'layer',
      'owner',
      'system',
      'reference',
      'scopeHash',
      'evidenceType',
      'evidenceDigest',
      'issuedAt',
      'expiresAt',
    ]) {
      if (body[field] is! String || (body[field] as String).isEmpty) {
        return false;
      }
    }
    if (!RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(
      body['evidenceDigest'] as String,
    )) {
      return false;
    }
    final signerId = signer['signerId'];
    final keyId = signer['keyId'];
    if (signerId is! String || keyId is! String) return false;
    final key = trust.find(signerId, keyId, 'attestation');
    if (key == null) return false;
    final unsigned = <String, Object?>{
      'kind': record['kind'],
      'signer': signer,
      'body': body,
    };
    final bytes = utf8.encode('$_domain${canonicalJson(unsigned)}');
    final signature = Signature(
      base64Decode(signatureText),
      publicKey: SimplePublicKey(key.publicKey, type: KeyPairType.ed25519),
    );
    return algorithm.verify(bytes, signature: signature);
  }
}
