import 'package:test/test.dart';
import 'package:zuke_cli/src/ir.dart';
import 'package:zuke_cli/src/proof_engine/binding_coverage_check.dart';
import 'package:zuke_cli/src/workspace_annotation_scan.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

const _check = BindingCoverageCheck();

void main() {
  test('feature locations are relative to the workspace root', () {
    final report = _check.run(
      _workspace(slots: [_slot()], sourceFile: '/w/specs/features/x.feature'),
      _scan(const []),
    );
    expect(report.unbound.single.location!.file, 'specs/features/x.feature');
  });
  group('BindingCoverageCheck verdicts', () {
    test('a registration publishing the kind binds the slot', () {
      final report = _check.run(
        _workspace(slots: [_slot()]),
        _scan([
          _binding('SCN-1', evidenceTypes: ['flutter-widget']),
        ]),
      );

      expect(report.findings.single.verdict, BindingCoverageVerdict.bound);
      expect(report.findings.single.discoveredAt, ['test/app_test.dart']);
      expect(report.unbound, isEmpty);
      expect(report.unverified, isEmpty);
    });

    test('no registration at all is a decided gap', () {
      final report = _check.run(_workspace(slots: [_slot()]), _scan(const []));

      final finding = report.unbound.single;
      expect(finding.verdict, BindingCoverageVerdict.unbound);
      expect(finding.reason, contains('no managed registration'));
      expect(finding.scenarioId, 'SCN-1');
    });

    test('a registration of the wrong kind is a decided gap, not a pass', () {
      final report = _check.run(
        _workspace(slots: [_slot(type: 'flutter-widget')]),
        _scan([
          _binding('SCN-1', evidenceTypes: ['domain-unit']),
        ]),
      );

      final finding = report.unbound.single;
      expect(finding.verdict, BindingCoverageVerdict.unbound);
      expect(finding.publishedKinds, 'domain-unit');
      // The message must say what was found, so the reader can act.
      expect(finding.discoveredAt, ['test/app_test.dart']);
    });

    test('a binding on one scenario satisfies the rule it belongs to', () {
      // The obligation is the rule's: its scenarios collectively satisfy its
      // slots. Demanding that every scenario satisfy every slot would report
      // each multi-target rule as a gap, which is not what the declaration
      // means. The finding still names which scenarios carry the binding.
      final report = _check.run(
        _workspace(slots: [_slot()], scenarioIds: ['SCN-1', 'SCN-2']),
        _scan([
          _binding('SCN-1', evidenceTypes: ['flutter-widget']),
        ]),
      );

      expect(report.findings.single.verdict, BindingCoverageVerdict.bound);
      expect(report.findings.single.scenarioId, 'SCN-1');
      expect(
        report.findings.single.reason,
        contains('satisfied by 1 of 2 in-scope scenarios'),
      );
      expect(report.unbound, isEmpty);
    });

    test('a registration for another scenario does not satisfy this rule', () {
      // The named scenario is not among this rule's, so the rule has no
      // registration at all and the gap is real.
      final report = _check.run(
        _workspace(slots: [_slot()], scenarioIds: ['SCN-1']),
        _scan([
          _binding('SCN-OTHER', evidenceTypes: ['flutter-widget']),
        ]),
      );

      expect(report.unbound.single.scenarioId, 'SCN-1');
      expect(report.unbound.single.reason, contains('no managed registration'));
    });

    test(
      'target mismatch is a decided gap, and the message names the target',
      () {
        final report = _check.run(
          _workspace(slots: [_slot(target: 'app')]),
          _scan([
            _binding(
              'SCN-1',
              evidenceTypes: ['flutter-widget'],
              target: 'backend',
              sourcePath: 'test/api_test.dart',
            ),
          ]),
        );

        final finding = report.unbound.single;
        expect(finding.reason, contains('none in the slot target'));
        expect(finding.reason, contains('backend'));
        expect(finding.discoveredAt, ['test/api_test.dart']);
      },
    );

    test('the full slot identity is matched, not the type alone', () {
      final report = _check.run(
        _workspace(slots: [_slot(variant: 'dark-mode')]),
        _scan([
          _binding('SCN-1', evidenceTypes: ['flutter-widget']),
        ]),
      );

      final finding = report.unverified.single;
      expect(finding.slotKey, 'flutter-widget/app/app/dart-source/dark-mode');
      expect(finding.reason, contains('do not record a variant'));
    });

    test(
      'the slot key carries the variant, so a reader can see the identity',
      () {
        final report = _check.run(
          _workspace(slots: [_slot()]),
          _scan(const []),
        );

        expect(
          report.unbound.single.slotKey,
          'flutter-widget/app/app/dart-source/default',
        );
      },
    );
  });

  group('BindingCoverageCheck reports unverified rather than absent', () {
    test('an unreadable kind makes the slot undecidable', () {
      final report = _check.run(
        _workspace(slots: [_slot()]),
        _scan([_binding('SCN-1')]),
      );

      final finding = report.unverified.single;
      expect(finding.reason, contains('could not be read as constants'));
      // The decisive property: no gap was asserted.
      expect(report.unbound, isEmpty);
      expect(report.isComplete, isTrue);
    });

    test(
      'an unreadable kind alongside a deciding one still blocks the gap',
      () {
        final report = _check.run(
          _workspace(slots: [_slot()]),
          _scan([
            _binding(
              'SCN-1',
              evidenceTypes: ['domain-unit'],
              sourcePath: 'test/a_test.dart',
            ),
            _binding('SCN-1', sourcePath: 'test/b_test.dart'),
          ]),
        );

        expect(report.unbound, isEmpty);
        expect(report.unverified.single.reason, contains('could not be read'));
      },
    );

    test('an unresolvable registration makes every slot undecidable', () {
      final report = _check.run(
        _workspace(slots: [_slot()]),
        _scan(const [], unresolved: 1),
      );

      expect(report.unbound, isEmpty);
      expect(
        report.unverified.single.reason,
        contains('no resolvable scenario'),
      );
      expect(report.isComplete, isFalse);
    });

    test('a slot naming no evidence type is undecidable, not unbound', () {
      final report = _check.run(
        _workspace(slots: [_slot(type: '')]),
        _scan([
          _binding('SCN-1', evidenceTypes: ['flutter-widget']),
        ]),
      );

      expect(
        report.unverified.single.reason,
        contains('declares no evidence type'),
      );
    });
  });

  group('BindingCoverageCheck scope', () {
    test('a rule with no slots contributes nothing', () {
      final report = _check.run(
        _workspace(slots: const []),
        _scan([
          _binding('SCN-1', evidenceTypes: ['flutter-widget']),
        ]),
      );

      expect(report.findings, isEmpty);
      expect(report.featureSummaries, isEmpty);
    });

    test('selection narrows the reported scenarios but not the rule', () {
      // A slot satisfied by an out-of-profile scenario is still satisfied, so
      // narrowing must not invent a gap.
      final report = _check.run(
        _workspace(slots: [_slot()], scenarioIds: ['SCN-1', 'SCN-2']),
        _scan([
          _binding('SCN-2', evidenceTypes: ['flutter-widget']),
        ]),
        selectedScenarioIds: const ['SCN-1'],
      );

      expect(report.findings.single.verdict, BindingCoverageVerdict.bound);
      expect(report.findings.single.scenarioId, 'SCN-2');
    });

    test('a rule with no selected scenario is skipped', () {
      final report = _check.run(
        _workspace(slots: [_slot()]),
        _scan(const []),
        selectedScenarioIds: const ['SCN-ELSEWHERE'],
      );

      expect(report.findings, isEmpty);
    });

    test('feature summaries count verdicts separately', () {
      final report = _check.run(
        _workspace(
          slots: [
            _slot(),
            _slot(type: 'domain-unit'),
          ],
        ),
        _scan([
          _binding('SCN-1', evidenceTypes: ['flutter-widget']),
        ]),
      );

      final summary = report.featureSummaries.single;
      expect(summary.bound, 1);
      expect(summary.unbound, 1);
      expect(summary.unverified, 0);
      expect(summary.obligations, 2);
    });
  });

  group('BindingCoverageCheck messages', () {
    test(
      'a gap states the obligation, the absence, and the limit of the check',
      () {
        final report = _check.run(
          _workspace(slots: [_slot()]),
          _scan([
            _binding('SCN-1', evidenceTypes: ['domain-unit']),
          ]),
        );

        // Selected by code, not position: the report also yields a per-feature
        // roll-up, and a test that took `.single` would break the day one more
        // informational message joined the list.
        final message = _check
            .toMessages(report, severity: IrDiagnosticSeverity.warning)
            .firstWhere((m) => m.code == bindingCoverageUnboundCode);

        expect(message.code, bindingCoverageUnboundCode);
        expect(message.severity, IrDiagnosticSeverity.warning);
        // The slot leads, because `validate` groups by a normalized shape and
        // the opening text is what survives into a group heading.
        expect(
          message.message,
          startsWith(
            'Evidence slot '
            'flutter-widget/app/app/dart-source/default is unbound:',
          ),
        );
        expect(message.message, contains('does not include "flutter-widget"'));
        expect(message.message, contains('Affected scenarios: SCN-1'));
        // The claim this check cannot make, stated so nobody infers it.
        expect(
          message.message,
          contains('does not mean a test for these scenarios exists'),
        );
        expect(message.remediation, contains('evidenceTypes'));
        expect(message.remediation, contains('test/app_test.dart'));
      },
    );

    test(
      'a discovered file is listed once, however many scenarios it binds',
      () {
        final report = _check.run(
          _workspace(
            slots: [_slot()],
            scenarioIds: ['SCN-1', 'SCN-2', 'SCN-3'],
          ),
          _scan([
            _binding(
              'SCN-1',
              evidenceTypes: ['domain-unit'],
              sourcePath: 'test/a_test.dart',
            ),
            _binding(
              'SCN-2',
              evidenceTypes: ['domain-unit'],
              sourcePath: 'test/a_test.dart',
            ),
            _binding(
              'SCN-3',
              evidenceTypes: ['domain-unit'],
              sourcePath: 'test/a_test.dart',
            ),
          ]),
        );

        // One registration site, so listing it per scenario would read as
        // three separate things to fix.
        expect(report.unbound.single.discoveredAt, ['test/a_test.dart']);
      },
    );

    test(
      'severity comes from the workspace, so one check serves both buckets',
      () {
        final report = _check.run(
          _workspace(slots: [_slot()]),
          _scan(const []),
        );

        IrDiagnosticSeverity severityFor(IrDiagnosticSeverity declared) =>
            _check
                .toMessages(report, severity: declared)
                .firstWhere((m) => m.code == bindingCoverageUnboundCode)
                .severity;

        expect(
          severityFor(IrDiagnosticSeverity.warning),
          IrDiagnosticSeverity.warning,
        );
        expect(
          severityFor(IrDiagnosticSeverity.error),
          IrDiagnosticSeverity.error,
        );
        // The roll-up rides along with the report but is never promoted by the
        // workspace's declared severity: feature-level counts cannot decide
        // acceptance, so an error bucket must not inherit an error roll-up.
        expect(
          _check
              .toMessages(report, severity: IrDiagnosticSeverity.error)
              .where((m) => m.code == bindingCoverageSummaryCode)
              .single
              .severity,
          IrDiagnosticSeverity.info,
        );
      },
    );

    test('an unverified finding is always info and never fails a run', () {
      final report = _check.run(
        _workspace(slots: [_slot()]),
        _scan([_binding('SCN-1')]),
      );

      final message = _check
          .toMessages(report, severity: IrDiagnosticSeverity.error)
          .firstWhere((m) => m.code == bindingCoverageUnverifiedCode);

      expect(message.code, bindingCoverageUnverifiedCode);
      expect(message.severity, IrDiagnosticSeverity.info);
    });
  });
}

