import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_cli/src/external_signing_client.dart';
import 'package:test/test.dart';

void main() {
  final trustedKey = TrustKey(
    signerId: 'attestation-signer',
    keyId: 'test-key',
    algorithm: 'Ed25519',
    publicKey: List<int>.filled(32, 7),
    fingerprint: 'sha256:${sha256.convert(List<int>.filled(32, 7))}',
    usages: const {'attestation'},
    status: 'active',
  );

  test('requires a signer endpoint and short-lived bearer token', () {
    final client = ExternalSigningClient(environment: const {});

    expect(
      client.sign(
        signerId: trustedKey.signerId,
        keyId: trustedKey.keyId,
        usage: 'attestation',
        domainSeparator: 'domain\u0000',
        payload: utf8.encode('payload'),
        trustedKey: trustedKey,
      ),
      throwsFormatException,
    );
  });

  test(
    'binds the exact payload and accepts only matching signer identity',
    () async {
      Map<String, Object?>? requestBody;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        requestBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, Object?>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'signerId': 'attestation-signer',
            'keyId': 'test-key',
            'algorithm': 'Ed25519',
            'publicKeyFingerprint': trustedKey.fingerprint,
            'signature': base64Encode(List<int>.filled(64, 1)),
          }),
        );
        await request.response.close();
      });
      final payload = utf8.encode('canonical payload');
      final client = ExternalSigningClient(
        environment: {
          'ZUKE_SIGNING_PROVIDER_URL':
              'http://${server.address.address}:${server.port}/v1/sign',
          'ZUKE_SIGNING_PROVIDER_BEARER_TOKEN': 'short-lived-test-token',
        },
      );

      final result = await client.sign(
        signerId: trustedKey.signerId,
        keyId: trustedKey.keyId,
        usage: 'attestation',
        domainSeparator: 'domain\u0000',
        payload: payload,
        trustedKey: trustedKey,
      );

      expect(base64Decode(result.signature), hasLength(64));
      expect(
        requestBody!['payloadDigest'],
        'sha256:${sha256.convert(payload)}',
      );
      expect(requestBody!['payloadBase64'], base64Encode(payload));
      expect(requestBody!['usage'], 'attestation');
    },
  );

  test('rejects a provider response with a mismatched fingerprint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      await request.drain();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'signerId': 'attestation-signer',
          'keyId': 'test-key',
          'algorithm': 'Ed25519',
          'publicKeyFingerprint': 'sha256:${List.filled(64, '0').join()}',
          'signature': base64Encode(List<int>.filled(64, 1)),
        }),
      );
      await request.response.close();
    });
    final client = ExternalSigningClient(
      environment: {
        'ZUKE_SIGNING_PROVIDER_URL':
            'http://${server.address.address}:${server.port}/v1/sign',
        'ZUKE_SIGNING_PROVIDER_BEARER_TOKEN': 'short-lived-test-token',
      },
    );

    expect(
      client.sign(
        signerId: trustedKey.signerId,
        keyId: trustedKey.keyId,
        usage: 'attestation',
        domainSeparator: 'domain\u0000',
        payload: utf8.encode('payload'),
        trustedKey: trustedKey,
      ),
      throwsFormatException,
    );
  });

  test('rejects malformed and non-Ed25519 signature responses', () async {
    for (final signature in [
      'not-base64!',
      base64Encode([1, 2, 3]),
    ]) {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        await request.drain();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'signerId': 'attestation-signer',
            'keyId': 'test-key',
            'algorithm': 'Ed25519',
            'publicKeyFingerprint': trustedKey.fingerprint,
            'signature': signature,
          }),
        );
        await request.response.close();
      });
      final client = ExternalSigningClient(
        environment: {
          'ZUKE_SIGNING_PROVIDER_URL':
              'http://${server.address.address}:${server.port}/v1/sign',
          'ZUKE_SIGNING_PROVIDER_BEARER_TOKEN': 'short-lived-test-token',
        },
      );

      await expectLater(
        client.sign(
          signerId: trustedKey.signerId,
          keyId: trustedKey.keyId,
          usage: 'attestation',
          domainSeparator: 'domain\u0000',
          payload: utf8.encode('payload'),
          trustedKey: trustedKey,
        ),
        throwsFormatException,
      );
    }
  });
}
