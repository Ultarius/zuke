import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';
import 'package:zuke_test_support/src/temporary_directory.dart';
import 'package:zuke_analyzer/main.dart' as analyzer_plugin;
import 'package:zuke_analyzer/src/plugin_visitors.dart';
import 'package:zuke_cli/editor.dart';

/// The editor-side acceptance surface for binding coverage.
///
/// The claim under test is narrow and falsifiable: a gap the CLI reports appears
/// in the editor, on the rule that declared it, exactly once. Everything else the
/// analyzer package already tests.
void main() {
  late Directory tempDir;
  late File contract;
  late File indexFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('zuke-binding-plugin-');
    File(
      '${tempDir.path}${Platform.pathSeparator}pubspec.yaml',
    ).writeAsStringSync('name: binding_fixture\nenvironment:\n  sdk: ^3.6.0\n');
    File(
      '${tempDir.path}${Platform.pathSeparator}zuke.yaml',
    ).writeAsStringSync('schemaVersion: 3\n');
    File(
      '${tempDir.path}${Platform.pathSeparator}generated-manifest.json',
    ).writeAsStringSync('{"files":[]}');
    contract = _writeContract(tempDir, '''
abstract final class FeatGap001RuleIds {
  static const listItems = 'RULE-GAP-LIST';
  static const listItemsId = 'RULE-GAP-LIST';
  static const covered = 'RULE-GAP-COVERED';
  static const coveredId = 'RULE-GAP-COVERED';
}

/// A second declaration of the same rule, as an aggregate or alias would produce.
/// It must not become a second owner.
abstract final class FeatGap001Aliases {
  static const listItemsAlias = 'RULE-GAP-LIST';
}
''');
    indexFile = File(
      '${tempDir.path}${Platform.pathSeparator}.zuke'
      '${Platform.pathSeparator}analyzer-index.json',
    )..parent.createSync(recursive: true);
  });

  tearDown(() => deleteTemporaryDirectory(tempDir));

  /// Writes a current index: no registration satisfies the widget slot, so both
  /// rules in the contract are genuinely unbound.
  void writeIndex({List<String> inputPaths = const []}) {
    final index = ZukeIndex.create(
      root: tempDir.path,
      inputPaths: [...inputPaths, File('${tempDir.path}/zuke.yaml').path],
      generatedManifestContent: '{"files":[]}',
      generatedManifestPath: 'generated-manifest.json',
      requirementIds: const [],
      controlIds: const [],
      bindingIds: const [],
      managedRegistrations: const [],
      unresolvedManagedRegistrations: 0,
      evidenceObligations: [
        for (final rule in ['RULE-GAP-LIST', 'RULE-GAP-COVERED'])
          EvidenceObligation(
            featureId: 'FEAT-GAP-001',
            ruleId: rule,
            scenarioIds: const ['SCN-GAP-001'],
            slots: const [
              {
                'type': 'flutter-widget',
                'target': 'app',
                'sourcePackage': 'app',
                'sourceAdapter': 'dart-source',
                'variant': 'default',
              },
            ],
          ),
      ],
      runnerScopes: const [
        RunnerScopeFact(
          target: 'app',
          sourcePackage: 'app',
          adapters: ['dart-source'],
        ),
      ],
      featureFiles: const {
        'FEAT-GAP-001': 'lib/src/generated/feat_gap_001_contracts.g.dart',
      },
    );
    indexFile.writeAsStringSync(jsonEncode(index.toJson()));
    analyzer_plugin.zukeClearIndexCacheForTesting();
  }

  group('ZukeBindingCoverageVisitor', () {
    test('reports each unbound slot once, on its own rule constant', () async {
      final unit = await _unitFor(contract);
      final reported = <String>[];
      final anchors = <AstNode>[];

      _walk(
        unit,
        ZukeBindingCoverageVisitor(
          findings: [_unbound('RULE-GAP-LIST'), _unbound('RULE-GAP-COVERED')],
          report: (anchor, finding) {
            anchors.add(anchor);
            reported.add(finding.ruleId);
          },
        ),
      );

      // Five constants spell two rules; two findings. The `...Id = RuleId('…')`
      // companions are constructor calls and cannot match, and the alias must not
      // become a second owner.
      expect(reported, ['RULE-GAP-LIST', 'RULE-GAP-COVERED']);
      expect(anchors, everyElement(isA<VariableDeclaration>()));
      expect(anchors.map((a) => (a as VariableDeclaration).name.lexeme), [
        'listItems',
        'covered',
      ]);
    });

    test('a rule with two unbound slots reports both, once each', () async {
      final unit = await _unitFor(contract);
      final reported = <String>[];
      _walk(
        unit,
        ZukeBindingCoverageVisitor(
          findings: [
            _unbound('RULE-GAP-LIST'),
            _unbound('RULE-GAP-LIST', type: 'integration-test'),
          ],
          report: (anchor, finding) => reported.add(finding.type),
        ),
      );
      expect(reported, ['flutter-widget', 'integration-test']);
    });

    test('a finding for another rule reports nothing here', () async {
      final unit = await _unitFor(contract);
      final reported = <String>[];
      _walk(
        unit,
        ZukeBindingCoverageVisitor(
          findings: [_unbound('RULE-SOMEWHERE-ELSE')],
          report: (anchor, finding) => reported.add(finding.ruleId),
        ),
      );
      expect(reported, isEmpty);
    });
  });

  group('ZukeBindingUnboundRule', () {
    test('both unbound rules are reported for the owning contract', () {
      writeIndex();
      final findings = analyzer_plugin.zukeBindingUnboundFindingsForTesting(
        contract.path,
      );
      expect(
        findings.map((f) => f.ruleId).toList()..sort(),
        ['RULE-GAP-COVERED', 'RULE-GAP-LIST'],
        reason:
            'one finding per rule/slot, and no repeats from the alias or the Id '
            'companions',
      );
      expect(
        analyzer_plugin.zukeBindingUnboundAppliesForTesting(contract.path),
        isTrue,
      );
    });

    test('a contract for another feature claims none of these findings', () {
      writeIndex();
      final other = _writeContract(
        tempDir,
        "abstract final class FeatOther001RuleIds {\n"
        "  static const listItems = 'RULE-GAP-LIST';\n}\n",
        name: 'feat_other_001_contracts.g.dart',
      );
      expect(
        analyzer_plugin.zukeBindingUnboundFindingsForTesting(other.path),
        isEmpty,
        reason:
            'feature ownership is what gives a finding one owner; another '
            "feature's contract repeating the rule ID must not report it",
      );
    });

    test('a file that is not a generated contract is never an owner', () {
      writeIndex();
      final handWritten =
          File(
              '${tempDir.path}${Platform.pathSeparator}lib'
              '${Platform.pathSeparator}rule_ids.dart',
            )
            ..parent.createSync(recursive: true)
            ..writeAsStringSync(
              "abstract final class Mine {\n"
              "  static const listItems = 'RULE-GAP-LIST';\n}\n",
            );
      expect(
        analyzer_plugin.zukeBindingUnboundFindingsForTesting(handWritten.path),
        isEmpty,
      );
    });

    test('a bound slot produces no finding', () {
      writeIndex();
      // Same index, but a registration that satisfies the widget slot for one
      // rule's scenario.
      final index = ZukeIndex.create(
        root: tempDir.path,
        inputPaths: [File('${tempDir.path}/zuke.yaml').path],
        generatedManifestContent: '{"files":[]}',
        generatedManifestPath: 'generated-manifest.json',
        requirementIds: const [],
        controlIds: const [],
        bindingIds: const [],
        managedRegistrations: const [
          ManagedRegistrationFact(
            scenarioId: 'SCN-GAP-001',
            sourcePath: 'test/gap_widget_test.dart',
            target: 'app',
            packageId: 'app',
            evidenceTypes: ['flutter-widget'],
          ),
        ],
        evidenceObligations: [
          EvidenceObligation(
            featureId: 'FEAT-GAP-001',
            ruleId: 'RULE-GAP-LIST',
            scenarioIds: const ['SCN-GAP-001'],
            slots: const [
              {
                'type': 'flutter-widget',
                'target': 'app',
                'sourcePackage': 'app',
                'sourceAdapter': 'dart-source',
                'variant': 'default',
              },
            ],
          ),
        ],
        runnerScopes: const [
          RunnerScopeFact(
            target: 'app',
            sourcePackage: 'app',
            adapters: ['dart-source'],
          ),
        ],
        featureFiles: const {
          'FEAT-GAP-001': 'lib/src/generated/feat_gap_001_contracts.g.dart',
        },
      );
      indexFile.writeAsStringSync(jsonEncode(index.toJson()));
      analyzer_plugin.zukeClearIndexCacheForTesting();
      expect(
        analyzer_plugin.zukeBindingUnboundFindingsForTesting(contract.path),
        isEmpty,
        reason:
            'the registration closes the slot, so claiming a gap here would '
            'send someone to write a test that already exists',
      );
    });

    test('a source drift suppresses the rule entirely', () {
      final source =
          File(
              '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}app.dart',
            )
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('void main() {}\n');
      writeIndex(inputPaths: [source.path]);
      expect(
        analyzer_plugin.zukeBindingUnboundAppliesForTesting(contract.path),
        isTrue,
        reason: 'current index, so the gap is reportable',
      );

      source.writeAsStringSync('void main() {}\n// edited\n');
      analyzer_plugin.zukeClearIndexCacheForTesting();
      expect(
        analyzer_plugin.zukeBindingUnboundFindingsForTesting(contract.path),
        isEmpty,
        reason:
            'a Dart input moved, so the registrations are in question and the '
            'rule must say nothing rather than accuse',
      );
    });

    test('a specification drift suppresses the rule entirely', () {
      final feature =
          File(
              '${tempDir.path}${Platform.pathSeparator}specs${Platform.pathSeparator}'
              'features${Platform.pathSeparator}gap.feature',
            )
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('Feature: Gap\n');
      writeIndex(inputPaths: [feature.path]);
      expect(
        analyzer_plugin.zukeBindingUnboundAppliesForTesting(contract.path),
        isTrue,
      );

      feature.writeAsStringSync('Feature: Gap\n\n  a new rule\n');
      analyzer_plugin.zukeClearIndexCacheForTesting();
      expect(
        analyzer_plugin.zukeBindingUnboundFindingsForTesting(contract.path),
        isEmpty,
        reason:
            'the slots come from the specification, so a stale one cannot be '
            'compared against today\'s registrations',
      );
    });

    test('a missing index suppresses the rule', () {
      writeIndex();
      indexFile.deleteSync();
      analyzer_plugin.zukeClearIndexCacheForTesting();
      expect(
        analyzer_plugin.zukeBindingUnboundFindingsForTesting(contract.path),
        isEmpty,
      );
    });

    test('an index from the previous contract is not consulted', () {
      // Absent facts cannot be read as "nothing registered": that would report
      // every slot as a gap. The old contract is refused instead.
      final stale = ZukeIndex.create(
        root: tempDir.path,
        inputPaths: [File('${tempDir.path}/zuke.yaml').path],
        generatedManifestContent: '{"files":[]}',
        generatedManifestPath: 'generated-manifest.json',
        requirementIds: const [],
        controlIds: const [],
        bindingIds: const [],
      );
      final json = stale.toJson()
        ..['contractVersion'] = zukeIndexContract - 1
        ..remove('managedRegistrations')
        ..remove('evidenceObligations')
        ..remove('runnerScopes')
        ..remove('unresolvedManagedRegistrations');
      indexFile.writeAsStringSync(jsonEncode(json));
      analyzer_plugin.zukeClearIndexCacheForTesting();
      expect(
        analyzer_plugin.zukeBindingUnboundFindingsForTesting(contract.path),
        isEmpty,
      );
    });
  });
}

