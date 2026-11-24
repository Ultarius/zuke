import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/workspace_annotation_scan.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'support/managed_binding_fixture.dart';

void main() {
  group('scenario harness registration', () {
    final batch = ManagedHarnessCases();
    batch.testKinds(
      'a harness alias retains its registering owner',
      harness: '''
const original = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: ['flutter-widget'],
);
final evidenceHarness = original;
''',
      cases:
          '    FlutterEvidenceCase(scenario: demo, body: (tester) async {}),',
      expected: ['flutter-widget'],
    );

    for (final cascade in [false, true]) {
      final claims = batch.add('''
void main() {
  final original = FlutterEvidenceCase(scenario: demo, body: (_) async => 'ok');
  final caseAlias = original;
  final cases = [caseAlias];
  ${cascade ? 'ZukeFlutterEvidenceHarness' : 'final harness = ZukeFlutterEvidenceHarness'}(
    runnerCompatibilityId: 'app-runner-v1',
    defaultEvidenceTypes: const ['flutter-widget'],
  )${cascade ? '..registerAll(cases)' : '; harness.registerAll(cases)'};
}
''');
      test('named case lists resolve with cascade=$cascade', () async {
        expect((await claims()).single.evidenceTypes, ['flutter-widget']);
      });
    }

    final unused = batch.add('''
void main() {
  const harness = ZukeFlutterEvidenceHarness(
    runnerCompatibilityId: 'app-runner-v1',
    defaultEvidenceTypes: const ['flutter-widget'],
  );
  final unused = FlutterEvidenceCase(scenario: demo, body: (_) async => 'ok');
}
''');
    test('unused constructions do not register cases', () async {
      expect(await unused(), isEmpty);
    });

    final variant = batch.add('''
const evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'runner-v1',
  defaultEvidenceTypes: ['flutter-widget'],
  variant: 'dark-mode',
);

void main() {
  evidenceHarness.registerAll([
    FlutterEvidenceCase(scenario: demo, body: (tester) async => ''),
  ]);
}
''');
    test('a case publishes the variant its harness emits', () async {
      expect((await variant()).single.variant, 'dark-mode');
    });

    final dynamicVariant = batch.add('''
final name = DateTime.now().toString();
final evidenceHarness = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'runner-v1',
  defaultEvidenceTypes: const ['flutter-widget'],
  variant: name,
);

void main() {
  evidenceHarness.registerAll([
    FlutterEvidenceCase(scenario: demo, body: (tester) async => ''),
  ]);
}
''');
    test('an unreadable harness variant stays unknown', () async {
      expect((await dynamicVariant()).single.variant, isNull);
    });

    group('isolated registration scans', () {
      final fixture = ManagedBindingFixture();
      test(
        'a reassigned harness is unresolved rather than its initializer',
        () async {
          fixture.contract();
          fixture.source('app/test/app_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';
void main() {
  var harness = const ZukeFlutterEvidenceHarness(
    runnerCompatibilityId: 'app-runner-v1',
    defaultEvidenceTypes: ['flutter-widget'],
  );
  harness = buildHarness();
  harness.registerAll([FlutterEvidenceCase(scenario: demo, body: (_) async => 'ok')]);
}
''');
          final result = await fixture.scan();
          expect(result.managedScenarios, isEmpty);
          expect(result.unresolvedManagedRegistrations, 1);
        },
      );

      test(
        'runner tests outside extraction roots count as registrations',
        () async {
          fixture.contract();
          final testFile = fixture.source('app/test/app_test.dart', '''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_runner/zuke_runner.dart';
import 'package:fixture/demo_contract.dart';

@ImplementsRequirement(['RULE-DEMO-001'])
void helper() {}

void main() {
  zukeTest(() {}, scenario: demo, evidenceTypes: const ['domain-unit']);
}
''');
          final result = await scanWorkspaceAnnotations(
            fixture.root.path,
            WorkspaceDiscoveryResult(
              config: const ZukeConfig(
                workspaceTargets: {
                  'app': WorkspaceTarget(
                    id: 'app',
                    language: 'dart',
                    framework: 'dart',
                    packages: [
                      WorkspacePackage(
                        id: 'app-pkg',
                        path: 'app',
                        roots: ['lib'],
                      ),
                    ],
                  ),
                },
                workspaceRunners: [
                  WorkspaceRunner(
                    id: 'app-tests',
                    target: 'app',
                    sourcePackage: 'app-pkg',
                    sourceAdapter: 'dart-source',
                    sourceCompatibilityId: 'dart-source-package-v1',
                    runnerCompatibilityId: 'dart-runner-v1',
                  ),
                ],
              ),
              data: const MetadataExtractorResult(),
            ),
          );

          final claim = result.managedScenarios.single;
          expect(claim.sourcePath, 'app/test/app_test.dart');
          expect(claim.target, 'app');
          expect(claim.packageId, 'app-pkg');
          expect(
            result.claims,
            isEmpty,
            reason: 'a test file is not an implementation source',
          );
          expect(
            result.sourcePaths.map((path) => File(path).absolute.path),
            contains(File(testFile.path).absolute.path),
            reason: 'the index must notice when this file changes',
          );
        },
      );
    });
  });
}
