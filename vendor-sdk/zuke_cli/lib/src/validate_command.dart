import 'dart:io';
import 'dart:convert';

import 'package:args/args.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'extraction_service.dart';
import 'attestation_verification.dart';
import 'scenario_selection.dart';
import 'proof_engine.dart';

class ValidateCommand {
  final ArgResults args;

  ValidateCommand(this.args);

  Future<int> execute() async {
    final root = args['root'] as String? ?? Directory.current.path;
    final profile = args['profile'] as String? ?? 'pullRequest';
    final jsonMode = (args['format'] as String? ?? 'text') == 'json';
    final quiet = args['quiet'] as bool? ?? false;
    var workspace = WorkspaceDiscovery().discover(root);

    void info(String message) {
      if (!jsonMode && !quiet) stdout.writeln(message);
    }

    info('Discovering workspace...');
    info('  Features: ${workspace.data.features.length}');
    info('  Epics: ${workspace.data.epics.length}');
    info('  Controls: ${workspace.data.controls.length}');
    info('  Registries: ${workspace.data.registries.length}');

    final extraction = await ExtractionService().extract(workspace);
    for (final error in extraction.errors) {
      stderr.writeln('  ERROR: $error');
    }

    info('Validating...');
    final verifiedAttestations = await AttestationVerification().verify(
      workspace,
    );
    final selection = const ScenarioSelector().resolve(workspace, profile);
    final result = ValidatorEngine().validate(
      workspace,
      outputs: extraction.outputs,
      evidenceRecords: extraction.evidenceRecords,
      verifiedAttestationProofs: verifiedAttestations,
      profile: profile,
      selectedScenarioIds: selection.tagExpression == null
          ? null
          : selection.scenarioIds,
    );
    for (final msg in result.errors) {
      stderr.writeln('  ERROR: $msg');
    }
    for (final msg in result.warnings) {
      stderr.writeln('  WARNING: $msg');
    }

    final passed = result.passed && extraction.errors.isEmpty;
    final report = result.toReport(
      evidence: extraction.evidenceRecords
          .where((record) => record.profile == profile)
          .toList(),
      workspace: root.replaceAll('\\', '/'),
      profile: profile,
      requiredEvidence: result.requiredEvidence,
      adapterHashes: {
        for (final output in extraction.outputs)
          (output.packageName ?? output.adapter.id):
              'sha256:${output.inputDigest}',
      },
    );
    if (jsonMode) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          ...report.toJson(),
          'status': passed ? 'passed' : 'failed',
          'errors': [
            ...extraction.errors,
            ...result.errors.map((e) => e.toJson()),
          ],
          'warnings': result.warnings.map((e) => e.toJson()).toList(),
        }),
      );
      if (extraction.errors.any((error) => error.startsWith('ZUKE-EXTRACT-'))) {
        return 3;
      }
      return passed ? 0 : 1;
    }
    if (!quiet) {
      stdout.writeln('Validation ${passed ? "PASSED" : "FAILED"}');
      stdout.writeln(
        '  Errors: ${result.errors.length + extraction.errors.length}',
      );
      stdout.writeln('  Warnings: ${result.warnings.length}');
    }
    if (extraction.errors.any((error) => error.startsWith('ZUKE-EXTRACT-'))) {
      return 3;
    }
    return passed ? 0 : 1;
  }
}
