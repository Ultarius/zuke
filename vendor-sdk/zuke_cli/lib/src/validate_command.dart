import 'dart:io';
import 'dart:convert';

import 'package:args/args.dart';
import 'package:zuke_core/zuke_core.dart';

import 'extraction_service.dart';
import 'attestation_verification.dart';
import 'scenario_selection.dart';
import 'proof_engine.dart';
import 'configuration_preflight.dart';

class ValidateCommand {
  final ArgResults args;
  List<Diagnostic> diagnostics = const [];

  ValidateCommand(this.args);

  Future<int> execute() async {
    final collectedDiagnostics = <Diagnostic>[];
    diagnostics = collectedDiagnostics;
    final root = args['root'] as String? ?? Directory.current.path;
    final profile = args['profile'] as String? ?? 'pullRequest';
    final jsonMode = (args['format'] as String? ?? 'text') == 'json';
    final quiet = args['quiet'] as bool? ?? false;
    final workspace = requireCurrentWorkspace(root);

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
      collectedDiagnostics.add(
        _textDiagnostic(
          error,
          fallbackCode: 'ZK-VALIDATE-EXTRACTION',
          severity: DiagnosticSeverity.error,
        ),
      );
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
      collectedDiagnostics.add(_validationDiagnostic(msg));
    }
    for (final msg in result.warnings) {
      stderr.writeln('  WARNING: $msg');
      collectedDiagnostics.add(
        _validationDiagnostic(msg, severity: DiagnosticSeverity.warning),
      );
    }

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
    final passed =
        result.passed && report.eligible && extraction.errors.isEmpty;
    if (!report.eligible) {
      for (final reason in report.ineligibilityReasons) {
        stderr.writeln('  ERROR: $reason');
        if (!collectedDiagnostics.any(
          (diagnostic) => diagnostic.message == reason,
        )) {
          collectedDiagnostics.add(
            _textDiagnostic(
              reason,
              fallbackCode: 'ZK-VALIDATE-INELIGIBLE',
              severity: DiagnosticSeverity.error,
            ),
          );
        }
      }
    }
    if (jsonMode) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          ...report.toJson(),
          'topologyOutputs': extraction.topologyOutputs
              .map((output) => output.toJson())
              .toList(),
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

  Diagnostic _validationDiagnostic(
    ValidationMessage message, {
    DiagnosticSeverity? severity,
  }) => Diagnostic(
    code: message.code,
    stage: 'validate',
    severity:
        severity ??
        switch (message.severity) {
          Severity.error => DiagnosticSeverity.error,
          Severity.warning => DiagnosticSeverity.warning,
          Severity.info => DiagnosticSeverity.info,
        },
    owner: DiagnosticOwner.unknown,
    message: message.message,
    remediation: 'Inspect the validation report and resolve this finding.',
  );

  Diagnostic _textDiagnostic(
    String text, {
    required String fallbackCode,
    required DiagnosticSeverity severity,
  }) {
    final match = RegExp(r'^([A-Z][A-Z0-9-]+):\s*(.*)$').firstMatch(text);
    final matchedMessage = match?.group(2)?.trim();
    return Diagnostic(
      code: match?.group(1) ?? fallbackCode,
      stage: 'validate',
      severity: severity,
      owner: DiagnosticOwner.unknown,
      message: matchedMessage == null || matchedMessage.isEmpty
          ? text
          : matchedMessage,
      remediation: 'Inspect the validation report and resolve this finding.',
    );
  }
}
