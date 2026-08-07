import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:zuke_core/zuke_core.dart';

class ExternalSignature {
  final String signature;

  const ExternalSignature(this.signature);
}

/// Requests a detached signature without ever handling a private key.
class ExternalSigningClient {
  ExternalSigningClient({
    Map<String, String>? environment,
    HttpClient Function()? httpClientFactory,
  }) : _environment = Map.unmodifiable(environment ?? Platform.environment),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final Map<String, String> _environment;
  final HttpClient Function() _httpClientFactory;

  Future<ExternalSignature> sign({
    required String signerId,
    required String keyId,
    required String usage,
    required String domainSeparator,
    required List<int> payload,
    required TrustKey trustedKey,
  }) async {
    final endpoint = _environment['ZUKE_SIGNING_PROVIDER_URL'];
    final bearer = _environment['ZUKE_SIGNING_PROVIDER_BEARER_TOKEN'];
    if (endpoint == null ||
        endpoint.isEmpty ||
        bearer == null ||
        bearer.isEmpty) {
      throw const FormatException(
        'ZUKE_SIGNING_PROVIDER_URL and '
        'ZUKE_SIGNING_PROVIDER_BEARER_TOKEN are required',
      );
    }
    final requestBody = <String, Object?>{
      'signerId': signerId,
      'keyId': keyId,
      'usage': usage,
      'algorithm': 'Ed25519',
      'domainSeparator': domainSeparator,
      'payloadDigest': 'sha256:${sha256.convert(payload)}',
      'payloadBase64': base64Encode(payload),
    };
    final client = _httpClientFactory();
    try {
      final request = await client
          .postUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 30));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $bearer')
        ..contentType = ContentType.json;
      request.write(jsonEncode(requestBody));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final responseText = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw FormatException(
          'Signing provider returned HTTP ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(responseText);
      if (decoded is! Map)
        throw const FormatException('Invalid signing response');
      final signature = decoded['signature'];
      if (decoded['signerId'] != signerId ||
          decoded['keyId'] != keyId ||
          decoded['algorithm'] != 'Ed25519' ||
          decoded['publicKeyFingerprint'] != trustedKey.fingerprint ||
          signature is! String ||
          signature.isEmpty) {
        throw const FormatException(
          'Signing provider identity does not match repository trust metadata',
        );
      }
      final signatureBytes = base64Decode(signature);
      if (signatureBytes.length != 64) {
        throw const FormatException(
          'Signing provider returned an invalid Ed25519 signature length',
        );
      }
      return ExternalSignature(signature);
    } finally {
      client.close(force: true);
    }
  }
}