/// A declared evidence slot, in the shape the parser produces.
Map<String, String> _slot({
  String type = 'flutter-widget',
  String target = 'app',
  String sourcePackage = 'app',
  String sourceAdapter = 'dart-source',
  String variant = 'default',
}) => {
  'type': type,
  'target': target,
  'sourcePackage': sourcePackage,
  'sourceAdapter': sourceAdapter,
  'variant': variant,
};

ManagedScenarioClaim _binding(
  String scenarioId, {
  List<String>? evidenceTypes,
  String? target = 'app',
  String? packageId = 'app',
  String sourcePath = 'test/app_test.dart',
}) => ManagedScenarioClaim(
  scenarioId: scenarioId,
  sourcePath: sourcePath,
  target: target,
  packageId: packageId,
  evidenceTypes: evidenceTypes,
);

WorkspaceAnnotationScan _scan(
  List<ManagedScenarioClaim> claims, {
  int unresolved = 0,
}) => WorkspaceAnnotationScan(
  root: '/w',
  claims: const [],
  sourcePaths: const [],
  inputPaths: const [],
  managedScenarios: claims,
  unresolvedManagedRegistrations: unresolved,
);

/// A workspace with one feature, one rule carrying [slots], and [scenarioIds].
///
/// Built in memory: this check reads only the discovery result and the resolved
/// scan, so it needs neither `pub get` nor an analyzer pass to be exercised.
WorkspaceDiscoveryResult _workspace({
  required List<Map<String, String>> slots,
  List<String> scenarioIds = const ['SCN-1'],
  String sourceFile = 'specs/features/x.feature',
}) {
  final at = SourceLocation(file: sourceFile, line: 1);
  final rule = ParsedRule(
    ruleElement: GherkinElement(
      keyword: GherkinKeyword.rule,
      title: 'Rule',
      source: at,
    ),
    tags: [GherkinTag(name: '@RULE-1', source: at)],
    scenarios: [
      for (final id in scenarioIds)
        GherkinScenario(
          tags: [GherkinTag(name: id, source: at)],
          scenarioElement: GherkinElement(
            keyword: GherkinKeyword.scenario,
            title: 'Scenario',
            source: at,
          ),
        ),
    ],
    metadata: ParsedMetadata(
      id: 'RULE-1',
      source: at,
      requiredEvidence: [for (final entry in slots) entry['type']!],
      evidenceRequirements: slots,
    ),
  );
  return WorkspaceDiscoveryResult(
    config: const ZukeConfig(
      evidenceTypes: {'flutter-widget': 'record'},
      // A registration records no adapter, so the check attributes one from the
      // runner configured for the slot's target and package. Without this the
      // adapter dimension is unknown and every verdict is unverified.
      workspaceRunners: [
        WorkspaceRunner(
          id: 'app-tests',
          target: 'app',
          sourcePackage: 'app',
          sourceAdapter: 'dart-source',
          sourceCompatibilityId: 'dart-source-package-v1',
          runnerCompatibilityId: 'dart-runner-v1',
        ),
      ],
    ),
    data: MetadataExtractorResult(
      features: [
        ParsedFeature(
          featureElement: GherkinElement(
            keyword: GherkinKeyword.feature,
            title: 'Feature',
            source: at,
          ),
          tags: [GherkinTag(name: '@FEAT-1', source: at)],
          rules: [rule],
          metadata: ParsedMetadata(id: 'FEAT-1', source: at),
        ),
      ],
    ),
  );
}
