/// CLI-owned trace and validation reporting implementation.
import 'dart:convert';
import 'package:zuke_core/zuke_core.dart';

/// Presentation-ready context for one governed requirement.  The reporter is
/// intentionally independent of the frontend and extractor packages; command
/// surfaces assemble this context from authoritative parsed/extracted data.
class RequirementTrace {
  final String requirementId;
  final String definedBy;
  final List<String> implementations;
  final List<String> presentations;
  final List<String> verifications;
  final List<String> requiredControls;
  final ValidationReport report;

  const RequirementTrace({
    required this.requirementId,
    required this.definedBy,
    required this.report,
    this.implementations = const [],
    this.presentations = const [],
    this.verifications = const [],
    this.requiredControls = const [],
  });
}

String renderRequirementTrace(RequirementTrace trace) {
  final buffer = StringBuffer('${trace.requirementId}\n\n');
  buffer.writeln('Defined by:');
  buffer.writeln('  ${trace.definedBy}');
  _writeSection(buffer, 'Implemented by', trace.implementations);
  _writeSection(buffer, 'Presented by', trace.presentations);
  _writeSection(buffer, 'Verified by', trace.verifications);
  _writeSection(buffer, 'Required controls', trace.requiredControls);

  final proofs =
      trace.report.controlProofs
          .where((proof) => proof.requirementId == trace.requirementId)
          .toList()
        ..sort((left, right) => left.controlId.compareTo(right.controlId));
  buffer.writeln('Controls:');
  if (proofs.isEmpty) {
    buffer.writeln('  <no proof produced>');
  }
  for (final proof in proofs) {
    buffer.writeln('  ${proof.controlId}');
    buffer.writeln('    assurance: ${proof.status.name.toUpperCase()}');
    buffer.writeln('    semantics: ${proof.semantics.wireValue}');
    if (proof.providerIds.isNotEmpty) {
      buffer.writeln('    providers: ${proof.providerIds.join(', ')}');
    }
    for (final path in proof.bypassPaths) {
      buffer.writeln('    bypass: $path');
    }
    for (final diagnostic in proof.diagnostics) {
      buffer.writeln('    diagnostic: $diagnostic');
    }
  }

  final evidence =
      trace.report.evidence
          .where((record) => record.requirementId == trace.requirementId)
          .toList()
        ..sort((left, right) {
          final leftKey = '${left.evidenceType}:${left.executionId}';
          final rightKey = '${right.evidenceType}:${right.executionId}';
          return leftKey.compareTo(rightKey);
        });
  buffer.writeln('Evidence:');
  if (evidence.isEmpty) {
    buffer.writeln('  <no evidence observed>');
  }
  for (final record in evidence) {
    buffer.writeln(
      '  ${record.evidenceType}: ${record.status.name.toUpperCase()} '
      '(${record.target}/${record.variant}, ${record.profile})',
    );
  }

  final eligible =
      proofs.every(
        (proof) =>
            proof.status == ProofStatus.proven ||
            proof.status == ProofStatus.verified ||
            proof.status == ProofStatus.attested,
      ) &&
      evidence.every((record) => record.status == EvidenceStatus.passed) &&
      proofs.isNotEmpty;
  buffer.writeln('Status: ${eligible ? 'ELIGIBLE' : 'INELIGIBLE'}');
  return buffer.toString();
}

void _writeSection(StringBuffer buffer, String title, List<String> values) {
  buffer.writeln('$title:');
  if (values.isEmpty) {
    buffer.writeln('  <none>');
    return;
  }
  for (final value in values.toSet().toList()..sort()) {
    buffer.writeln('  $value');
  }
}

String renderTrace(ValidationReport report) {
  final map = report.toJson();
  final buffer = StringBuffer('Zuke trace\n');
  buffer.writeln('Eligibility: ${map['eligible'] ?? false}');
  for (final proof in (map['controlProofs'] as List? ?? const [])) {
    buffer.writeln('Control: $proof');
  }
  for (final record in (map['evidence'] as List? ?? const [])) {
    buffer.writeln('Evidence: $record');
  }
  return buffer.toString();
}

String renderValidationReport(
  ValidationReport report, {
  String format = 'text',
}) {
  final map = report.toJson();
  if (format == 'json') return const JsonEncoder.withIndent('  ').convert(map);
  final buffer = StringBuffer('Zuke validation\n');
  buffer.writeln(
    'Status: ${map['status'] ?? (map['eligible'] == true ? 'passed' : 'failed')}',
  );
  buffer.writeln('Eligibility: ${map['eligible'] ?? false}');
  final reasons = map['ineligibilityReasons'];
  if (reasons is Iterable && reasons.isNotEmpty) {
    buffer.writeln('Ineligibility:');
    for (final reason in reasons) buffer.writeln('  $reason');
  }
  for (final proof in (map['controlProofs'] as List? ?? const [])) {
    buffer.writeln('Control: $proof');
  }
  for (final record in (map['evidence'] as List? ?? const [])) {
    buffer.writeln('Evidence: $record');
  }
  return buffer.toString();
}

final class ZukeModelGraph {
  final List<ZukeModelEpic> epics;
  final List<ZukeModelPbi> pbis;
  final List<ZukeModelFeature> features;

  const ZukeModelGraph({
    this.epics = const [],
    this.pbis = const [],
    this.features = const [],
  });

  Map<String, Object?> toJson() => {
    'epics': epics.map((item) => item.toJson()).toList(),
    'pbis': pbis.map((item) => item.toJson()).toList(),
    'features': features.map((item) => item.toJson()).toList(),
  };
}

