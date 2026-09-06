import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:args/args.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'extraction_service.dart';
import 'attestation_verification.dart';
import 'scenario_selection.dart';
import 'generator.dart';
import 'proof_engine.dart';
import 'ir.dart';
import 'lock_path.dart';
import 'configuration_preflight.dart';

/// Immutable inputs for one lock calculation.
///
/// The physical root is resolved once by the command entry point so lock
/// construction cannot accidentally consult a different CLI argument later.
final class WorkspaceContext {
  final Directory root;
  final WorkspaceDiscoveryResult workspace;
  final WorkspaceExtraction extraction;

  const WorkspaceContext({
    required this.root,
    required this.workspace,
    required this.extraction,
  });
}

class LockCommand {
  final ArgResults args;
  List<Diagnostic> diagnostics = const [];

  LockCommand(this.args);

  Future<int> execute() async {
    diagnostics = const [];
    final requestedRoot = args['root'] as String? ?? Directory.current.path;
    final check = args['check'] as bool? ?? false;
    final update =
        args.options.contains('update') && (args['update'] as bool? ?? false);
    if (check && update) {
      throw const FormatException(
        'lock --check and lock --update are mutually exclusive',
      );
    }
    final allProfiles =
        args.options.contains('all-profiles') &&
        (args['all-profiles'] as bool? ?? false);
    final profile = args['profile'] as String?;
    final selectedProfiles = args.options.contains('profiles')
        ? args['profiles'] as List<String>
        : const <String>[];
    if (selectedProfiles.isNotEmpty) {
      if (allProfiles || profile != null) {
        throw const FormatException(
          'Profile selection flags are mutually exclusive',
        );
      }
      final configured = _configuredProfiles(requestedRoot);
      if (selectedProfiles.any((value) => !configured.contains(value))) {
        throw const FormatException('Requested profile is not configured');
      }
      return _executeProfiles(
        requestedRoot,
        profiles: selectedProfiles.toSet().toList(),
        transactional: update,
        checkOnly: check,
      );
    }
    if (allProfiles && profile != null) {
      throw const FormatException(
        'lock --all-profiles and --profile are mutually exclusive',
      );
    }
    final refreshAll = update && !allProfiles && profile == null;
    if (allProfiles || refreshAll) {
      return _executeProfiles(
        requestedRoot,
        profiles: _configuredProfiles(requestedRoot),
        transactional: update,
        checkOnly: check,
      );
    }
    final root = Directory(
      Directory(
        args['root'] as String? ?? Directory.current.path,
      ).absolute.resolveSymbolicLinksSync(),
    );
    final legacyLockPaths = [
      File(resolveLegacyRootLockPath(root.path)),
      File('${root.path}/zuke.lock'),
    ];
    final legacyLock = legacyLockPaths.firstWhere(
      (file) => file.existsSync(),
      orElse: () => File(''),
    );
    if (legacyLock.path.isNotEmpty) {
      diagnostics = [
        Diagnostic(
          code: 'ZK-LOCK-LEGACY-FORMAT',
          stage: 'lock',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.zuke,
          message: '${legacyLock.path} is a legacy lock path.',
          remediation:
              'Remove the legacy lock and regenerate the current profile lock.',
        ),
      ];
      stderr.writeln(
        'ZK-LOCK-LEGACY-FORMAT: ${legacyLock.path} is a legacy lock path; '
        'remove it and regenerate assurance/locks/<profile>.lock.json with '
        'the current Zuke CLI.',
      );
      return 1;
    }
    final workspace = requireCurrentWorkspace(root.path);
    final profileName = profile ?? 'pullRequest';
    final extraction = await ExtractionService().extract(workspace);
    final verifiedAttestations = await AttestationVerification().verify(
      workspace,
    );
    final selection = const ScenarioSelector().resolve(workspace, profileName);
    final validation = ValidatorEngine().validate(
      workspace,
      outputs: extraction.outputs,
      evidenceRecords: extraction.evidenceRecords,
      verifiedAttestationProofs: verifiedAttestations,
      profile: profileName,
      selectedScenarioIds: selection.tagExpression == null
          ? null
          : selection.scenarioIds,
    );
    final report = validation.toReport(
      evidence: extraction.evidenceRecords
          .where((record) => record.profile == profileName)
          .toList(),
      requiredEvidence: validation.requiredEvidence,
      workspace: root.path,
    );
    if (extraction.errors.isNotEmpty || !report.eligible) {
      stderr.writeln(
        'Lock generation aborted: validation report is ineligible.',
      );
      for (final error in extraction.errors) {
        stderr.writeln('  ERROR: $error');
      }
      for (final error in validation.errors) {
        stderr.writeln('  ERROR: [${error.code}] ${error.message}');
      }
      for (final reason in report.ineligibilityReasons) {
        stderr.writeln('  ERROR: $reason');
      }
      return 1;
    }
    final context = WorkspaceContext(
      root: root,
      workspace: workspace,
      extraction: extraction,
    );
    final lockContent = await buildLock(
      context,
      validation,
      profile: profileName,
    );
    final output = args.options.contains('output')
        ? args['output'] as String?
        : null;
    final path = output != null && output.isNotEmpty
        ? output
        : resolveProfileLockPath(root.path, profileName);
    final file = File(path);
    final quiet =
        args.options.contains('quiet') && (args['quiet'] as bool? ?? false);
    if (check) {
      final current = file.existsSync() ? file.readAsStringSync() : null;
      if (current != null) {
        try {
          final decoded = jsonDecode(current);
          if (decoded is! Map ||
              decoded['kind'] != 'zuke.lock' ||
              decoded.containsKey('schemaVersion') ||
              decoded.containsKey('formatVersion')) {
            diagnostics = [_legacyLockDiagnostic()];
            stderr.writeln(
              'ZK-LOCK-LEGACY-FORMAT: the lock is not a current lock; regenerate it with the current Zuke CLI.',
            );
            return 1;
          }
        } on FormatException {
          diagnostics = [_legacyLockDiagnostic()];
          stderr.writeln(
            'ZK-LOCK-LEGACY-FORMAT: the lock is malformed; regenerate it with the current Zuke CLI.',
          );
          return 1;
        }
      }
      if (current != lockContent) {
        diagnostics = [
          Diagnostic(
            code: 'ZK-LOCK-STALE',
            stage: 'lock',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.project,
            message: 'Specification lock is stale or missing: $path',
            remediation:
                'Generate the profile lock in a reviewed change, then verify it with --check.',
          ),
        ];
        stderr.writeln(
          'ZK-LOCK-STALE: Specification lock is stale or missing: $path',
        );
        if (current != null) {
          stderr.writeln(
            '  expected sha256:${sha256.convert(utf8.encode(lockContent))}',
          );
          stderr.writeln(
            '  actual   sha256:${sha256.convert(utf8.encode(current))}',
          );
        }
        return 1;
      }
      if (!quiet) stdout.writeln('Specification lock is current.');
      return 0;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(lockContent);
    if (!quiet) stdout.writeln('Wrote $path');
    return 0;
  }

  Future<int> _executeProfiles(
    String requestedRoot, {
    required List<String> profiles,
    required bool transactional,
    required bool checkOnly,
  }) async {
    if (!transactional) {
      var result = 0;
      for (final profile in profiles) {
        result |= await _executeSingleProfile(
          requestedRoot,
          profile,
          check: checkOnly,
          update: false,
        );
      }
      return result;
    }

    final root = Directory(requestedRoot).absolute;
    final staging = Directory.systemTemp.createTempSync('zuke-lock-staging-');
    final snapshots = <String, List<int>?>{};
    for (final profile in profiles) {
      final path = resolveProfileLockPath(root.path, profile);
      snapshots[path] = File(path).existsSync()
          ? File(path).readAsBytesSync()
          : null;
    }
    try {
      for (final profile in profiles) {
        final stagedPath =
            '${staging.path}${Platform.pathSeparator}$profile.lock.json';
        final result = await _executeSingleProfile(
          requestedRoot,
          profile,
          output: stagedPath,
          update: true,
        );
        if (result != 0 || !File(stagedPath).existsSync()) {
          _restoreSnapshots(snapshots);
          return result == 0 ? 1 : result;
        }
      }
      for (final profile in profiles) {
        final stagedPath =
            '${staging.path}${Platform.pathSeparator}$profile.lock.json';
        final destination = File(resolveProfileLockPath(root.path, profile));
        destination.parent.createSync(recursive: true);
        destination.writeAsBytesSync(File(stagedPath).readAsBytesSync());
      }
      for (final profile in profiles) {
        final check = await _executeCheck(requestedRoot, profile);
        if (check != 0) {
          _restoreSnapshots(snapshots);
          return check;
        }
      }
      return 0;
    } catch (error) {
      _restoreSnapshots(snapshots);
      stderr.writeln('Lock refresh failed before completion: $error');
      return 1;
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
  }

  Future<int> _executeSingleProfile(
    String root,
    String profile, {
    bool check = false,
    bool update = false,
    String? output,
  }) async {
    final parser = ArgParser()
      ..addOption('root')
      ..addOption('profile')
      ..addOption('output')
      ..addFlag('check')
      ..addFlag('quiet')
      ..addFlag('update');
    return LockCommand(
      parser.parse([
        '--root',
        root,
        '--profile',
        profile,
        if (output != null) ...['--output', output],
        if (check) '--check',
        if (update) '--update',
      ]),
    ).execute();
  }

  Future<int> _executeCheck(String root, String profile) async {
    final parser = ArgParser()
      ..addOption('root')
      ..addOption('profile')
      ..addFlag('check')
      ..addFlag('quiet')
      ..addFlag('update');
    return LockCommand(
      parser.parse([
        '--root',
        root,
        '--profile',
        profile,
        '--check',
        '--quiet',
      ]),
    ).execute();
  }

  void _restoreSnapshots(Map<String, List<int>?> snapshots) {
    for (final entry in snapshots.entries) {
      final file = File(entry.key);
      final bytes = entry.value;
      if (bytes == null) {
        if (file.existsSync()) file.deleteSync();
      } else {
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
      }
    }
  }

  Diagnostic _legacyLockDiagnostic() => const Diagnostic(
    code: 'ZK-LOCK-LEGACY-FORMAT',
    stage: 'lock',
    severity: DiagnosticSeverity.error,
    owner: DiagnosticOwner.zuke,
    message: 'The lock is not a current lock artifact.',
    remediation:
        'Remove the legacy lock and regenerate the current profile lock.',
  );

  List<String> _configuredProfiles(String root) {
    try {
      final profiles = requireCurrentWorkspace(root).config.lock.profiles;
      if (profiles.isNotEmpty) return profiles;
    } on Object {
      // Let the normal single-profile path report the configuration failure.
    }
    return const ['pullRequest', 'merge', 'release', 'nightly'];
  }

  Future<String> buildLock(
    WorkspaceContext context,
    ValidationResult validation, {
    String profile = 'pullRequest',
  }) async {
    final root = context.root;
    final workspace = context.workspace;
    final extraction = context.extraction;
    final selection = const ScenarioSelector().resolve(workspace, profile);
    final workspaceName = root.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    final generator = DartContractGenerator();
    final generated = generator.generate(
      workspace: workspace,
      outputDir: workspace.config.contractOutput ?? 'lib/src/generated',
      exportPath: workspace.config.contractExport,
    );
    final fragments =
        extraction.outputs
            .map(
              (output) => {
                'adapter': output.adapter.id,
                'version': output.adapter.version,
                'compatibilityId': output.adapter.compatibilityId,
                'package': output.packageName,
                'digest': 'sha256:${output.inputDigest}',
                'completeness': output.completeness.toJson(),
              },
            )
            .toList()
          ..sort((a, b) => '${a['package']}'.compareTo('${b['package']}'));

    final featureHashes = <String, String>{};
    for (final feat in workspace.data.features) {
      final featId = feat.metadata.id ?? feat.featureElement.title;
      final file = File(feat.metadata.source.file);
      if (file.existsSync()) {
        featureHashes[featId] =
            'sha256:${sha256.convert(canonicalDigestBytes(file.path, file.readAsBytesSync()))}';
      }
    }

    final policyPreset = workspace.config.preset ?? 'secure-product-v1';
    final sortedControls = workspace.data.controls.keys.toList()..sort();
    final controlsJsonList = [
      for (final key in sortedControls)
        {
          'id': key,
          'control': _canonicalMap(
            workspace.data.controls[key] ?? const {},
            stripDiscoveryMetadata: true,
          ),
        },
    ];
    final policyValues =
        workspace.data.policies.values.map(_canonicalMap).toList()
          ..sort((a, b) => canonicalJson(a).compareTo(canonicalJson(b)));
    final policyJson = canonicalJson({
      'policies': policyValues,
      'controls': controlsJsonList,
    });
    final evidenceRequirements = workspace.data.features
        .expand((feature) => feature.rules)
        .map(
          (rule) => {
            'id': rule.metadata.id,
            'requiredEvidence': rule.metadata.requiredEvidence ?? const [],
          },
        )
        .toList();
    final controlAssurance = <String, dynamic>{};
    final report = validation.toReport(
      evidence: extraction.evidenceRecords
          .where((record) => record.profile == profile)
          .toList(),
      requiredEvidence: validation.requiredEvidence,
      workspace: root.path,
      profile: profile,
    );
    final specificationDigest = WorkspaceDigest.computeInputContents(
      root,
      workspace.inputContents,
    );
    // A lock records proof results.  It must never upgrade an unverified
    // policy declaration into an attested assurance result.
    for (final proof in validation.controlProofs) {
      final key = proof.requirementId == null
          ? proof.controlId
          : '${proof.requirementId}|${proof.controlId}|${proof.target}|'
                '${proof.variant}|${proof.slot}';
      controlAssurance[key] = {
        'assurance': proof.status.name,
        'semantics': proof.semantics.wireValue,
        'providerIds': proof.providerIds,
        'evidenceDigests': proof.evidenceDigests,
        'coverage': proof.status.name,
        'graphHash': proof.governedGraphHash,
        'completeness': {
          for (final entry in proof.completeness.entries)
            entry.key: entry.value.name,
        },
        'bypassPaths': proof.bypassPaths,
      };
    }
    for (final controlId in workspace.data.controls.keys) {
      if (controlAssurance.keys.any(
        (key) => key.contains('|$controlId|') || key == controlId,
      )) {
        continue;
      }
      controlAssurance[controlId] = {
        'assurance': ProofStatus.missing.name,
        'coverageSemantics':
            workspace.data.controls[controlId]?['coverageSemantics'],
        'providerIds': const <String>[],
      };
    }

    final policyHash = 'sha256:${sha256.convert(utf8.encode(policyJson))}';
    final evidenceRequirementsHash =
        'sha256:${sha256.convert(utf8.encode(canonicalJson(evidenceRequirements)))}';

    final data = <String, dynamic>{
      'kind': 'zuke.lock',
      'profile': profile,
      'selectedScenarioIds': selection.scenarioIds,
      'selectionDigest': selection.digest,
      'engineVersion': report.engineVersion,
      'workspace': workspaceName,
      'policy': {
        'preset': policyPreset,
        'policyHash': policyHash,
        'evidenceRequirementsHash': evidenceRequirementsHash,
      },
      'policyHash': policyHash,
      'evidenceRequirementsHash': evidenceRequirementsHash,
      'specificationDigestScope': 'discovery-inputs-v1',
      'specificationDigest': 'sha256:$specificationDigest',
      'generatedManifestDigest':
          'sha256:${sha256.convert(utf8.encode(generated.manifest.toJson()))}',
      'features': {
        for (final entry in featureHashes.entries)
          entry.key: {'sourceHash': entry.value},
      },
      'fragments': fragments,
      'topologyOutputs': extraction.topologyOutputs
          .map((output) => output.toJson())
          .toList(),
      'requirements': workspace.data.features
          .expand((feature) => feature.rules)
          .where((rule) => rule.metadata.id != null)
          .map((rule) => rule.metadata.id)
          .toList(),
      'attestations': _attestations(workspace, validation.controlProofs),
      'implementationCoverage':
          (validation.implementationCoverage.toList()..sort(
                (left, right) => left.binding.key.compareTo(right.binding.key),
              ))
              .map((coverage) => coverage.toJson())
              .toList(),
      'controls': controlAssurance,
    };
    return const JsonEncoder.withIndent('  ').convert(data) + '\n';
  }

  List<Map<String, Object?>> _attestations(
    WorkspaceDiscoveryResult workspace,
    List<ControlProofResult> proofs,
  ) {
    final providers = <String, Map>{};
    for (final policy in workspace.data.policies.values) {
      for (final provider in (policy['providers'] as List? ?? const [])) {
        if (provider is Map && provider['id'] != null) {
          providers[provider['id'].toString()] = provider;
        }
      }
    }
    final rows = <Map<String, Object?>>[];
    for (final proof in proofs.where(
      (proof) => proof.status == ProofStatus.attested,
    )) {
      for (final providerId in proof.providerIds) {
        final provider = providers[providerId];
        if (provider == null) continue;
        final evidence = provider['evidence'] as Map?;
        rows.add({
          'providerId': providerId,
          'controlId': proof.controlId,
          'target': proof.target,
          'variant': proof.variant,
          'semantics': proof.semantics.wireValue,
          'issuedAt': provider['attestedAt'],
          'expiresAt': provider['expiresAt'],
          'evidenceDigest': evidence?['digest'],
          'document': provider['document'],
        });
      }
    }
    rows.sort(
      (a, b) => '${a['providerId']}|${a['controlId']}'.compareTo(
        '${b['providerId']}|${b['controlId']}',
      ),
    );
    return rows;
  }

  Map<String, Object?> _canonicalMap(
    Map<dynamic, dynamic> value, {
    bool stripDiscoveryMetadata = false,
  }) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException(
          'Policy/control object keys must be strings, got '
          '${entry.key.runtimeType}',
        );
      }
      final key = entry.key as String;
      if (stripDiscoveryMetadata && (key == '_file' || key == '_sourceList')) {
        continue;
      }
      result[key] = entry.value;
    }
    return result;
  }
}
