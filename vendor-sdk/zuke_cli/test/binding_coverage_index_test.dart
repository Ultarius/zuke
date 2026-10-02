import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:zuke_cli/src/index_contract.dart';
import 'package:zuke_cli/src/proof_engine/binding_coverage_engine.dart';
import 'package:zuke_cli/src/tooling/dart_extractor/zuke_index.dart';

import 'support/temporary_directory.dart';

/// The acceptance surface for surfacing binding-coverage gaps in the editor.
///
/// These tests exist because of one specific way this could be wrong: the editor
/// reads a *serialized snapshot* while `zuke validate` reads a *live scan*. Any
/// place the snapshot loses information turns `unverified` into a false
/// `unbound`, and a false gap is worse than no gap - it sends someone to write a
/// test that already exists. So the round trip is the subject here, not the
/// matching logic, which `binding_coverage_check_test.dart` covers directly.
void main() {
  test(
    'feature summaries aggregate rules even when features are interleaved',
    () {
      final report = const BindingVerdictEngine().compute(
        obligations: [
          _obligation('RULE-BOUND', [_slot()], ['SCN-BOUND']),
          const EvidenceObligation(
            featureId: 'FEAT-OTHER',
            ruleId: 'RULE-OTHER',
            scenarioIds: ['SCN-OTHER'],
            slots: [
              {'type': 'unit'},
            ],
          ),
          _obligation('RULE-UNBOUND', [_slot()], ['SCN-UNBOUND']),
          _obligation('RULE-UNKNOWN', [_slot()], ['SCN-UNKNOWN']),
        ],
        registrations: [
          _registration('SCN-BOUND', ['flutter-widget']),
          _registration('SCN-UNKNOWN', null),
        ],
        runnerScopes: _scope(),
      );
      expect(report.featureSummaries, hasLength(2));
      final summary = report.featureSummaries.first;
      expect(summary.obligations, 3);
      expect(summary.bound, 1);
      expect(summary.unbound, 1);
      expect(summary.unverified, 1);
      expect(report.featureSummaries.last.obligations, 1);
    },
  );

  test('runner scopes have set equality and matching hash codes', () {
    const first = RunnerScopeFact(
      target: 'app',
      sourcePackage: 'app',
      adapters: ['a', 'b'],
    );
    const reordered = RunnerScopeFact(
      target: 'app',
      sourcePackage: 'app',
      adapters: ['b', 'a', 'a'],
    );
    expect(first, reordered);
    expect(first.hashCode, reordered.hashCode);
    expect({first, reordered}, hasLength(1));
  });
  group('binding-coverage facts survive the index round trip', () {
    test('every verdict the engine reaches is reached from the index', () {
      // Deliberately no unresolved registrations: that count makes *every* slot
      // unverified workspace-wide, so it cannot coexist with an `unbound` verdict
      // in the same report. It has its own test below.
      final obligations = <EvidenceObligation>[
        _obligation('RULE-BOUND', [_slot()], ['SCN-BOUND']),
        _obligation('RULE-UNBOUND', [_slot()], ['SCN-UNBOUND']),
        _obligation('RULE-UNKNOWN-KINDS', [_slot()], ['SCN-UNKNOWN']),
      ];
      final registrations = <ManagedRegistrationFact>[
        _registration('SCN-BOUND', ['flutter-widget']),
        _registration('SCN-UNKNOWN', null),
      ];
      final scopes = _scope();

      final direct = const BindingVerdictEngine().compute(
        obligations: obligations,
        registrations: registrations,
        runnerScopes: scopes,
      );

      final index = _index(
        obligations: obligations,
        registrations: registrations,
        runnerScopes: scopes,
      );
      final reread = const BindingVerdictEngine().compute(
        obligations: index.evidenceObligations,
        registrations: index.managedRegistrations,
        runnerScopes: index.runnerScopes,
        unresolvedRegistrations: index.unresolvedManagedRegistrations,
      );

      expect(
        _verdictsOf(reread),
        _verdictsOf(direct),
        reason:
            'the editor and the CLI run the same engine, so any difference here '
            'is information the serialization dropped',
      );
      // Spelled out, because "the lists are equal" would pass just as well if
      // both were empty.
      expect(_verdictOf(reread, 'RULE-BOUND'), BindingCoverageVerdict.bound);
      // The gap: readable facts, nothing registering it.
      expect(
        _verdictOf(reread, 'RULE-UNBOUND'),
        BindingCoverageVerdict.unbound,
      );
      // An unreadable kind must stay unknown through the round trip. Coerced to
      // an empty list it would read as "publishes nothing" and refute the slot,
      // turning this into a false gap.
      expect(
        _verdictOf(reread, 'RULE-UNKNOWN-KINDS'),
        BindingCoverageVerdict.unverified,
      );
      // And the reason travels with it, so the editor can still explain itself.
      final unknown = reread.findings.firstWhere(
        (f) => f.ruleId == 'RULE-UNKNOWN-KINDS',
      );
      expect(unknown.reason, contains('could not be read as constants'));
      expect(unknown.publishedKinds, 'no evidence kinds');
    });

    test('a null evidence list stays null rather than becoming empty', () {
      final written = _index(
        obligations: const [],
        registrations: const [
          ManagedRegistrationFact(
            scenarioId: 'SCN-1',
            sourcePath: 'test/one_test.dart',
            target: 'app',
            packageId: 'app',
          ),
        ],
        runnerScopes: const [],
      );
      final entry = (written.toJson()['managedRegistrations'] as List).single;
      expect(
        entry,
        containsPair('evidenceTypes', isNull),
        reason:
            'an omitted key and an empty list both read as "publishes nothing" '
            'once coerced, which is the false-gap failure this guards',
      );
      expect(
        written.managedRegistrations.single.evidenceTypes,
        isNull,
        reason: 'null means unknown, and unknown has to survive the write',
      );
    });

    test('the whole workspace unreadable leaves every slot unverified', () {
      // The coarsest case, and the one that must stay conservative: one
      // unreadable registration anywhere means no gap anywhere can be claimed,
      // including slots whose own facts are perfectly readable.
      final report = const BindingVerdictEngine().compute(
        obligations: [
          for (final id in ['RULE-A', 'RULE-B', 'RULE-C'])
            _obligation(id, [_slot()], ['SCN-$id']),
        ],
        registrations: const [],
        runnerScopes: const [],
        unresolvedRegistrations: 1,
      );
      expect(report.unbound, isEmpty);
      expect(report.unverified, hasLength(3));
      expect(report.isComplete, isFalse);
    });

    test('the unresolved count survives the round trip', () {
      final index = _index(
        obligations: [
          _obligation('RULE-1', [_slot()], ['SCN-1']),
        ],
        registrations: const [],
        unresolvedRegistrations: 2,
      );
      expect(index.unresolvedManagedRegistrations, 2);
      final reread = ZukeIndex.fromJson(index.toJson());
      expect(reread.unresolvedManagedRegistrations, 2);
      expect(
        const BindingVerdictEngine()
            .compute(
              obligations: reread.evidenceObligations,
              registrations: reread.managedRegistrations,
              runnerScopes: reread.runnerScopes,
              unresolvedRegistrations: reread.unresolvedManagedRegistrations,
            )
            .unverified,
        hasLength(1),
        reason:
            'dropping the count would let the editor report a gap the CLI '
            'correctly refuses to decide',
      );
    });

    test('two runners naming one adapter still attribute exactly one', () {
      // Regression, and the reason both `workspaceRunnerScopes` and the reader
      // deduplicate. A workspace with a setup runner and a test runner on the same
      // package declares the same adapter twice; that is one adapter, so the slot
      // is decidable. Counting the entries turned two decided slots into unknowns
      // in the editor while `zuke validate` still called them decided, which is
      // precisely the drift the shared engine was supposed to prevent.
      final scopes = const [
        RunnerScopeFact(
          target: 'app',
          sourcePackage: 'app',
          adapters: ['dart-source'],
        ),
        RunnerScopeFact(
          target: 'app',
          sourcePackage: 'app',
          adapters: ['dart-source'],
        ),
      ];
      BindingCoverageReport run(List<RunnerScopeFact> input) =>
          const BindingVerdictEngine().compute(
            obligations: [
              _obligation('RULE-1', [_slot()], ['SCN-1']),
            ],
            registrations: [
              _registration('SCN-1', ['flutter-widget']),
            ],
            runnerScopes: input,
          );

      expect(
        run(scopes).findings.single.verdict,
        BindingCoverageVerdict.bound,
        reason:
            'the slot names an adapter, this workspace supplies exactly one, and '
            'a registration publishes that kind, so the slot is decided. Without '
            'deduplication this reads as two candidate adapters and degrades to '
            'unverified, which is the drift this guards.',
      );

      // The same input through the index reader must reach the same verdict, so
      // the deduplication cannot be left to the producer alone.
      final written = _index(
        obligations: [
          _obligation('RULE-1', [_slot()], ['SCN-1']),
        ],
        registrations: [
          _registration('SCN-1', ['flutter-widget']),
        ],
        runnerScopes: scopes,
      );
      final reread = ZukeIndex.fromJson(written.toJson());
      expect(
        reread.runnerScopes.every((scope) => scope.adapters.length == 1),
        isTrue,
      );
      expect(
        const BindingVerdictEngine()
            .compute(
              obligations: reread.evidenceObligations,
              registrations: reread.managedRegistrations,
              runnerScopes: reread.runnerScopes,
              unresolvedRegistrations: reread.unresolvedManagedRegistrations,
            )
            .findings
            .single
            .verdict,
        BindingCoverageVerdict.bound,
      );
    });

    test('two adapters for one scope genuinely remain undecidable', () {
      // The counterpart, so the deduplication above cannot be mistaken for
      // ignoring multiplicity: distinct adapters really are ambiguous.
      final report = const BindingVerdictEngine().compute(
        obligations: [
          _obligation('RULE-1', [_slot()], ['SCN-1']),
        ],
        registrations: [
          _registration('SCN-1', ['flutter-widget']),
        ],
        runnerScopes: const [
          RunnerScopeFact(
            target: 'app',
            sourcePackage: 'app',
            adapters: ['dart-source', 'other-source'],
          ),
        ],
      );
      expect(report.unverified.single.reason, contains('more than one'));
    });

    test('an adapter the runner scopes cannot attribute stays unverified', () {
      // Two runners for one target/package pair: which adapter runs a
      // registration is genuinely undecidable, so the slot is not a gap.
      final report = const BindingVerdictEngine().compute(
        obligations: [
          _obligation('RULE-1', [_slot()], ['SCN-1']),
        ],
        registrations: [
          _registration('SCN-1', ['flutter-widget']),
        ],
        runnerScopes: const [
          RunnerScopeFact(
            target: 'app',
            sourcePackage: 'app',
            adapters: ['dart-source'],
          ),
          RunnerScopeFact(
            target: 'app',
            sourcePackage: 'app',
            adapters: ['other-source'],
          ),
        ],
      );
      expect(report.unverified.single.reason, contains('more than one'));
    });

    test(
      'a rule location is carried so the editor can name the feature line',
      () {
        final index = _index(
          obligations: [
            _obligation('RULE-1', [_slot()], ['SCN-1']),
          ],
          registrations: const [],
        );
        final location = index.evidenceObligations.single.location;
        expect(location, isNotNull);
        expect(location!.file, 'specs/features/x.feature');
        expect(location.line, 7);
        expect(location.location, 'specs/features/x.feature:7:3');
      },
    );
  });

  group('freshness gating', () {
    test('editing a test file invalidates the snapshot of registrations', () {
      final tempDir = Directory.systemTemp.createTempSync('zuke-binding-');
      addTearDown(() => deleteTemporaryDirectory(tempDir));
      final testFile = File(p.join(tempDir.path, 'test', 'app_test.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('// v1\n');
      final config = File(p.join(tempDir.path, 'zuke.yaml'))
        ..writeAsStringSync('schemaVersion: 3\n');

      final before = _index(
        root: tempDir.path,
        inputPaths: [config.path, testFile.path],
        obligations: [
          _obligation('RULE-1', [_slot()], ['SCN-1']),
        ],
        registrations: const [],
        runnerScopes: _scope(),
      );
      expect(before.freshnessIssues(root: tempDir.path), isEmpty);

      // Someone adds the widget test that closes the gap. The recorded index
      // still says the slot is unbound, so it must not be consulted: reporting it
      // would accuse the workspace of a gap it has just closed.
      testFile.writeAsStringSync('// v2 with a widget test\n');
      final after = before.freshnessIssues(root: tempDir.path);
      expect(
        after.map((issue) => issue.kind.facetFor(issue.path)),
        contains(ZukeIndexFreshnessFacet.sources),
        reason:
            'a Dart input changed, so source-derived registrations are in '
            'question and the rule must stay silent',
      );
      expect(after.sourcesFresh, isFalse);
      expect(after.consultableFacts(indexReadable: true).sources, isFalse);
      expect(
        after.consultableFacts(indexReadable: true).specification,
        isTrue,
        reason:
            'only the source family moved, so a source-only rule would still '
            'run while the binding rule must not',
      );
    });

    test('deleting a test file invalidates the recorded inventory', () {
      final tempDir = Directory.systemTemp.createTempSync('zuke-binding-');
      addTearDown(() => deleteTemporaryDirectory(tempDir));
      final testDir = Directory(p.join(tempDir.path, 'test'))
        ..createSync(recursive: true);
      final first = File(p.join(testDir.path, 'a_test.dart'))
        ..writeAsStringSync('// a\n');
      final second = File(p.join(testDir.path, 'b_test.dart'))
        ..writeAsStringSync('// b\n');
      final config = File(p.join(tempDir.path, 'zuke.yaml'))
        ..writeAsStringSync('schemaVersion: 3\n');
      final inputs = [config.path, first.path, second.path];

      final before = _index(
        root: tempDir.path,
        inputPaths: inputs,
        registrations: [
          _registration('SCN-1', ['flutter-widget']),
        ],
      );
      expect(before.freshnessIssues(root: tempDir.path), isEmpty);

      // The index still lists b_test.dart as an input; it is gone. A registration
      // may have lived there.
      second.deleteSync();
      expect(
        before.freshnessIssues(root: tempDir.path).map((i) => i.kind),
        contains(ZukeIndexFreshnessIssueKind.inputMissing),
      );
      // A fresh scan would not have recorded the deleted file at all.
      final after = _index(
        root: tempDir.path,
        inputPaths: [config.path, first.path],
        registrations: const [],
      );
      expect(after.freshnessIssues(root: tempDir.path), isEmpty);
    });

    test('a specification edit also suppresses the rule', () {
      // The gate needs both families. A stale `.feature` must suppress too, or
      // the rule compares today's registrations against a requirement set from
      // before the edit.
      final tempDir = Directory.systemTemp.createTempSync('zuke-binding-');
      addTearDown(() => deleteTemporaryDirectory(tempDir));
      final feature =
          File(p.join(tempDir.path, 'specs', 'features', 'x.feature'))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('Feature: X\n');

      final before = _index(
        root: tempDir.path,
        inputPaths: [feature.path],
        obligations: [
          _obligation('RULE-1', [_slot()], ['SCN-1']),
        ],
      );
      expect(before.freshnessIssues(root: tempDir.path), isEmpty);

      feature.writeAsStringSync('Feature: X\n\n  changed\n');
      final issues = before.freshnessIssues(root: tempDir.path);
      expect(
        issues.map((issue) => issue.kind.facetFor(issue.path)),
        contains(ZukeIndexFreshnessFacet.specification),
      );
      expect(issues.sourcesFresh, isTrue);
      expect(issues.specificationFresh, isFalse);
      final facts = issues.consultableFacts(indexReadable: true);
      expect(
        facts.specification && facts.sources,
        isFalse,
        reason:
            'the rule requires both families, so a specification-only drift is '
            'enough to make it stay silent',
      );
    });

    test('editing the configuration invalidates the recorded runner scopes', () {
      // Adapter attribution comes from configuration, so a config edit has to
      // count or the editor decides a slot against runners that no longer exist.
      final tempDir = Directory.systemTemp.createTempSync('zuke-binding-');
      addTearDown(() => deleteTemporaryDirectory(tempDir));
      final config = File(p.join(tempDir.path, 'zuke.yaml'))
        ..writeAsStringSync('schemaVersion: 3\n');

      final before = _index(
        root: tempDir.path,
        inputPaths: [config.path],
        runnerScopes: _scope(),
      );
      expect(before.freshnessIssues(root: tempDir.path), isEmpty);

      config.writeAsStringSync('schemaVersion: 3\n# a second runner added\n');
      expect(
        before
            .freshnessIssues(root: tempDir.path)
            .map((i) => i.kind.facetFor(i.path)),
        contains(ZukeIndexFreshnessFacet.specification),
        reason:
            'a non-Dart input is read as specification drift, which already '
            'suppresses a rule needing both families',
      );
    });

    test('an edited index is caught by its own digest', () {
      // The binding facts participate in the digest, so a registration inserted
      // after the fact cannot close a gap the editor believes is open.
      final root = Directory.systemTemp.createTempSync('zuke-binding-').path;
      final index = _index(
        root: root,
        obligations: [
          _obligation('RULE-1', [_slot()], ['SCN-1']),
        ],
        registrations: const [],
      );
      expect(index.freshnessIssues(root: root), isEmpty);

      final tampered = ZukeIndex.fromJson({
        ...index.toJson(),
        'managedRegistrations': [
          {
            'scenarioId': 'SCN-1',
            'sourcePath': 'test/x_test.dart',
            'target': 'app',
            'packageId': 'app',
            'evidenceTypes': ['flutter-widget'],
          },
        ],
      });
      expect(
        tampered.freshnessIssues(root: root).map((i) => i.kind),
        contains(ZukeIndexFreshnessIssueKind.inputSetDigestMismatch),
      );
    });
  });

  group('contract', () {
    test('an index without the binding facts is refused, not believed', () {
      expect(
        () => ZukeIndex.fromJson({
          'kind': ZukeIndex.kind,
          'contractVersion': zukeIndexContract,
          'inputDigest': 'sha256:${'0' * 64}',
          'generatedManifestDigest': 'sha256:${'0' * 64}',
          'generatedManifestPath': 'generated-manifest.json',
          'inputs': <Object?>[],
          'inputPatterns': <Object?>[],
          'patternInputs': <Object?>[],
          'requirementIds': <Object?>[],
          'controlIds': <Object?>[],
          'bindingIds': <Object?>[],
        }),
        throwsFormatException,
      );
    });

    test('an index at the previous contract is incompatible', () {
      expect(
        ZukeIndexHeader({
          'contractVersion': zukeIndexContract - 1,
        }).isIncompatible,
        isTrue,
        reason:
            'an older snapshot cannot say what it did not record, so reading it '
            'would be guessing',
      );
    });
  });

  group('scope', () {
    test('a selection narrows which scenarios an unbound finding names', () {
      // Whole-workspace scope is what the editor does: no selection, so every
      // affected scenario is named. A profile-scoped `zuke validate` run names
      // fewer. The verdicts agree; only the named set differs.
      final obligation = _obligation('RULE-1', [_slot()], ['SCN-A', 'SCN-B']);
      final engine = const BindingVerdictEngine();

      final whole = engine.compute(
        obligations: [obligation],
        registrations: const [],
        runnerScopes: _scope(),
      );
      expect(whole.findings.single.scenarioIds, ['SCN-A', 'SCN-B']);

      final scoped = engine.compute(
        obligations: [obligation],
        registrations: const [],
        runnerScopes: _scope(),
        selectedScenarioIds: ['SCN-B'],
      );
      expect(scoped.findings.single.verdict, whole.findings.single.verdict);
      expect(scoped.findings.single.scenarioIds, ['SCN-B']);
    });

    test('a selection never changes a verdict', () {
      // A slot satisfied by an out-of-profile scenario is still satisfied. If
      // narrowing the report could turn a bound slot into a gap, the two front
      // ends would disagree for a reason that has nothing to do with evidence.
      final obligation = _obligation('RULE-1', [_slot()], ['SCN-A', 'SCN-B']);
      final engine = const BindingVerdictEngine();
      final registrations = [
        _registration('SCN-A', ['flutter-widget']),
      ];
      final scopes = _scope();

      for (final selection in <List<String>?>[
        null,
        ['SCN-B'],
        ['SCN-A'],
      ]) {
        expect(
          engine
              .compute(
                obligations: [obligation],
                registrations: registrations,
                runnerScopes: scopes,
                selectedScenarioIds: selection,
              )
              .findings
              .single
              .verdict,
          BindingCoverageVerdict.bound,
          reason: 'selection $selection must not decide the verdict',
        );
      }
    });
  });
}

Map<String, BindingCoverageVerdict> _verdictsOf(BindingCoverageReport report) =>
    {
      for (final finding in report.findings)
        '${finding.ruleId}|${finding.slotKey}': finding.verdict,
    };

BindingCoverageVerdict? _verdictOf(
  BindingCoverageReport report,
  String ruleId,
) {
  for (final finding in report.findings) {
    if (finding.ruleId == ruleId) return finding.verdict;
  }
  return null;
}

EvidenceObligation _obligation(
  String ruleId,
  List<Map<String, String>> slots,
  List<String> scenarioIds,
) => EvidenceObligation(
  featureId: 'FEAT-1',
  ruleId: ruleId,
  scenarioIds: scenarioIds,
  slots: slots,
  location: const FeatureLocation(
    file: 'specs/features/x.feature',
    line: 7,
    column: 3,
  ),
);

ManagedRegistrationFact _registration(
  String scenarioId,
  List<String>? evidenceTypes,
) => ManagedRegistrationFact(
  scenarioId: scenarioId,
  sourcePath: 'test/app_test.dart',
  target: 'app',
  packageId: 'app',
  evidenceTypes: evidenceTypes,
);

List<RunnerScopeFact> _scope() => const [
  RunnerScopeFact(
    target: 'app',
    sourcePackage: 'app',
    adapters: ['dart-source'],
  ),
];

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

ZukeIndex _index({
  String? root,
  List<String> inputPaths = const [],
  List<EvidenceObligation> obligations = const [],
  List<ManagedRegistrationFact> registrations = const [],
  List<RunnerScopeFact> runnerScopes = const [],
  int unresolvedRegistrations = 0,
}) {
  // The manifest has to exist on disk and match, or freshness reports the index
  // as unusable and every facet assertion below becomes vacuous.
  const manifest = '{"files":[]}';
  final temporaryRoot = root == null
      ? Directory.systemTemp.createTempSync('zuke-binding-index-')
      : null;
  root ??= temporaryRoot!.path;
  if (temporaryRoot != null) {
    addTearDown(() => deleteTemporaryDirectory(temporaryRoot));
  }
  final manifestFile = File(p.join(root, 'generated-manifest.json'));
  if (!manifestFile.existsSync()) {
    manifestFile.parent.createSync(recursive: true);
    manifestFile.writeAsStringSync(manifest);
  }
  return ZukeIndex.create(
    root: root,
    inputPaths: inputPaths,
    generatedManifestContent: manifest,
    generatedManifestPath: 'generated-manifest.json',
    requirementIds: const [],
    controlIds: const [],
    bindingIds: const [],
    managedRegistrations: registrations,
    unresolvedManagedRegistrations: unresolvedRegistrations,
    evidenceObligations: obligations,
    runnerScopes: runnerScopes,
  );
}
