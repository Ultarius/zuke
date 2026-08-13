import 'package:test/test.dart';
import 'package:zuke_cli/src/reporter.dart';
import 'package:zuke_cli/src/ir.dart';

void main() {
  test('renders deterministic text and JSON validation reports', () {
    const report = ValidationReport(
      eligible: true,
      controlProofs: [
        ControlProofResult(
          controlId: 'CTRL-1',
          status: ProofStatus.proven,
          semantics: CoverageSemantics.ingressDominance,
        ),
      ],
    );
    expect(renderValidationReport(report), contains('Eligibility: true'));
    expect(renderValidationReport(report, format: 'json'), contains('CTRL-1'));
  });

  test('renders a requirement-scoped assurance trace', () {
    const report = ValidationReport(
      controlProofs: [
        ControlProofResult(
          requirementId: 'RULE-1',
          controlId: 'CTRL-1',
          status: ProofStatus.proven,
          semantics: CoverageSemantics.ingressDominance,
          providerIds: ['provider:one'],
        ),
      ],
      evidence: [
        EvidenceRecord(
          requirementId: 'RULE-1',
          evidenceType: 'gherkin-api',
          target: 'backend',
          executionId: 'execution-1',
          profile: 'pullRequest',
        ),
      ],
    );

    final output = renderRequirementTrace(
      const RequirementTrace(
        requirementId: 'RULE-1',
        definedBy: 'specs/calculator.feature:12',
        implementations: ['[domain] package:calculator/domain.dart#evaluate'],
        requiredControls: ['CTRL-1'],
        report: report,
      ),
    );

    expect(output, contains('Defined by:'));
    expect(output, contains('Implemented by:'));
    expect(output, contains('assurance: PROVEN'));
    expect(output, contains('gherkin-api: PASSED'));
    expect(output, contains('Status: ELIGIBLE'));
  });

  test('renders proven and attested assurance states distinctly', () {
    const report = ValidationReport(
      controlProofs: [
        ControlProofResult(
          requirementId: 'RULE-1',
          controlId: 'CTRL-PROVEN',
          status: ProofStatus.proven,
          semantics: CoverageSemantics.ingressDominance,
          providerIds: ['provider:in-repository'],
        ),
        ControlProofResult(
          requirementId: 'RULE-1',
          controlId: 'CTRL-ATTESTED',
          status: ProofStatus.attested,
          semantics: CoverageSemantics.externalAttestation,
          providerIds: ['provider:gateway'],
        ),
      ],
    );

    final output = renderRequirementTrace(
      const RequirementTrace(
        requirementId: 'RULE-1',
        definedBy: 'specs/calculator.feature:12',
        requiredControls: ['CTRL-ATTESTED', 'CTRL-PROVEN'],
        report: report,
      ),
    );

    expect(output, contains('CTRL-PROVEN'));
    expect(output, contains('assurance: PROVEN'));
    expect(output, contains('CTRL-ATTESTED'));
    expect(output, contains('assurance: ATTESTED'));
  });

  test('ZukeModelGraph and child model JSON serialization', () {
    const catalog = ZukeModelGraph(
      epics: [
        ZukeModelEpic(
          id: 'EPIC-1',
          title: 'Epic One',
          owner: 'team-a',
          featureIds: ['FEAT-1'],
        ),
      ],
      pbis: [
        ZukeModelPbi(
          id: 'PBI-1',
          title: 'PBI One',
          owner: 'team-a',
          feature: 'FEAT-1',
          status: 'active',
          ruleIds: ['RULE-1'],
        ),
      ],
      features: [
        ZukeModelFeature(
          id: 'FEAT-1',
          title: 'Feature One',
          epic: 'EPIC-1',
          owner: 'team-a',
          status: 'active',
          targets: ['flutter'],
          pbis: ['PBI-1'],
          bindings: [
            ZukeModelBinding(
              id: 'binding.1',
              target: 'flutter',
              cardinality: 'exactlyOne',
              interaction: 'action',
            ),
          ],
          rules: [
            ZukeModelRule(
              id: 'RULE-1',
              title: 'Rule One',
              requiredEvidence: ['gherkin-ui'],
              scenarios: [
                ZukeModelScenario(
                  id: 'SCN-1',
                  title: 'Scenario One',
                  keyword: 'Scenario',
                  tags: ['@SCN-1'],
                  effectiveTags: ['@SCN-1'],
                  steps: [ZukeModelStep(keyword: 'Given ', text: 'a step')],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final json = catalog.toJson();
    expect(json, contains('epics'));
    expect(json, contains('pbis'));
    expect(json, contains('features'));
  });
}
