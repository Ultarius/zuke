import 'package:path/path.dart' as p;
import 'package:zuke_frontend/zuke_frontend.dart';

import '../ir.dart';
import '../workspace_annotation_scan.dart';
import 'binding_coverage_engine.dart';

export 'binding_coverage_engine.dart';

/// The severity the workspace declared for the unbound code, or null when it
/// declared none.
///
/// One accessor for both the decision and the value, because the two callers
/// need the same fact and disagreeing about it fails in opposite directions. The
/// command has to know whether to pay for a resolver pass; the validator has to
/// know whether to report. If the command thought the check was on and the
/// validator thought it was off, the workspace would be charged for a full scan
/// and be shown a registration count with no findings beneath it. If the reverse,
/// the check would silently produce nothing.
///
/// The value itself is the switch between a planned gap (`warning`) and an unmet
/// acceptance obligation (`error`); see [BindingCoverageCheck.toMessages].
String? declaredBindingCoverageSeverity(WorkspaceDiscoveryResult workspace) =>
    workspace.config.protectedSeverities[bindingCoverageUnboundCode];

/// The CLI front end for binding coverage.
///
/// The verdict computation lives in `binding_coverage_engine.dart` and is shared
/// with the analysis-server plugin, so the editor and `zuke validate` cannot
/// disagree about whether a slot is bound. This class only adapts a live
/// workspace and a resolved scan into the engine's inputs and renders the result
/// as validation diagnostics.
final class BindingCoverageCheck {
  const BindingCoverageCheck();

  /// The findings for every rule/slot obligation in scope, plus the roll-up.
  ///
  /// [scan] is the resolved registration scan. Passing one whose
  /// [WorkspaceAnnotationScan.unresolvedManagedRegistrations] is zero asserts
  /// that every registration resolved, which is what makes a gap decidable.
  BindingCoverageReport run(
    WorkspaceDiscoveryResult workspace,
    WorkspaceAnnotationScan scan, {
    List<String>? selectedScenarioIds,
  }) => const BindingVerdictEngine().compute(
    obligations: workspaceEvidenceObligations(workspace, root: scan.root),
    registrations: managedRegistrationFacts(scan),
    runnerScopes: workspaceRunnerScopes(workspace),
    unresolvedRegistrations: scan.unresolvedManagedRegistrations,
    selectedScenarioIds: selectedScenarioIds,
  );

  /// Every message this check produces, in one place.
  ///
  /// Unbound at [severity] for a decided gap, and info for anything the scan
  /// could not answer plus the per-feature roll-up. The wording of all three
  /// lives here rather than being split between this method and a caller, so the
  /// check cannot describe the same finding two ways.
  List<IrDiagnostic> toMessages(
    BindingCoverageReport report, {
    required IrDiagnosticSeverity severity,
  }) => [
    for (final finding in report.unbound)
      IrDiagnostic(
        code: bindingCoverageUnboundCode,
        severity: severity,
        // The sentence is the engine's, so the CLI and the analyzer plugin
        // describe one gap identically.
        message: bindingUnboundMessage(finding),
        remediation:
            'Register a managed test for ${finding.scenarioId} that declares '
            'evidenceTypes including "${finding.type}"'
            '${finding.discoveredAt.isEmpty ? '' : '. Registrations found at '
                      '${finding.discoveredAt.join(', ')} publish '
                      '${finding.publishedKinds}'}',
      ),
    for (final finding in report.unverified)
      IrDiagnostic(
        code: bindingCoverageUnverifiedCode,
        severity: IrDiagnosticSeverity.info,
        message:
            'Evidence slot ${finding.slotKey} could not be decided from source: '
            '${finding.reason}. Affected scenarios: ${finding.scenarioId}',
      ),
    for (final summary in report.featureSummaries)
      IrDiagnostic(
        code: bindingCoverageSummaryCode,
        severity: IrDiagnosticSeverity.info,
        message:
            '${summary.featureId}: ${summary.bound} bound, ${summary.unbound} '
            'unbound, ${summary.unverified} unverified across '
            '${summary.obligations} rule/slot obligations',
      ),
  ];
}

