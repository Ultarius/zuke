import 'dart:io';

import 'package:library_catalog/library_catalog.dart';
import 'package:test/test.dart';
import 'package:zuke/zuke.dart';

import 'support/library_fixtures.dart';
import 'support/library_gherkin_steps.dart';
import 'support/library_world.dart';

void main() {
  final feature = ZukeFeatureLoader.load('library_catalog.feature');
  final selectedScenarios = scenarioFilterFromEnvironment(Platform.environment);

  Future<void> runContract(ZukeScenarioContract contract) async {
    if (!shouldRunScenario(contract.id.value, selectedScenarios)) return;
    final resolved = resolveScenarioContract(feature, contract);
    final executor = ScenarioExecutor<LibraryWorld>(
      registry: buildLibraryRegistry(),
      evidenceType: 'domain-unit',
      target: 'catalog',
      profile: 'pullRequest',
      candidateId: contract.id,
      controlIds: contract.controlIds.map((control) => control.value).toSet(),
      runnerId: 'library-catalog-unit-tests',
      runnerCompatibilityId: 'library-catalog-dart-runner-v1',
      digests: const {'runner': 'zuke-runner-v1'},
      sourceIdentity: librarySourceIdentity,
    );
    LibraryWorld? world;
    try {
      world = LibraryWorld();
      final result = await executor.executeScenario(
        feature,
        resolved.rule,
        resolved.scenario,
        () => world!,
      );
      if (result.status != ScenarioStatus.passed) {
        // ignore: avoid_print
        print(result.toJson());
      }
      expect(result.status, ScenarioStatus.passed);
    } finally {
      await world?.dispose();
    }
  }

  group('pure-Dart Gherkin runner', () {
    test('executes checkout scenarios through generated steps', () async {
      for (final contract in CheckoutScenarios.all) {
        await runContract(contract);
      }
    });

    test('executes book-return scenario through generated steps', () async {
      await runContract(BookReturnScenarios.return_);
    });

    test('executes branch peer scenarios over loopback TCP', () async {
      for (final contract in BranchPeerScenarios.all) {
        await runContract(contract);
      }
    });
  });
}
