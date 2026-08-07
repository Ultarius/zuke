import 'dart:io';

import 'package:args/args.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_core/zuke_core.dart' show ProofStatus;

import 'extraction_service.dart';
import 'proof_engine.dart';
import 'reporter.dart';

class TraceCommand {
  final ArgResults args;
  TraceCommand(this.args);

  Future<int> execute() async {
    final requirementId = args.rest.isNotEmpty ? args.rest.first : null;
    if (requirementId == null || requirementId.isEmpty) {
      stderr.writeln('Usage: zuke trace RULE-ID');
      return 1;
    }
    final root = Directory(
      args['root'] as String? ?? Directory.current.path,
    ).absolute.resolveSymbolicLinksSync();
    final workspace = WorkspaceDiscovery().discover(root);
    final extraction = await ExtractionService().extract(workspace);
    final matching = <(ParsedFeature, ParsedRule)>[];
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        if (rule.metadata.id == requirementId) {
          matching.add((feature, rule));
        }
      }
    }
    if (matching.isEmpty) {
      stderr.writeln('Unknown requirement: $requirementId');
      return 1;
    }
    final validation = ValidatorEngine().validate(
      workspace,
      outputs: extraction.outputs,
      evidenceRecords: extraction.evidenceRecords,
    );
    final report = validation.toReport(
      evidence: extraction.evidenceRecords,
      requiredEvidence: validation.requiredEvidence,
    );
    final selected = matching.single;
    final symbols = extraction.outputs.expand((output) => output.symbols);
    List<String> mappings(String kind) => symbols
        .where(
          (symbol) =>
              symbol.kind == kind &&
              symbol.requirementIds.contains(requirementId),
        )
        .map((symbol) => '[${symbol.role}] ${symbol.symbolId}')
        .toList();
    final controls = <String>{
      for (final control in selected.$2.metadata.requires ?? const [])
        control.id,
    }.toList()..sort();
    stdout.write(
      renderRequirementTrace(
        RequirementTrace(
          requirementId: requirementId,
          definedBy:
              '${selected.$1.featureElement.source.file}:${selected.$2.ruleElement.source.line}',
          implementations: mappings('requirementBoundary'),
          presentations: mappings('presentationBoundary'),
          verifications: mappings('verificationBoundary'),
          requiredControls: controls,
          report: report,
        ),
      ),
    );
    final relevantProofs = report.controlProofs
        .where((proof) => proof.requirementId == requirementId)
        .toList();
    final eligible =
        relevantProofs.isNotEmpty &&
        relevantProofs.every(
          (proof) =>
              proof.status == ProofStatus.proven ||
              proof.status == ProofStatus.verified ||
              proof.status == ProofStatus.attested,
        ) &&
        extraction.errors.isEmpty;
    return eligible ? 0 : 1;
  }
}
