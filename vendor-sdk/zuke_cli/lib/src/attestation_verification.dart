import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'trust_bundle.dart';

/// Resolves and verifies externally enforced controls before the synchronous
/// proof engine evaluates evidence eligibility.  A policy declaration is only
/// a candidate; it becomes [ProofStatus.attested] after its signed document
/// verifies against repository trust metadata and its body matches exactly.
class AttestationVerification {
  static const _minimumReleaseValidity = Duration(days: 14);
  Future<List<ControlProofResult>> verify(
    WorkspaceDiscoveryResult workspace,
  ) async {
    final results = <ControlProofResult>[];
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final requirementId = rule.metadata.id;
        if (requirementId == null) continue;
        for (final reference
            in rule.metadata.requires ?? const <ParsedControlRef>[]) {
          if (reference.kind != 'control' ||
              workspace.data.controls[reference.id]?['coverageSemantics'] !=
                  'external-attestation') {
            continue;
          }
          results.add(
            await _verifyRequirement(
              workspace,
              requirementId: requirementId,
              controlId: reference.id,
              target: reference.target,
              variant: reference.variant,
            ),
          );
        }
      }
    }
    final keys = <String>{};
    for (final result in results) {
      final key =
          '${result.requirementId}|${result.controlId}|${result.target}|${result.variant}';
      if (!keys.add(key)) {
        throw StateError('Duplicate external attestation proof key: $key');
      }
    }
    return results;
  }

  Future<ControlProofResult> _verifyRequirement(
    WorkspaceDiscoveryResult workspace, {
    required String requirementId,
    required String controlId,
    required String target,
    required String variant,
  }) async {
    ControlProofResult result(
      ProofStatus status, {
      List<String> diagnostics = const [],
      List<String> providerIds = const [],
    }) => ControlProofResult(
      requirementId: requirementId,
      controlId: controlId,
      target: target,
      variant: variant,
      semantics: CoverageSemantics.externalAttestation,
      status: status,
      providerIds: providerIds,
      diagnostics: diagnostics,
    );

    final provider = _provider(workspace, controlId, target, variant);
    if (provider == null) {
      return result(
        ProofStatus.missing,
        diagnostics: const ['No external attestation provider is configured'],
      );
    }
    final providerId = provider['id']?.toString();
    final documentPath = provider['document']?.toString();
    if (providerId == null ||
        providerId.isEmpty ||
        documentPath == null ||
        documentPath.isEmpty) {
      return result(
        ProofStatus.failed,
        diagnostics: const [
          'External attestation provider lacks id or document',
        ],
      );
    }
    final document = _confinedFile(workspace.config.root!, documentPath);
    if (document == null || !document.existsSync()) {
      return result(
        ProofStatus.missing,
        providerIds: [providerId],
        diagnostics: const ['Signed external attestation document is missing'],
      );
    }
    final trustFile = configuredTrustBundle(
      workspace.config.root!,
      configuredPath: workspace.config.trustBundle,
    );
    if (!trustFile.existsSync()) {
      return result(
        ProofStatus.missing,
        providerIds: [providerId],
        diagnostics: const ['Ed25519 attestation trust bundle is missing'],
      );
    }

    try {
      final record = Map<String, Object?>.from(
        jsonDecode(document.readAsStringSync()) as Map,
      );
      final trust = loadWorkspaceTrustBundle(workspace);
      final validSignature = await SignedAttestationVerifier().verify(
        record,
        trust,
      );
      if (!validSignature) {
        return result(
          ProofStatus.failed,
          providerIds: [providerId],
          diagnostics: const [
            'External attestation signature or trusted signer is invalid',
          ],
        );
      }
      final body = Map<String, Object?>.from(record['body'] as Map);
      final issued = DateTime.tryParse(body['issuedAt']?.toString() ?? '');
      final expiry = DateTime.tryParse(body['expiresAt']?.toString() ?? '');
      if (issued == null || expiry == null || !expiry.isAfter(issued)) {
        return result(
          ProofStatus.failed,
          providerIds: [providerId],
          diagnostics: const [
            'External attestation issue or expiry is invalid',
          ],
        );
      }
      if (issued.toUtc().isAfter(DateTime.now().toUtc())) {
        return result(
          ProofStatus.failed,
          providerIds: [providerId],
          diagnostics: const [
            'External attestation issue time is in the future',
          ],
        );
      }
      if (!expiry.toUtc().isAfter(DateTime.now().toUtc())) {
        return result(
          ProofStatus.expired,
          providerIds: [providerId],
          diagnostics: const ['External attestation has expired'],
        );
      }
      if (expiry.toUtc().isBefore(
        DateTime.now().toUtc().add(_minimumReleaseValidity),
      )) {
        return result(
          ProofStatus.failed,
          providerIds: [providerId],
          diagnostics: const [
            'ZUKE-ATTEST-EXPIRING: External attestation has fewer than 14 days remaining',
          ],
        );
      }
      final expected = <String, String>{
        'providerId': providerId,
        'controlId': controlId,
        'target': target,
        'variant': variant,
        'kind': provider['kind']?.toString() ?? '',
        'layer': provider['layer']?.toString() ?? '',
        'owner': provider['owner']?.toString() ?? '',
        'system': provider['system']?.toString() ?? '',
        'reference': provider['reference']?.toString() ?? '',
        'scopeHash': _hash(provider['scope']),
        'evidenceType': provider['evidence'] is Map
            ? (provider['evidence'] as Map)['type']?.toString() ?? ''
            : '',
        'evidenceDigest': provider['evidence'] is Map
            ? (provider['evidence'] as Map)['digest']?.toString() ?? ''
            : '',
      };
      for (final entry in expected.entries) {
        if (entry.value.isEmpty || body[entry.key] != entry.value) {
          return result(
            ProofStatus.failed,
            providerIds: [providerId],
            diagnostics: ['Attestation ${entry.key} does not match policy'],
          );
        }
      }
      if (!RegExp(
        r'^sha256:[a-f0-9]{64}$',
      ).hasMatch(expected['evidenceDigest']!)) {
        return result(
          ProofStatus.failed,
          providerIds: [providerId],
          diagnostics: const ['Attestation evidence digest is malformed'],
        );
      }
      final sourceScope = provider['scope'] is Map
          ? Map<String, Object?>.from(provider['scope'] as Map)
          : null;
      if (sourceScope != null && sourceScope.containsKey('sourceFiles')) {
        final expectedDigest = sourceScope['sourceDigest']?.toString() ?? '';
        final actualDigest = _sourceDigest(
          workspace.config.root!,
          sourceScope['sourceFiles'],
        );
        if (expectedDigest.isEmpty ||
            actualDigest == null ||
            expectedDigest != actualDigest) {
          return result(
            ProofStatus.failed,
            providerIds: [providerId],
            diagnostics: const [
              'External attestation source scope has drifted or is malformed',
            ],
          );
        }
      }
      return result(ProofStatus.attested, providerIds: [providerId]);
    } on FormatException catch (error) {
      return result(
        ProofStatus.failed,
        providerIds: [providerId],
        diagnostics: ['Malformed external attestation: $error'],
      );
    } on Object catch (error) {
      return result(
        ProofStatus.failed,
        providerIds: [providerId],
        diagnostics: ['Unable to verify external attestation: $error'],
      );
    }
  }

  Map? _provider(
    WorkspaceDiscoveryResult workspace,
    String controlId,
    String target,
    String variant,
  ) {
    for (final policy in workspace.data.policies.values) {
      final providers = policy['providers'];
      if (providers is! List) continue;
      for (final provider in providers.whereType<Map>()) {
        if (provider['provides'] == controlId &&
            provider['assurance'] == 'attested' &&
            provider['target'] == target &&
            (provider['variant']?.toString() ?? 'default') == variant) {
          return provider;
        }
      }
    }
    return null;
  }

  File? _confinedFile(String root, String relative) {
    if (relative.isEmpty ||
        relative.contains('..') ||
        relative.startsWith('/') ||
        relative.startsWith('\\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(relative)) {
      return null;
    }
    final rootDirectory = Directory(root).absolute;
    final candidate = File(
      '${rootDirectory.path}${Platform.pathSeparator}$relative',
    ).absolute;
    final rootPath = '${rootDirectory.path}${Platform.pathSeparator}';
    if (!candidate.path.startsWith(rootPath)) return null;
    return candidate;
  }

  String _hash(Object? value) {
    return 'sha256:${sha256.convert(utf8.encode(canonicalJson(value)))}';
  }

  String? _sourceDigest(String root, Object? files) {
    if (files is! List || files.isEmpty) return null;
    final chunks = <int>[];
    final paths = files.map((value) => value.toString()).toList()..sort();
    for (final path in paths) {
      final file = _confinedFile(root, path);
      if (file == null || !file.existsSync()) return null;
      chunks.addAll(utf8.encode('$path\u0000'));
      chunks.addAll(canonicalDigestBytes(path, file.readAsBytesSync()));
      chunks.add(0);
    }
    return 'sha256:${sha256.convert(chunks)}';
  }
}