File _writeContract(
  Directory root,
  String body, {
  String name = 'feat_gap_001_contracts.g.dart',
}) {
  final generated = Directory(
    '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}src'
    '${Platform.pathSeparator}generated',
  )..createSync(recursive: true);
  return File('${generated.path}${Platform.pathSeparator}$name')
    ..writeAsStringSync(body);
}

Future<AstNode> _unitFor(File file) async {
  // Both sides resolved, and that is the whole fix. `systemTemp` is reached
  // through a symlink on macOS (`/var` -> `/private/var`), so a collection
  // rooted at the unresolved path does not contain the *resolved* file path, and
  // `contextFor` reports it cannot find a context for it. Registering the
  // resolved root and asking for the resolved file keeps them in the same
  // spelling on every platform.
  final root = file.parent.parent.parent.resolveSymbolicLinksSync();
  final collection = AnalysisContextCollection(includedPaths: [root]);
  addTearDown(collection.dispose);
  final normalized = file.resolveSymbolicLinksSync();
  final result = await collection
      .contextFor(normalized)
      .currentSession
      .getResolvedUnit(normalized);
  return (result as ResolvedUnitResult).unit;
}

/// Applies [visitor] to every node, mirroring how the analysis server drives a
/// registered visitor.
void _walk(AstNode node, AstVisitor<void> visitor) {
  node.accept(visitor);
  for (final child in node.childEntities.whereType<AstNode>()) {
    _walk(child, visitor);
  }
}

BindingCoverageFinding _unbound(
  String ruleId, {
  String type = 'flutter-widget',
}) => BindingCoverageFinding(
  featureId: 'FEAT-GAP-001',
  ruleId: ruleId,
  scenarioIds: const ['SCN-GAP-001'],
  slot: {
    'type': type,
    'target': 'app',
    'sourcePackage': 'app',
    'sourceAdapter': 'dart-source',
    'variant': 'default',
  },
  verdict: BindingCoverageVerdict.unbound,
  location: const FeatureLocation(file: 'specs/features/gap.feature', line: 4),
  reason: "no managed registration names any of this rule's scenarios",
);
