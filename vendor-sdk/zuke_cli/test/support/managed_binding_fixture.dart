import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/workspace_annotation_scan.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'resolved_workspace.dart';
import 'temporary_directory.dart';

/// Fixtures that go through the real resolver.
///
/// Constructing [ManagedScenarioClaim] by hand bypasses exactly the defects
/// that matter here: how a registration's evidence kinds are read, how its
/// provenance is attributed, and whether two registrations of one scenario stay
/// separate. Every test using this fixture resolves actual source.
///
/// Resolution is the slow part of these tests, so they are spread over several
/// files for the test runner to schedule concurrently.
final class ManagedBindingFixture {
  late Directory root;

  /// Registers per-test setup and teardown in the calling suite.
  ManagedBindingFixture() {
    setUp(() async {
      root = Directory.systemTemp.createTempSync('zuke-binding-scan-');
      await configureFixturePackages(root);
      source(
        'pubspec.yaml',
        "name: fixture\nenvironment:\n  sdk: '>=3.10.0 <4.0.0'\n",
      );
    });
    tearDown(() => deleteTemporaryDirectory(root));
  }

  File source(String path, String content) {
    final file = File.fromUri(root.uri.resolve(path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  /// A contract declaring one scenario, so registrations can name it.
  void contract({String scenario = 'SCN-DEMO-001'}) =>
      source('lib/demo_contract.dart', '''
import 'package:zuke_annotations/zuke_annotations.dart';

class FakeScenario implements ZukeScenarioContract {
  const FakeScenario(this.id, this.requirementId, this.title, this.controlIds);

  @override
  final ScenarioId id;
  @override
  final RuleId requirementId;
  @override
  final String title;
  @override
  final Set<ControlId> controlIds;
}

const demo = FakeScenario(
  ScenarioId('$scenario'),
  RuleId('RULE-DEMO-001'),
  'A demo scenario',
  <ControlId>{},
);
''');

  /// A workspace with two targets, so provenance can be told apart.
  WorkspaceDiscoveryResult workspace() => WorkspaceDiscoveryResult(
    config: const ZukeConfig(
      workspaceTargets: {
        'app': WorkspaceTarget(
          id: 'app',
          language: 'dart',
          framework: 'flutter',
          packages: [
            WorkspacePackage(
              id: 'app-pkg',
              path: 'app',
              roots: ['lib', 'test'],
            ),
          ],
        ),
        // Declares no path, so `workspacePackageTargets` cannot map it and its
        // files reach the scan unattributed. This is the shape that produces a
        // null target from real source.
        'loose': WorkspaceTarget(
          id: 'loose',
          language: 'dart',
          framework: 'dart',
          packages: [
            WorkspacePackage(id: 'loose-pkg', path: '', roots: ['test']),
          ],
        ),
        'backend': WorkspaceTarget(
          id: 'backend',
          language: 'dart',
          framework: 'dart',
          packages: [
            WorkspacePackage(
              id: 'api-pkg',
              path: 'api',
              roots: ['lib', 'test'],
            ),
          ],
        ),
      },
    ),
    data: const MetadataExtractorResult(),
  );

  Future<WorkspaceAnnotationScan> scan() =>
      scanWorkspaceAnnotations(root.path, workspace());

  /// Registers [declaration] from a file in the app package and returns the
  /// kinds the scan read off it. Null means the scan could not know them.
  Future<List<String>?> kindsOf(String declaration) async {
    contract();
    source('app/test/app_test.dart', '''
import 'package:zuke_runner/zuke_runner.dart';
import 'package:fixture/demo_contract.dart';

const more = ['domain-unit'];

void main() {
  zukeTest(() {}, scenario: demo, evidenceTypes: $declaration);
}
''');
    final claims = (await scan()).managedScenarios;
    return claims.single.evidenceTypes;
  }

  /// Registers one harness case and returns the kinds inherited for it.
  Future<List<String>?> harnessKinds({
    required String harness,
    required String cases,
  }) async {
    contract();
    source('app/test/app_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';

$harness

void main() {
  evidenceHarness.registerAll([
$cases
  ]);
}
''');
    return (await scan()).managedScenarios.single.evidenceTypes;
  }

  /// Registers one case under each of two harnesses and returns their kinds in
  /// registration order, so per-harness attribution is observable.
  Future<List<List<String>?>> twoHarnessKinds({
    required String readable,
    required String unreadable,
  }) async {
    contract();
    source('app/test/app_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';

final otherScenario = FakeScenario(
  ScenarioId('SCN-DEMO-002'),
  RuleId('RULE-DEMO-001'),
  'Another demo scenario',
  <ControlId>{},
);

$readable
$unreadable

void main() {
  readableHarness.registerAll([
    FlutterEvidenceCase(scenario: demo, body: (tester) async {}),
  ]);
  dynamicHarness.registerAll([
    FlutterEvidenceCase(scenario: otherScenario, body: (tester) async {}),
  ]);
}
''');
    final result = await scan();
    final Map<String, ManagedScenarioClaim> byScenario = {
      for (final claim in result.managedScenarios) claim.scenarioId: claim,
    };
    return [
      byScenario['SCN-DEMO-001']?.evidenceTypes,
      byScenario['SCN-DEMO-002']?.evidenceTypes,
    ];
  }
}