final class ZukeModelEpic {
  final String id;
  final String? title;
  final String? owner;
  final List<String> featureIds;

  const ZukeModelEpic({
    required this.id,
    this.title,
    this.owner,
    this.featureIds = const [],
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'owner': owner,
    'featureIds': featureIds,
  };
}

final class ZukeModelPbi {
  final String id;
  final String? title;
  final String? owner;
  final String? feature;
  final String? status;
  final List<String> ruleIds;

  const ZukeModelPbi({
    required this.id,
    this.title,
    this.owner,
    this.feature,
    this.status,
    this.ruleIds = const [],
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'owner': owner,
    'feature': feature,
    'status': status,
    'ruleIds': ruleIds,
  };
}

final class ZukeModelFeature {
  final String id;
  final String title;
  final String? epic;
  final String? owner;
  final String? status;
  final List<String> targets;
  final List<String> pbis;
  final List<ZukeModelBinding> bindings;
  final List<ZukeModelRule> rules;

  const ZukeModelFeature({
    required this.id,
    required this.title,
    this.epic,
    this.owner,
    this.status,
    this.targets = const [],
    this.pbis = const [],
    this.bindings = const [],
    this.rules = const [],
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'epic': epic,
    'owner': owner,
    'status': status,
    'targets': targets,
    'pbis': pbis,
    'bindings': bindings.map((item) => item.toJson()).toList(),
    'rules': rules.map((item) => item.toJson()).toList(),
  };
}

final class ZukeModelBinding {
  final String id;
  final String target;
  final String cardinality;
  final String instanceCardinality;
  final String? interaction;
  final String variant;
  final String slot;

  const ZukeModelBinding({
    required this.id,
    required this.target,
    required this.cardinality,
    this.instanceCardinality = 'exactlyOne',
    this.interaction,
    this.variant = 'default',
    this.slot = 'primary',
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'target': target,
    'cardinality': cardinality,
    'instanceCardinality': instanceCardinality,
    'interaction': interaction,
    'variant': variant,
    'slot': slot,
  };
}

final class ZukeModelRule {
  final String id;
  final String title;
  final List<String> pbis;
  final List<String> requiredEvidence;
  final String? securityProfile;
  final List<ZukeModelControlRequirement> requires;
  final List<ZukeModelScenario> scenarios;

  const ZukeModelRule({
    required this.id,
    required this.title,
    this.pbis = const [],
    this.requiredEvidence = const [],
    this.securityProfile,
    this.requires = const [],
    this.scenarios = const [],
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'pbis': pbis,
    'requiredEvidence': requiredEvidence,
    'securityProfile': securityProfile,
    'requires': requires.map((item) => item.toJson()).toList(),
    'scenarios': scenarios.map((item) => item.toJson()).toList(),
  };
}

final class ZukeModelControlRequirement {
  final String kind;
  final String id;
  final String target;
  final String cardinality;
  final List<String> acceptableAssurance;
  final String variant;
  final String slot;

  const ZukeModelControlRequirement({
    required this.kind,
    required this.id,
    required this.target,
    required this.cardinality,
    this.acceptableAssurance = const [],
    required this.variant,
    required this.slot,
  });

  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'target': target,
    'cardinality': cardinality,
    'acceptableAssurance': acceptableAssurance,
    'variant': variant,
    'slot': slot,
  };
}

final class ZukeModelScenario {
  final String id;
  final String title;
  final String keyword;
  final List<String> tags;
  final List<String> effectiveTags;
  final List<ZukeModelStep> steps;
  final List<ZukeModelExamples> examples;

  const ZukeModelScenario({
    required this.id,
    required this.title,
    required this.keyword,
    this.tags = const [],
    this.effectiveTags = const [],
    this.steps = const [],
    this.examples = const [],
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'keyword': keyword,
    'tags': tags,
    'effectiveTags': effectiveTags,
    'steps': steps.map((item) => item.toJson()).toList(),
    'examples': examples.map((item) => item.toJson()).toList(),
  };
}

final class ZukeModelStep {
  final String keyword;
  final String text;

  const ZukeModelStep({required this.keyword, required this.text});

  Map<String, Object?> toJson() => {'keyword': keyword, 'text': text};
}

final class ZukeModelExamples {
  final String title;
  final List<String> tags;
  final List<String> effectiveTags;
  final List<String> headers;
  final List<List<String>> rows;

  const ZukeModelExamples({
    required this.title,
    this.tags = const [],
    this.effectiveTags = const [],
    this.headers = const [],
    this.rows = const [],
  });

  Map<String, Object?> toJson() => {
    'title': title,
    'tags': tags,
    'effectiveTags': effectiveTags,
    'headers': headers,
    'rows': rows,
  };
}

class ZukeModel {
  final String schemaVersion;
  final String workspaceName;
  final String root;
  final ZukeModelGraph graph;
  final Map<String, Object?> registries;
  final ValidationReport validationReport;
  final Map<String, Object?> lockDigests;

  const ZukeModel({
    this.schemaVersion = 'zuke.model.v1',
    required this.workspaceName,
    required this.root,
    required this.graph,
    required this.registries,
    required this.validationReport,
    this.lockDigests = const {},
  });

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'workspace': {'name': workspaceName, 'root': root},
    'graph': graph.toJson(),
    'registries': registries,
    'validationReport': validationReport.toJson(),
    'lockDigests': lockDigests,
  };

  String renderJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson()) + '\n';
}

String renderSpecModelJson(ZukeModel model) => model.renderJson();
