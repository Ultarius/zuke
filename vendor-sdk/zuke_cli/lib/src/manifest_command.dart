import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:args/args.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'ir.dart';
import 'lock_path.dart';
import 'package:zuke_core/zuke_core.dart';

import 'extraction_service.dart';
import 'lock_command.dart';
import 'attestation_verification.dart';
import 'external_signing_client.dart';
import 'trust_bundle.dart';
import 'scenario_selection.dart';
import 'proof_engine.dart';

class ManifestCommand {
  static Future<String> create({
    required String root,
    required String signerId,
    String keyId = 'default',
    String profile = 'release',
  }) async {
    _rejectLegacyHistoryLayout(root);
    _requireCleanRepository(root);
    final workspaceRoot = Directory(
      Directory(root).absolute.resolveSymbolicLinksSync(),
    );
    final workspace = WorkspaceDiscovery().discover(workspaceRoot.path);
    final trust = loadWorkspaceTrustBundle(workspace);
    if (trust.keys.isEmpty) {
      throw FormatException('No signers enrolled in ed25519.json');
    }
    final activeReleaseKeys = trust.keys
        .where((k) => k.active && k.usages.contains('release'))
        .toList();
    if (activeReleaseKeys.isEmpty) {
      throw FormatException(
        'No active release signers enrolled in ed25519.json',
      );
    }
    if (trust.find(signerId, keyId, 'release') == null) {
      throw FormatException(
        'Signer is not active in assurance-history/trust/ed25519.json',
      );
    }
    final lock = File(resolveProfileLockPath(workspaceRoot.path, profile));
    if (!lock.existsSync()) {
      throw const FormatException('A current zuke lock is required');
    }
    final extraction = await ExtractionService().extract(workspace);
    final verifiedAttestations = await AttestationVerification().verify(
      workspace,
    );
    final selection = const ScenarioSelector().resolve(workspace, profile);
    final validation = ValidatorEngine().validate(
      workspace,
      outputs: extraction.outputs,
      evidenceRecords: extraction.evidenceRecords,
      verifiedAttestationProofs: verifiedAttestations,
      profile: profile,
      selectedScenarioIds: selection.tagExpression == null
          ? null
          : selection.scenarioIds,
    );
    final report = validation.toReport(
      evidence: extraction.evidenceRecords
          .where((record) => record.profile == profile)
          .toList(),
      requiredEvidence: validation.requiredEvidence,
      workspace: root,
      profile: profile,
    );
    if (!report.eligible || extraction.errors.isNotEmpty) {
      throw FormatException(
        'Release creation requires an eligible validation report: '
        '${report.ineligibilityReasons.join('; ')}',
      );
    }
    final expectedLock =
        await LockCommand(
          (ArgParser()..addOption('root')).parse(const []),
        ).buildLock(
          WorkspaceContext(
            root: workspaceRoot,
            workspace: workspace,
            extraction: extraction,
          ),
          validation,
          profile: profile,
        );
    if (lock.readAsStringSync() != expectedLock) {
      throw const FormatException('Release creation requires a current lock');
    }
    final lockDigest = lock.existsSync()
        ? sha256.convert(lock.readAsBytesSync()).toString()
        : null;
    final body = <String, Object?>{
      'workspace': Directory(
        root,
      ).absolute.path.replaceAll('\\', '/').split('/').last,
      'repositoryState': _gitState(root),
      'engineVersion': '1.0.0',
      'lockDigest': lockDigest,
      'policyHash': await _computeHash(root, 'policies'),
      'evidenceRequirementsHash': await _computeHash(root, 'evidence'),
      'assurance': report.controlProofs.map((proof) => proof.toJson()).toList(),
      'evidenceDigests':
          report.evidence
              .map(
                (record) => sha256
                    .convert(utf8.encode(canonicalJson(record.toJson())))
                    .toString(),
              )
              .toList()
            ..sort(),
      'previousRecord': await _verifiedHead(root),
    };
    final existingHead = await _verifiedHead(root);
    if (existingHead != null) {
      final headFile = File(
        '$root/assurance-history/records/$existingHead.json',
      );
      if (headFile.existsSync()) {
        final head = Map<String, Object?>.from(
          jsonDecode(headFile.readAsStringSync()) as Map,
        );
        final headBody = Map<String, Object?>.from(head['body'] as Map)
          ..remove('previousRecord');
        final candidateBody = Map<String, Object?>.from(body)
          ..remove('previousRecord');
        if (const JsonEncoder().convert(headBody) ==
            const JsonEncoder().convert(candidateBody)) {
          return headFile.path;
        }
      }
    }
    final record = await _signWithExternalProvider(
      body: body,
      signerId: signerId,
      keyId: keyId,
      trustedKey: trust.find(signerId, keyId, 'release')!,
    );
    final digest = record['recordDigest'] as String;
    final dir = Directory('$root/assurance-history/records')
      ..createSync(recursive: true);
    final file = File('${dir.path}/$digest.json');
    if (!file.existsSync()) {
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(record) + '\n',
      );
    }
    return file.path;
  }

  /// Requests a detached Ed25519 signature from an operational signing
  /// service. The CLI never receives or handles a private seed.
  static Future<Map<String, Object?>> _signWithExternalProvider({
    required Map<String, Object?> body,
    required String signerId,
    required String keyId,
    required TrustKey trustedKey,
  }) async {
    const domain = 'Zuke behavioral assurance release\u0000';
    final unsigned = <String, Object?>{
      'kind': 'zuke.behavioral-assurance-release',
      'signer': {'signerId': signerId, 'keyId': keyId, 'algorithm': 'Ed25519'},
      'body': body,
    };
    final payload = utf8.encode('$domain${canonicalJson(unsigned)}');
    final external = await ExternalSigningClient().sign(
      signerId: signerId,
      keyId: keyId,
      usage: 'release',
      domainSeparator: domain,
      payload: payload,
      trustedKey: trustedKey,
    );
    final record = <String, Object?>{
      ...unsigned,
      'recordDigest': sha256.convert(payload).toString(),
      'signature': external.signature,
    };
    if (!await Ed25519ReleaseSigner().verify(
      record,
      trustedPublicKey: trustedKey.publicKey,
    )) {
      throw const FormatException(
        'Signing provider returned a signature that does not verify against repository trust metadata',
      );
    }
    return record;
  }

  static Future<String?> _verifiedHead(String root) async {
    final dir = Directory('$root/assurance-history/records');
    if (!dir.existsSync()) return null;
    final records = <String, Map<String, Object?>>{};
    for (final file in dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.json'),
    )) {
      final value = jsonDecode(file.readAsStringSync());
      if (value is! Map) {
        throw StateError('Invalid current record: ${file.path}');
      }
      final record = Map<String, Object?>.from(value);
      if (!await TrustedReleaseVerifier().verify(
        record,
        loadTrustBundle(root),
      )) {
        throw StateError('Invalid current signature: ${file.path}');
      }
      final digest = record['recordDigest'];
      if (digest is! String || !file.path.endsWith('$digest.json')) {
        throw StateError('Record filename does not match digest: ${file.path}');
      }
      records[digest] = record;
    }
    final referenced = <String>{};
    for (final record in records.values) {
      final previous = (record['body'] as Map?)?['previousRecord'];
      if (previous is String) {
        if (!records.containsKey(previous)) {
          throw StateError('Missing record predecessor: $previous');
        }
        referenced.add(previous);
      }
    }
    final heads = records.keys.where((id) => !referenced.contains(id)).toList();
    if (heads.length > 1) {
      throw StateError('Multiple record chain heads: $heads');
    }
    if (records.isNotEmpty && heads.isEmpty) {
      throw StateError('Record chain has a cycle and no head');
    }
    return heads.isEmpty ? null : heads.single;
  }

  static Future<bool> verify(
    String root, {
    String? head,
    bool current = false,
    bool requireHistory = false,
  }) async {
    _rejectLegacyHistoryLayout(root);
    final selected = head ?? await _verifiedHead(root);
    if (selected == null) return !current && !requireHistory;
    final dir = Directory('$root/assurance-history/records');
    final seen = <String>{};
    String? currentRecord = selected;
    while (currentRecord != null) {
      if (!seen.add(currentRecord)) return false;
      final file = File('${dir.path}/$currentRecord.json');
      if (!file.existsSync()) return false;
      final record = Map<String, Object?>.from(
        jsonDecode(file.readAsStringSync()) as Map,
      );
      if (!await TrustedReleaseVerifier().verify(
        record,
        loadTrustBundle(root),
      )) {
        return false;
      }
      currentRecord = ((record['body'] as Map?)?['previousRecord']) as String?;
    }
    if (!current) return true;
    try {
      final file = File('$root/assurance-history/records/$selected.json');
      final record = Map<String, Object?>.from(
        jsonDecode(file.readAsStringSync()) as Map,
      );
      final body = Map<String, Object?>.from(record['body'] as Map);
      if (body['repositoryState'] != _gitState(root)) return false;
      final workspace = WorkspaceDiscovery().discover(root);
      final lock = File(resolveProfileLockPath(root, 'release'));
      if (!lock.existsSync() ||
          body['lockDigest'] !=
              sha256.convert(lock.readAsBytesSync()).toString()) {
        return false;
      }
      if (body['policyHash'] != await _computeHash(root, 'policies') ||
          body['evidenceRequirementsHash'] !=
              await _computeHash(root, 'evidence')) {
        return false;
      }
      final extraction = await ExtractionService().extract(workspace);
      final selection = const ScenarioSelector().resolve(workspace, 'release');
      final validation = ValidatorEngine().validate(
        workspace,
        outputs: extraction.outputs,
        evidenceRecords: extraction.evidenceRecords,
        verifiedAttestationProofs: await AttestationVerification().verify(
          workspace,
        ),
        profile: 'release',
        selectedScenarioIds: selection.tagExpression == null
            ? null
            : selection.scenarioIds,
      );
      final report = validation.toReport(
        evidence: extraction.evidenceRecords
            .where((record) => record.profile == 'release')
            .toList(),
        requiredEvidence: validation.requiredEvidence,
        workspace: root,
        profile: 'release',
      );
      final expected =
          report.evidence
              .map(
                (item) => sha256
                    .convert(utf8.encode(canonicalJson(item.toJson())))
                    .toString(),
              )
              .toList()
            ..sort();
      final actual =
          (body['evidenceDigests'] as List?)?.whereType<String>().toList() ??
          <String>[];
      actual.sort();
      return const JsonEncoder().convert(expected) ==
          const JsonEncoder().convert(actual);
    } catch (_) {
      return false;
    }
  }

  static Future<void> export(String root, String output, {String? head}) async {
    _rejectLegacyHistoryLayout(root);
    final selected = head ?? await _verifiedHead(root);
    final chain = <Object?>[];
    var current = selected;
    while (current != null) {
      final file = File('$root/assurance-history/records/$current.json');
      final record = jsonDecode(file.readAsStringSync());
      chain.add(record);
      current = ((record as Map)['body'] as Map?)?['previousRecord'] as String?;
    }
    File(output).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
            'kind': 'zuke.behavioral-assurance-release-export',
            'chain': chain,
          }) +
          '\n',
    );
  }

  static String _gitState(String root) {
    try {
      final result = Process.runSync('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: root);
      return (result.stdout as String).trim();
    } catch (_) {
      return 'unknown';
    }
  }

  static void _rejectLegacyHistoryLayout(String root) {
    final history = Directory('$root/assurance-history');
    final legacyPaths = <String>[];
    if (history.existsSync()) {
      const currentDirectories = {'records', 'trust', 'attestations'};
      for (final entity in history.listSync(followLinks: false)) {
        final name = entity.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last;
        if (entity is Directory && currentDirectories.contains(name)) {
          continue;
        }
        legacyPaths.add(entity.path);
      }
      final legacyVerifier = File('${history.path}/trust/verifier.json');
      if (legacyVerifier.existsSync() &&
          !legacyPaths.contains(legacyVerifier.path)) {
        legacyPaths.add(legacyVerifier.path);
      }
    }
    if (legacyPaths.isEmpty) return;
    throw FormatException(
      'ZK-HISTORY-LEGACY-FORMAT: legacy assurance history was found at '
      '${legacyPaths.join(', ')}. Move it out of assurance-history and '
      'regenerate current records using docs/migration.md.',
    );
  }

  static void _requireCleanRepository(String root) {
    final result = Process.runSync('git', [
      'status',
      '--porcelain',
    ], workingDirectory: root);
    if (result.exitCode != 0) {
      throw const FormatException('Unable to determine repository state');
    }
    if (result.stdout.toString().trim().isNotEmpty) {
      throw const FormatException(
        'Release creation requires a clean tracked repository',
      );
    }
  }

  static Future<String> _computeHash(String root, String relative) async {
    final directory = Directory('$root${Platform.pathSeparator}$relative');
    if (!directory.existsSync()) {
      return 'sha256:${sha256.convert(utf8.encode('empty'))}';
    }
    final rootPath = root.replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '');
    final files =
        directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final bytes = <int>[];
    for (final file in files) {
      final normalized = file.path.replaceAll('\\', '/');
      final path = normalized.startsWith('$rootPath/')
          ? normalized.substring(rootPath.length + 1)
          : normalized;
      bytes.addAll(utf8.encode(path));
      bytes.add(0);
      bytes.addAll(canonicalDigestBytes(path, file.readAsBytesSync()));
      bytes.add(0);
    }
    return 'sha256:${sha256.convert(bytes)}';
  }

  // Current release history is the only supported history layout.
  // Legacy layouts are rejected before any command reads the workspace.
}
