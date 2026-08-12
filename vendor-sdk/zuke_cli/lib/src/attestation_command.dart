import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'attestation_verification.dart';
import 'external_signing_client.dart';
import 'trust_bundle.dart';

class AttestationCommand {
  static const _domain = 'Zuke external control attestation\u0000';
  final ArgResults args;
  final ExternalSigningClient signingClient;

  AttestationCommand(this.args, {ExternalSigningClient? signingClient})
    : signingClient = signingClient ?? ExternalSigningClient();

  Future<int> create() async {
    final root = args['root'] as String? ?? Directory.current.path;
    final providerId = args['provider-id'] as String;
    final evidencePath = args['evidence'] as String;
    final signerId = args['signer-id'] as String;
    final keyId = args['key-id'] as String? ?? 'default';
    final reference = args['reference'] as String;
    final issuedAt = _parseTime(args['issued-at'] as String, 'issued-at');
    final expiresAt = _parseTime(args['expires-at'] as String, 'expires-at');
    final now = DateTime.now().toUtc();
    if (issuedAt.isAfter(now)) {
      throw const FormatException('issued-at must not be in the future');
    }
    if (!expiresAt.isAfter(issuedAt)) {
      throw const FormatException('expires-at must be after issued-at');
    }
    if (!expiresAt.isAfter(now)) {
      throw const FormatException('expires-at must not be in the past');
    }
    if (expiresAt.difference(issuedAt) > const Duration(days: 90)) {
      throw const FormatException(
        'Attestation validity must not exceed 90 days',
      );
    }
    final evidence = File(evidencePath).readAsBytesSync();
    if (evidence.isEmpty) {
      throw const FormatException('Gateway evidence must not be empty');
    }
    final workspace = WorkspaceDiscovery().discover(root);
    final provider = _provider(workspace, providerId);
    if (provider == null) {
      throw FormatException('Attested provider not found: $providerId');
    }
    final documentPath = provider['document']?.toString();
    if (documentPath == null || documentPath.isEmpty) {
      throw const FormatException('Attested provider has no document path');
    }
    final trust = loadWorkspaceTrustBundle(workspace);
    final trustedKey = trust.find(signerId, keyId, 'attestation');
    if (trustedKey == null) {
      throw const FormatException('Signer is not active for attestation usage');
    }
    final body = <String, Object?>{
      'providerId': providerId,
      'controlId': provider['provides']?.toString() ?? '',
      'target': provider['target']?.toString() ?? '',
      'variant': provider['variant']?.toString() ?? 'default',
      'kind': provider['kind']?.toString() ?? '',
      'layer': provider['layer']?.toString() ?? '',
      'owner': provider['owner']?.toString() ?? '',
      'system': provider['system']?.toString() ?? '',
      'reference': reference,
      'scopeHash': _hash(provider['scope']),
      'evidenceType': (provider['evidence'] as Map?)?['type']?.toString() ?? '',
      'evidenceDigest': 'sha256:${sha256.convert(evidence)}',
      'issuedAt': issuedAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
    };
    if (body.values.any((value) => value is String && value.isEmpty)) {
      throw const FormatException(
        'Attestation provider metadata is incomplete',
      );
    }
    final unsigned = <String, Object?>{
      'kind': 'zuke.external-attestation',
      'signer': {'signerId': signerId, 'keyId': keyId, 'algorithm': 'Ed25519'},
      'body': body,
    };
    final payload = utf8.encode('$_domain${canonicalJson(unsigned)}');
    final external = await signingClient.sign(
      signerId: signerId,
      keyId: keyId,
      usage: 'attestation',
      domainSeparator: _domain,
      payload: payload,
      trustedKey: trustedKey,
    );
    final record = <String, Object?>{
      ...unsigned,
      'signature': external.signature,
    };
    if (!await SignedAttestationVerifier().verify(record, trust)) {
      throw const FormatException(
        'Signing provider returned an invalid attestation signature',
      );
    }
    final policyFile = File('$root/policies/attestations.yaml');
    final updatedPolicy = _updateProviderPolicy(
      policyFile.readAsStringSync(),
      providerId: providerId,
      digest: body['evidenceDigest']! as String,
      issuedAt: body['issuedAt']! as String,
      expiresAt: body['expiresAt']! as String,
      reference: reference,
    );
    final documentFile = File('$root/$documentPath');
    final originalDocument = documentFile.existsSync()
        ? documentFile.readAsStringSync()
        : null;
    final originalPolicy = policyFile.readAsStringSync();
    try {
      _writeAtomically(
        documentFile,
        '${JsonEncoder.withIndent('  ').convert(record)}\n',
      );
      _writeAtomically(policyFile, updatedPolicy);
      final verifiedWorkspace = WorkspaceDiscovery().discover(root);
      final verified = await AttestationVerification().verify(
        verifiedWorkspace,
      );
      if (!verified.any(
        (proof) =>
            proof.providerIds.contains(providerId) &&
            proof.status.name == 'attested',
      )) {
        final diagnostics = verified
            .expand((proof) => proof.diagnostics)
            .toSet()
            .join('; ');
        final configuredProviders = verifiedWorkspace.data.policies.values
            .expand(
              (policy) =>
                  (policy['providers'] as List? ?? const []).whereType<Map>(),
            )
            .map(
              (candidate) =>
                  '${candidate['id']}:${candidate['provides']}:'
                  '${candidate['target']}:${candidate['variant']}:'
                  '${candidate['assurance']}',
            )
            .join(', ');
        final discoveryErrors = verifiedWorkspace.data.errors.join('; ');
        throw FormatException(
          'Written attestation does not verify against policy'
          '${diagnostics.isEmpty ? '' : ': $diagnostics'}'
          '${configuredProviders.isEmpty ? '' : ' [$configuredProviders]'}'
          '${discoveryErrors.isEmpty ? '' : ' ($discoveryErrors)'}',
        );
      }
    } on Object {
      // A two-file update cannot be made filesystem-atomic. Restore both
      // inputs if any write or post-write verification fails so a failed
      // signing request never leaves an accepted-looking partial state.
      _writeAtomically(policyFile, originalPolicy);
      if (originalDocument == null) {
        if (documentFile.existsSync()) documentFile.deleteSync();
      } else {
        _writeAtomically(documentFile, originalDocument);
      }
      rethrow;
    }
    stdout.writeln('Wrote signed attestation for $providerId');
    return 0;
  }

