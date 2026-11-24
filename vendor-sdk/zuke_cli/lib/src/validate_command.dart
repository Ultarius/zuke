import 'dart:io';
import 'dart:convert';

import 'package:args/args.dart';
import 'package:zuke_core/zuke_core.dart';

import 'extraction_service.dart';
import 'attestation_verification.dart';
import 'cli_parser.dart';
import 'scenario_selection.dart';
import 'workspace_annotation_scan.dart';
import 'diagnostic_text.dart';
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
    final quiet = boolFlag(args, 'quiet');
    final silent = boolFlag(args, 'silent');
    final requireEvidence = boolFlag(args, 'require-evidence');
    final workspace = requireCurrentWorkspace(root);
    // Shape normalization resolves declared binding names; build the list once.
    final bindingNames = bindingNamesOf(workspace);

    void info(String message) {
      if (!silent && !jsonMode && !quiet) stdout.writeln(message);
    }

    /// A finding line. [silent] suppresses findings too: `lock --refresh` uses
    /// the command as a probe and validates again after the tests, so echoing
    /// them here would print every finding twice.
    void finding(String line) {
      if (!silent) stderr.writeln(line);
    }

    info('Discovering workspace...');
    info('  Features: ${workspace.data.features.length}');
    info('  Epics: ${workspace.data.epics.length}');
    info('  Controls: ${workspace.data.controls.length}');
    info('  Registries: ${workspace.data.registries.length}');

    final extraction = await ExtractionService().extract(workspace);
    for (final error in extraction.errors) {
      finding('  ERROR: $error');
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
    // Only resolved when the workspace opted in: the scan is a full resolver
    // pass, and a workspace that has not asked whether a scenario test exists
    // should not pay to find out that it does not. The opt-in is read through
    // the same accessor the validator uses, so the two cannot disagree about
    // whether this pass was worth taking.
    final bindingCoverageEnabled =
        declaredBindingCoverageSeverity(workspace) != null;
    final managedScenarioScan = bindingCoverageEnabled
        ? await scanWorkspaceAnnotations(root, workspace)
        : null;
    if (managedScenarioScan != null) {
      info(
        '  Scenario bindings: ${managedScenarioScan.managedScenarios.length} '
        'registered, '
        '${managedScenarioScan.unresolvedManagedRegistrations} unresolved',
      );
    }
    final result = ValidatorEngine().validate(
      workspace,
      outputs: extraction.outputs,
      evidenceRecords: extraction.evidenceRecords,
      verifiedAttestationProofs: verifiedAttestations,
      profile: profile,
      selectedScenarioIds: selection.tagExpression == null
          ? null
          : selection.scenarioIds,
      managedScenarioScan: managedScenarioScan,
    );
    for (final line in renderValidationMessages(
      result.errors,
      label: 'ERROR',
      bindingNames: bindingNames,
    ).lines) {
      finding(line);
    }
    for (final msg in result.errors) {
      collectedDiagnostics.add(_validationDiagnostic(msg));
    }
    for (final line in renderValidationMessages(
      result.warnings,
      label: 'WARNING',
      bindingNames: bindingNames,
    ).lines) {
      finding(line);
    }
    for (final msg in result.warnings) {
      collectedDiagnostics.add(
        _validationDiagnostic(msg, severity: DiagnosticSeverity.warning),
      );
    }
    // Informational findings are findings, not progress. They render through
    // the same channel as warnings so `--quiet`, which suppresses progress,
    // still shows them, and `--silent`, which suppresses findings, still
    // suppresses them. A finding that only reached the JSON report would be
    // invisible in the mode most people run.
    for (final line in renderValidationMessages(
      result.infos,
      label: 'INFO',
      bindingNames: bindingNames,
    ).lines) {
      finding(line);
    }
    for (final msg in result.infos) {
      collectedDiagnostics.add(
        _validationDiagnostic(msg, severity: DiagnosticSeverity.info),
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
          (output.packageName ?? output.adapter.id): output
              .requirePublishedSourceDigest(),
      },
    );
    final profileEvidence = extraction.evidenceRecords.where(
      (record) => record.profile == profile,
    );
    final missingEvidence = requireEvidence && profileEvidence.isEmpty;
    final untestedMessage =
        'profile $profile has no executed evidence to validate';
    final passed =
        result.passed &&
        report.eligible &&
        extraction.errors.isEmpty &&
        !missingEvidence;
    if (missingEvidence) {
      // A distinct code from the validator's ZUKE-SCENARIO-UNTESTED, which
      // means "a selected scenario never executed" for an existing profile.
      finding('  ERROR: [ZUKE-PROFILE-UNTESTED] $untestedMessage');
      collectedDiagnostics.add(
        Diagnostic(
          code: 'ZUKE-PROFILE-UNTESTED',
          stage: 'validate',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.project,
          message: untestedMessage,
          remediation:
              'Run `zuke test --root $root --profile $profile` to execute it.',
        ),
      );
    }
    if (!report.eligible) {
      // The report restates many validation errors as eligibility reasons;
      // skip the ones the grouped output above already printed, once each.
      for (final reason in unprintedReasons(
        result.errors,
        report.ineligibilityReasons,
        alreadyReported: collectedDiagnostics.map(
          (diagnostic) => diagnostic.message,
        ),
      )) {
        finding('  ERROR: $reason');
        collectedDiagnostics.add(
          _textDiagnostic(
            reason,
            fallbackCode: 'ZK-VALIDATE-INELIGIBLE',
            severity: DiagnosticSeverity.error,
          ),
        );
      }
    }
    if (jsonMode && !silent) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          ...report.toJson(),
          'topologyOutputs': extraction.topologyOutputs
              .map((output) => output.toJson())
              .toList(),
          'status': passed ? 'passed' : 'failed',
          'errors': [
            // Extraction failures stay plain strings for backwards
            // compatibility; everything this command raises itself uses the
            // validator's `{code, message, severity}` shape.
            ...extraction.errors,
            ...result.errors.map((e) => e.toJson()),
            if (missingEvidence)
              {
                'code': 'ZUKE-PROFILE-UNTESTED',
                'message': untestedMessage,
                'severity': 'error',
                'remediation':
                    'Run `zuke test --root $root --profile $profile` to '
                    'execute it.',
              },
          ],
          'warnings': result.warnings.map((e) => e.toJson()).toList(),
          'infos': result.infos.map((e) => e.toJson()).toList(),
        }),
      );
      if (extraction.errors.any((error) => error.startsWith('ZUKE-EXTRACT-'))) {
        return 3;
      }
      return passed ? 0 : 1;
    }
    if (!quiet && !silent) {
      stdout.writeln('Validation ${passed ? "PASSED" : "FAILED"}');
      stdout.writeln(
        '  Errors: '
        '${result.errors.length + extraction.errors.length + (missingEvidence ? 1 : 0)}',
      );
      stdout.writeln('  Warnings: ${result.warnings.length}');
      if (result.infos.isNotEmpty) {
        stdout.writeln('  Info: ${result.infos.length}');
      }
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
    remediation:
        message.remediation ??
        defaultRemediation(message.code) ??
        'Inspect the validation report and resolve this finding.',
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
      remediation:
          defaultRemediation(match?.group(1) ?? fallbackCode) ??
          'Inspect the validation report and resolve this finding.',
    );
  }
}
