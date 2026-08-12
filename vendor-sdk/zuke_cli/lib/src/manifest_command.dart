import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:args/args.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
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
    final lock = File(
      resolveProfileLockPath(workspaceRoot.path, workspace, profile),
    );
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
      final headFile = File('$root/assurance-history/records/$existingHead.json');
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
      if (value is! Map) throw StateError('Invalid current record: ${file.path}');
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
    if (heads.length > 1) throw StateError('Multiple record chain heads: $heads');
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
      final lock = File(
        resolveProfileLockPath(root, workspace, 'release'),
      );
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

  static Future<void> export(
    String root,
    String output, {
    String? head,
  }) async {
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

  /*
  // Retained below solely as historical verification/reference code. New
  // execution must never extend the v1 chain.
  static Future<String> _legacyWrite(
    WorkspaceDiscoveryResult workspace,
    WorkspaceExtraction extraction,
  ) async {
    final root = workspace.config.root!;
    final requirements = <Map<String, dynamic>>[];
    final evidence = <Map<String, dynamic>>[];
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final id = rule.metadata.id;
        if (id == null) continue;
        final implementations = extraction.outputs
            .expand((output) => output.symbols)
            .where((symbol) => symbol.requirementIds.contains(id))
            .map(
              (symbol) => {
                'role': symbol.role,
                'symbolId': symbol.symbolId,
                'source': '${symbol.source.uri}:${symbol.source.line}',
              },
            )
            .toList();
        final controls = (rule.metadata.requires ?? const <ParsedControlRef>[])
            .map(
              (control) => {
                'id': control.id,
                'target': control.target,
                'assurance': _assurance(workspace, extraction, control.id),
              },
            )
            .toList();
        requirements.add({
          'id': id,
          'feature': feature.metadata.id,
          'implementations': implementations,
          'controls': controls,
          'requiredEvidence': rule.metadata.requiredEvidence ?? const [],
        });
        final evidenceStatus =
            (rule.metadata.requiredEvidence ?? const <String>[])
                .map(
                  (type) => {
                    'type': type,
                    'status': _evidenceStatus(
                      type,
                      feature,
                      rule,
                      workspace,
                      extraction,
                    ),
                  },
                )
                .toList();
        evidence.add({
          'requirement': id,
          'required': rule.metadata.requiredEvidence ?? const [],
          'status': evidenceStatus.every((entry) => entry['status'] == 'PASS')
              ? 'PASS'
              : 'FAIL',
          'checks': evidenceStatus,
        });
      }
    }
    final workspaceName = Directory(
      root,
    ).uri.pathSegments.where((s) => s.isNotEmpty).last;
    final body = <String, dynamic>{
      'kind': 'zuke.behavioral-assurance-manifest',
      'workspace': workspaceName,
      'requirements': requirements,
      'evidence': evidence,
      'fragments': extraction.outputs
          .map(
            (output) => {
              'adapter': output.adapter.id,
              'package': output.packageName,
              'digest': 'sha256:${output.inputDigest}',
            },
          )
          .toList(),
      'previous': _previousDigest(root),
    };
    final existing = _findIdentical(root, body);
    if (existing != null) return existing;
    final canonical = const JsonEncoder().convert(body);
    final signature = Hmac(
      sha256,
      utf8.encode(_key()),
    ).convert(utf8.encode(canonical)).toString();
    final manifest = <String, dynamic>{
      ...body,
      'signature': {'algorithm': 'HMAC-SHA256', 'value': signature},
    };
    final manifestJson =
        const JsonEncoder.withIndent('  ').convert(manifest) + '\n';
    final digest = sha256.convert(utf8.encode(manifestJson)).toString();
    final manifestPath = '$root/assurance-history/manifests/$digest.json';
    final file = File(manifestPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(manifestJson);
    final trust = File('$root/assurance-history/trust/verifier.json');
    trust.parent.createSync(recursive: true);
    trust.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
            'schemaVersion': 1,
            'algorithm': 'HMAC-SHA256',
            'keyId': 'local-development-key',
          }) +
          '\n',
    );
    // Evidence is accepted only from atomic execution records. Do not emit a
    // hand-authored aggregate report that could be mistaken for test output.
    final export = File('$root/assurance-history/export.json');
    export.parent.createSync(recursive: true);
    final manifests =
        Directory('$root/assurance-history/manifests')
            .listSync()
            .whereType<File>()
            .map((file) => file.path.split(Platform.pathSeparator).last)
            .where((name) => name.endsWith('.json'))
            .toList()
          ..sort();
    export.writeAsStringSync(
      const JsonEncoder.withIndent(
            '  ',
          ).convert({'schemaVersion': 1, 'manifests': manifests}) +
          '\n',
    );
    return manifestPath;
  }

  static String _assurance(
    WorkspaceDiscoveryResult workspace,
    WorkspaceExtraction extraction,
    String controlId,
  ) {
    final validation = ValidatorEngine().validate(
      workspace,
      outputs: extraction.outputs,
    );

    final proofs = validation.controlProofs
        .where((proof) => proof.controlId == controlId)
        .toList();
    if (proofs.any((proof) => proof.status == ProofStatus.failed)) {
      return 'FAILED';
    }
    if (proofs.any((proof) => proof.status == ProofStatus.indeterminate)) {
      return 'INDETERMINATE';
    }
    if (proofs.any((proof) => proof.status == ProofStatus.expired)) {
      return 'EXPIRED';
    }
    if (proofs.any((proof) => proof.status == ProofStatus.attested)) {
      return 'ATTESTED';
    }
    if (proofs.any((proof) => proof.status == ProofStatus.proven)) {
      return 'PROVEN';
    }
    if (proofs.any((proof) => proof.status == ProofStatus.verified)) {
      return 'VERIFIED';
    }

    // A provider declaration is only a candidate. It cannot produce an
    // assurance state without a proof result from ValidatorEngine.
    return 'MISSING';
  }

  static String _evidenceStatus(
    String type,
    ParsedFeature feature,
    ParsedRule rule,
    WorkspaceDiscoveryResult workspace,
    WorkspaceExtraction extraction,
  ) {
    final id = rule.metadata.id;
    final records = extraction.outputs
        .expand((o) => o.evidenceRecords)
        .whereType<SemanticEvidenceRecord>();
    bool executed(String evidenceType, String target) => records.any(
      (record) =>
          record.requirementId == id &&
          record.evidenceType == evidenceType &&
          record.target == target &&
          record.status == EvidenceStatus.passed,
    );
    switch (type) {
      case 'domain-unit':
        return executed(type, 'backend') ? 'PASS' : 'MISSING';
      case 'flutter-widget':
      case 'accessibility-integration':
        return executed(type, 'flutter') ? 'PASS' : 'MISSING';
      case 'api-contract':
        return executed(type, 'backend') ? 'PASS' : 'MISSING';
      case 'performance':
        return executed(type, 'backend') ? 'PASS' : 'MISSING';
      case 'gherkin-api':
        return executed(type, 'backend') ? 'PASS' : 'MISSING';
      case 'gherkin-ui':
        return executed(type, 'flutter') ? 'PASS' : 'MISSING';
      case 'security-integration':
        final validation = ValidatorEngine().validate(
          workspace,
          outputs: extraction.outputs,
        );
        final okay = (rule.metadata.requires ?? const <ParsedControlRef>[])
            .every(
              (control) => validation.controlProofs.any(
                (proof) =>
                    proof.controlId == control.id &&
                    (proof.status == ProofStatus.proven ||
                        proof.status == ProofStatus.verified ||
                        proof.status == ProofStatus.attested),
              ),
            );
        return okay ? 'PASS' : 'MISSING';
      case 'logging-verification':
        return executed(type, 'backend') ? 'PASS' : 'MISSING';
      case 'attestation-freshness':
        return (rule.metadata.requires ?? const <ParsedControlRef>[]).any(
              (control) =>
                  _assurance(workspace, extraction, control.id) == 'ATTESTED',
            )
            ? 'PASS'
            : 'MISSING';
      default:
        return 'MISSING';
    }
  }

  static String? _previousDigest(String root) {
    final directory = Directory('$root/assurance-history/manifests');
    if (!directory.existsSync()) return null;
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList();
    if (files.isEmpty) return null;
    final ids = <String>{};
    final referenced = <String>{};
    for (final file in files) {
      final id = file.path
          .split(Platform.pathSeparator)
          .last
          .replaceAll('.json', '');
      ids.add(id);
      try {
        final value = jsonDecode(file.readAsStringSync());
        if (value is Map && value['previous'] is String) {
          referenced.add(value['previous'] as String);
        }
      } catch (_) {
        throw StateError('Invalid assurance manifest: ${file.path}');
      }
    }
    final heads = ids.difference(referenced).toList()..sort();
    if (heads.length > 1) {
      throw StateError('Assurance history has multiple chain heads: $heads');
    }
    return heads.isEmpty ? null : heads.single;
  }

  static String _key({String? supplied}) {
    final key = supplied ?? Platform.environment['ZUKE_SIGNING_KEY'];
    if (key == null || key.isEmpty) {
      throw FormatException('An explicit legacy HMAC key is required');
    }
    return key;
  }

  static String? _findIdentical(String root, Map<String, dynamic> body) {
    final directory = Directory('$root/assurance-history/manifests');
    if (!directory.existsSync()) return null;
    final identity = Map<String, dynamic>.from(body)..remove('previous');
    final expected = const JsonEncoder().convert(identity);
    for (final file in directory.listSync().whereType<File>()) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is! Map) continue;
        final candidate = Map<String, dynamic>.from(decoded)
          ..remove('previous')
          ..remove('signature');
        if (const JsonEncoder().convert(candidate) == expected)
          return file.path;
      } catch (_) {}
    }
    return null;
  }

  static bool verify(String path, {String? legacyKey}) {
    final value =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final signature = (value.remove('signature') as Map)['value'] as String;
    value.remove('observedAt');
    final canonical = const JsonEncoder().convert(value);
    final expected = Hmac(
      sha256,
      utf8.encode(_key(supplied: legacyKey)),
    ).convert(utf8.encode(canonical)).toString();
    return signature == expected;
  }

  static Future<String> _computeHash(String root, String kind) async {
    final dir = Directory('$root/$kind');
    if (!dir.existsSync()) return 'sha256:${sha256.convert(utf8.encode('empty')).toString()}';
    final parts = <int>[];
    final files = dir.listSync(recursive: true).whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      parts.addAll(utf8.encode(file.path.replaceAll('\\', '/')));
      parts.addAll(file.readAsBytesSync());
    }
    return 'sha256:${sha256.convert(parts).toString()}';
  }
  */
}
