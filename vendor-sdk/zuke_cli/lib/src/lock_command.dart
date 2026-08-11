import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:args/args.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_core/zuke_core.dart';

import 'extraction_service.dart';
import 'attestation_verification.dart';
import 'scenario_selection.dart';
import 'generator.dart';
import 'proof_engine.dart';

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

  LockCommand(this.args);

  Future<int> execute() async {
    final allProfiles = args.options.contains('all-profiles') &&
        (args['all-profiles'] as bool? ?? false);
    if (allProfiles) {
      var result = 0;
      for (final profile in const [
        'pullRequest',
        'merge',
        'release',
        'nightly',
      ]) {
        final profileArgs = ArgParser()
          ..addOption('root')
          ..addOption('profile')
          ..addFlag('check')
          ..addFlag('quiet');
        final values = <String>[
          '--root',
          args['root'] as String? ?? Directory.current.path,
          '--profile',
          profile,
          if (args['check'] as bool? ?? false) '--check',
          if (args.options.contains('quiet') && (args['quiet'] as bool? ?? false))
            '--quiet',
        ];
        result |= await LockCommand(profileArgs.parse(values)).execute();
      }
      return result;
    }
    final root = Directory(
      Directory(
        args['root'] as String? ?? Directory.current.path,
      ).absolute.resolveSymbolicLinksSync(),
    );
    final workspace = WorkspaceDiscovery().discover(root.path);
    final profile = args['profile'] as String? ?? 'pullRequest';
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
    final lockContent = await buildLock(context, validation, profile: profile);
    final path = _lockPath(root.path, workspace, profile);
    final file = File(path);
    final check = args['check'] as bool? ?? false;
    final quiet =
        args.options.contains('quiet') && (args['quiet'] as bool? ?? false);
    if (check) {
      final current = file.existsSync() ? file.readAsStringSync() : null;
      if (current != lockContent) {
        stderr.writeln('Specification lock is stale or missing: $path');
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
          : '${proof.requirementId}|${proof.controlId}|${proof.target}|${proof.variant}';
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
        'sha256:${sha256.convert(utf8.encode(const JsonEncoder().convert(evidenceRequirements)))}';

    final data = <String, dynamic>{
      'schemaVersion': 'zuke.lock.v2',
      'formatVersion': 2,
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
      'requirements': workspace.data.features
          .expand((feature) => feature.rules)
          .where((rule) => rule.metadata.id != null)
          .map((rule) => rule.metadata.id)
          .toList(),
      'attestations': _attestations(workspace, validation.controlProofs),
      'controls': controlAssurance,
    };
    return const JsonEncoder.withIndent('  ').convert(data) + '\n';
  }

  String _lockPath(
    String root,
    WorkspaceDiscoveryResult workspace,
    String profile,
  ) {
    final configured = workspace.config.lockFile;
    final configFile = File('$root/zuke.yaml');
    if (configFile.existsSync()) {
      final content = configFile.readAsStringSync();
      if (content.contains('schemaVersion: 3') ||
          content.contains('directory: assurance/locks')) {
        final directory = RegExp(r'(?m)^\s*directory:\s*([^\s#]+)')
            .firstMatch(content)
            ?.group(1) ??
            'assurance/locks';
        return '$root/${directory.replaceAll('\\', '/')}/$profile.lock.json';
      }
    }
    return '$root/${configured ?? 'zuke.lock.json'}';
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