  DateTime _parseTime(String value, String field) {
    final parsed = DateTime.tryParse(value)?.toUtc();
    if (parsed == null) {
      throw FormatException('$field must be an ISO-8601 timestamp');
    }
    return parsed;
  }

  Map? _provider(WorkspaceDiscoveryResult workspace, String id) {
    for (final policy in workspace.data.policies.values) {
      final providers = policy['providers'];
      if (providers is List) {
        for (final provider in providers.whereType<Map>()) {
          if (provider['id'] == id && provider['assurance'] == 'attested') {
            return provider;
          }
        }
      }
    }
    return null;
  }

  String _hash(Object? value) =>
      'sha256:${sha256.convert(utf8.encode(canonicalJson(value)))}';

  String _updateProviderPolicy(
    String source, {
    required String providerId,
    required String digest,
    required String issuedAt,
    required String expiresAt,
    required String reference,
  }) {
    final lines = source.split(RegExp(r'\r?\n'));
    final marker = RegExp(
      '^([ \\t]*)-\\s+id:\\s*${RegExp.escape(providerId)}\\s*\$',
    );
    final start = lines.indexWhere(marker.hasMatch);
    if (start < 0) {
      throw FormatException(
        'Provider $providerId was not found in policies/attestations.yaml',
      );
    }
    final indentation = marker.firstMatch(lines[start])!.group(1)!;
    final nextProvider = RegExp('^${RegExp.escape(indentation)}-\\s+id:\\s*');
    var end = lines.length;
    for (var index = start + 1; index < lines.length; index++) {
      if (nextProvider.hasMatch(lines[index])) {
        end = index;
        break;
      }
    }
    final replacements = {
      'reference': reference,
      'attestedAt': issuedAt,
      'expiresAt': expiresAt,
      'digest': digest,
    };
    for (final replacement in replacements.entries) {
      final field = RegExp(
        '^([ \\t]+)${RegExp.escape(replacement.key)}:\\s*.*\$',
      );
      var replaced = false;
      for (var index = start + 1; index < end; index++) {
        final match = field.firstMatch(lines[index]);
        if (match == null) continue;
        lines[index] =
            '${match.group(1)}${replacement.key}: ${replacement.value}';
        replaced = true;
        break;
      }
      if (!replaced) {
        throw FormatException(
          'Provider $providerId is missing ${replacement.key}',
        );
      }
    }
    final updated = lines.join('\n');
    return source.endsWith('\n') && !updated.endsWith('\n')
        ? '$updated\n'
        : updated;
  }

  void _writeAtomically(File target, String contents) {
    target.parent.createSync(recursive: true);
    final temporary = File(
      '${target.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
    );
    temporary.writeAsStringSync(contents);
    if (target.existsSync()) target.deleteSync();
    temporary.renameSync(target.path);
  }
}
