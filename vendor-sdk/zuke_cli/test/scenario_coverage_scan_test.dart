import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/configuration_preflight.dart';
import 'package:zuke_cli/src/spec_lint_scan.dart';
import 'package:zuke_cli/src/workspace_annotation_scan.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'support/resolved_workspace.dart';
import 'support/temporary_directory.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('zuke-scenario-coverage-');
    await configureFixturePackages(root);
  });
  tearDown(() => deleteTemporaryDirectory(root));

  File source(String path, String content) {
    final file = File.fromUri(root.uri.resolve(path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  WorkspaceDiscoveryResult workspace() => WorkspaceDiscoveryResult(
    config: ZukeConfig(
      workspaceTargets: {
        'app': WorkspaceTarget(
          id: 'app',
          language: 'dart',
          framework: 'flutter',
          packages: [
            WorkspacePackage(id: 'fixture', path: '.', roots: const ['lib']),
          ],
        ),
      },
    ),
    data: const MetadataExtractorResult(),
  );

  test('declared scenarios without a managed registration are reported', () {
    source(
      'pubspec.yaml',
      "name: fixture\nenvironment:\n  sdk: '>=3.10.0 <4.0.0'\n",
    );
    source('zuke.yaml', '''
schemaVersion: 3
workspace:
  name: fixture
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets:
  app:
    language: dart
    framework: flutter
    packages:
      - id: app
        path: .
        roots: [lib]
''');
    source('specs/features/demo.feature', '''
# spec-begin
# schemaVersion: 1
# id: FEAT-DEMO-001
# spec-end

@FEAT-DEMO-001
Feature: Demo
  A user can do a thing.

  # rule-spec-begin
  # id: RULE-DEMO-001
  # rule-spec-end
  @RULE-DEMO-001
  Rule: Things work

    @SCN-DEMO-001
    Scenario: A registered thing
      Given a thing
      When the user does it
      Then it works

    @SCN-DEMO-002
    Scenario: An unregistered thing
      Given a thing
      When the user does it
      Then it works
''');
    final parsed = requireCurrentWorkspace(root.path);

    final diagnostics = scanScenarioCoverage(
      parsed,
      root: root.path,
      registeredScenarioIds: const {'SCN-DEMO-001'},
    );

    expect(diagnostics, hasLength(1));
    final finding = diagnostics.single;
    expect(finding.code, 'ZUKE-SCENARIO-UNVERIFIED');
    expect(finding.severity, 'warning');
    expect(finding.featureId, 'FEAT-DEMO-001');
    expect(finding.file, 'specs/features/demo.feature');
    expect(finding.message, contains('SCN-DEMO-002'));
    expect(finding.line, greaterThan(1));
  });

  test(
    'managed registrations resolve to their constant scenario IDs',
    () async {
      source('lib/fake_contract.dart', '''
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

const fake = FakeScenario(
  ScenarioId('SCN-FAKE-001'),
  RuleId('RULE-FAKE-001'),
  'A fake scenario',
  <ControlId>{},
);
''');
      source('lib/registrations.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'fake_contract.dart';

void register() {
  zukeTest(() {}, scenario: fake);
}
''');

      final scan = await scanWorkspaceAnnotations(root.path, workspace());

      expect(scan.unresolvedManagedRegistrations, 0);
      expect(scan.managedScenarioIds, contains('SCN-FAKE-001'));
      final claim = scan.managedScenarios.single;
      expect(claim.sourcePath, 'lib/registrations.dart');
      expect(claim.target, 'app');
    },
    // These fixtures need the real Flutter registration to prove library
    // identity. Loading its SDK graph under coverage can exceed the
    // default 30s on a busy Windows runner; keep a finite per-test budget.
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a non-constant scenario makes coverage unknown, not empty',
    () async {
      source('lib/fake_contract.dart', '''
import 'package:zuke_annotations/zuke_annotations.dart';

const fake = _Fake(
  ScenarioId('SCN-FAKE-002'),
  RuleId('RULE-FAKE-002'),
  'A fake scenario',
  <ControlId>{},
);

class _Fake implements ZukeScenarioContract {
  const _Fake(this.id, this.requirementId, this.title, this.controlIds);

  @override
  final ScenarioId id;
  @override
  final RuleId requirementId;
  @override
  final String title;
  @override
  final Set<ControlId> controlIds;
}
''');
      source('lib/registrations.dart', '''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';

void register(ZukeScenarioContract scenario) {
  zukeTest(() {}, scenario: scenario);
}
''');

      final scan = await scanWorkspaceAnnotations(root.path, workspace());

      expect(scan.managedScenarioIds, isEmpty);
      expect(scan.unresolvedManagedRegistrations, 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
