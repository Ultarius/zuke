import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/workspace_annotation_scan.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'support/managed_binding_fixture.dart';

void main() {
  final fixture = ManagedBindingFixture();
  final source = fixture.source;
  final contract = fixture.contract;
  final scan = fixture.scan;
  final harnessKinds = fixture.harnessKinds;

  group('scenario harness registration', () {
    const oneCase =
        '    FlutterEvidenceCase(scenario: demo, body: (tester) async {}),';

    test('a harness alias retains its registering owner', () async {
      expect(
        await harnessKinds(
          harness: '''
const original = ZukeFlutterEvidenceHarness(
  runnerCompatibilityId: 'app-runner-v1',
  defaultEvidenceTypes: ['flutter-widget'],
);
final evidenceHarness = original;
''',
          cases: oneCase,
        ),
        ['flutter-widget'],
      );
    });

    for (final cascade in [false, true]) {
      test('named case lists resolve with cascade=$cascade', () async {
        contract();
        source('app/test/app_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';
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
        final result = await scan();
        expect(result.managedScenarios.single.evidenceTypes, [
          'flutter-widget',
        ]);
        expect(result.unresolvedManagedRegistrations, 0);
      });
    }

    test('unused constructions do not register cases', () async {
      contract();
      source('app/test/app_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';
void main() {
  const harness = ZukeFlutterEvidenceHarness(
    runnerCompatibilityId: 'app-runner-v1',
    defaultEvidenceTypes: ['flutter-widget'],
  );
  final unused = FlutterEvidenceCase(scenario: demo, body: (_) async => 'ok');
}
''');
      final result = await scan();
      expect(result.managedScenarios, isEmpty);
      expect(result.unresolvedManagedRegistrations, 0);
    });

    test(
      'a reassigned harness is unresolved rather than its initializer',
      () async {
        contract();
        source('app/test/app_test.dart', '''
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
        final result = await scan();
        expect(result.managedScenarios, isEmpty);
        expect(result.unresolvedManagedRegistrations, 1);
      },
    );

    test('a case publishes the variant its harness emits', () async {
      contract();
      source('app/test/app_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';

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
      expect((await scan()).managedScenarios.single.variant, 'dark-mode');
    });

    test('an unreadable harness variant stays unknown', () async {
      contract();
      source('app/test/app_test.dart', '''
import 'package:zuke_runner_flutter/zuke_runner_flutter.dart';
import 'package:fixture/demo_contract.dart';

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
      expect((await scan()).managedScenarios.single.variant, isNull);
    });

    test(
      'runner tests outside extraction roots count as registrations',
      () async {
        contract();
        final testFile = source('app/test/app_test.dart', '''
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
}