/// Every declared evidence obligation in the workspace, one per rule that has
/// slots.
///
/// Also used by the index writer, so the facts the editor reasons over are the
/// facts the CLI reasoned over rather than a second reading of the same features.
List<EvidenceObligation> workspaceEvidenceObligations(
  WorkspaceDiscoveryResult workspace, {
  String? root,
}) => [
  for (final feature in workspace.data.features)
    for (final rule in feature.rules)
      if ((rule.metadata.evidenceRequirements ?? const []).isNotEmpty)
        EvidenceObligation(
          featureId: feature.metadata.id ?? '<feature>',
          ruleId: rule.metadata.id ?? rule.ruleElement.title,
          scenarioIds: _sortedScenarioIds(rule),
          slots: rule.metadata.evidenceRequirements!,
          location: _locationOf(rule.ruleElement.source, root: root),
        ),
];

/// The runner scopes an adapter can be attributed through.
///
/// A registration records no adapter, so which adapter runs it is a property of
/// the runner configured for that target and package. Grouping by pair is what
/// lets the engine tell "exactly one adapter" from "several could apply", which
/// are different verdicts.
///
/// Adapters are collected into a set, not a list. Two runners for one pair
/// declaring the *same* adapter still attribute every registration to that one
/// adapter, so counting them twice makes the engine read a decided slot as
/// unattributable. That is exactly the drift this function being shared is meant
/// to prevent, and it was caught by running both front ends against a workspace
/// with two same-adapter runners rather than by the unit tests.
List<RunnerScopeFact> workspaceRunnerScopes(
  WorkspaceDiscoveryResult workspace,
) {
  final adapters = <_ScopePair, Set<String>>{};
  for (final runner in workspace.config.workspaceRunners) {
    final pair = _ScopePair(
      target: runner.target,
      sourcePackage: runner.sourcePackage,
    );
    adapters.putIfAbsent(pair, () => <String>{}).add(runner.sourceAdapter);
  }
  return [
    for (final entry in adapters.entries)
      RunnerScopeFact(
        target: entry.key.target,
        sourcePackage: entry.key.sourcePackage,
        adapters: entry.value.toList()..sort(),
      ),
  ];
}

List<String> _sortedScenarioIds(ParsedRule rule) => {
  for (final scenario in rule.scenarios) ..._scenarioIdsOf(scenario),
}.toList()..sort();

Set<String> _scenarioIdsOf(GherkinScenario scenario) => {
  for (final tag in scenario.tags)
    if (tag.name.startsWith('SCN-')) tag.name,
  for (final examples in scenario.examples)
    for (final tag in examples.tags)
      if (tag.name.startsWith('SCN-')) tag.name,
};

/// The rule's real location in the `.feature`, when the parser recorded one.
///
/// The plugin cannot anchor a diagnostic on a Gherkin line, so without this the
/// reader would be sent to a generated constant instead of to the rule.
FeatureLocation? _locationOf(SourceLocation source, {String? root}) {
  if (source.file.isEmpty || source.line < 1) return null;
  return FeatureLocation(
    file:
        (root != null && p.isAbsolute(source.file)
                ? p.relative(source.file, from: root)
                : source.file)
            .replaceAll('\\', '/'),
    line: source.line,
    column: source.column,
  );
}

final class _ScopePair {
  const _ScopePair({required this.target, required this.sourcePackage});

  final String target;
  final String sourcePackage;

  @override
  bool operator ==(Object other) =>
      other is _ScopePair &&
      other.target == target &&
      other.sourcePackage == sourcePackage;

  @override
  int get hashCode => Object.hash(target, sourcePackage);
}

/// Shared projection for live validation and the editor index writer.
List<ManagedRegistrationFact> managedRegistrationFacts(
  WorkspaceAnnotationScan scan,
) => [
  for (final claim in scan.managedScenarios)
    ManagedRegistrationFact(
      scenarioId: claim.scenarioId,
      sourcePath: claim.sourcePath,
      target: claim.target,
      packageId: claim.packageId,
      evidenceTypes: claim.evidenceTypes,
    ),
];
