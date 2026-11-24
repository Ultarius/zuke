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
final class ManagedBindingFixture {
  late Directory root;

  /// Registers per-test setup and teardown in the calling suite.
  ManagedBindingFixture() {
    setUp(_createWorkspace);
    tearDown(() => deleteTemporaryDirectory(root));
  }

  ManagedBindingFixture._();

  Future<void> _createWorkspace() async {
    root = Directory.systemTemp.createTempSync('zuke-binding-scan-');
    source(
      'pubspec.yaml',
      "name: fixture\nenvironment:\n  sdk: '>=3.10.0 <4.0.0'\n",
    );
    await configureFixturePackages(root);
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
}

/// Resolves independent, fully identified harness registrations together.
///
/// Each case has its own library so declarations remain isolated, but the
/// analyzer can link the real Flutter dependencies once for the workspace.
final class ManagedHarnessCases {
  final _sources = <String, String>{};
  late final _result = _scan();

  Future<List<ManagedScenarioClaim>> Function() add(String body) {
    final path = 'app/test/case_${_sources.length}.dart';
    _sources[path] =
        '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';

$body
''';
    return () async => (await _result).managedScenarios
        .where((claim) => claim.sourcePath == path)
        .toList();
  }

  void testKinds(
    String description, {
    required String harness,
    required String cases,
    required Object? expected,
  }) {
    final claims = add('''
$harness

void main() {
  evidenceHarness.registerAll([
$cases
  ]);
}
''');
    test(description, () async {
      expect((await claims()).single.evidenceTypes, expected);
    });
  }

  Future<WorkspaceAnnotationScan> _scan() async {
    final fixture = ManagedBindingFixture._();
    try {
      await fixture._createWorkspace();
      fixture.contract();
      for (final entry in _sources.entries) {
        fixture.source(entry.key, entry.value);
      }
      final result = await fixture.scan();
      expect(result.unresolvedManagedRegistrations, 0);
      return result;
    } finally {
      await deleteTemporaryDirectory(fixture.root);
    }
  }
}
