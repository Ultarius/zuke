import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart' as test_api;
import 'package:zuke/runner.dart';
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_core/zuke_core.dart';

final _registeredScenarioCases = <String>{};
final _registeredScenarioIds = <String>{};

/// Registers a normal Dart test that can publish evidence when launched by
/// the Zuke CLI.
///
/// With no managed runner environment this is exactly an ordinary test and
/// produces no evidence. A partial managed environment is rejected before
/// the body runs so a passing test can never publish an incomplete identity.
void zukeTest(
  Object? description,
  FutureOr<dynamic> Function() body, {
  required ZukeScenarioContract scenario,
  Iterable<String> evidenceTypes = const [],
  Set<ControlId> provedControls = const {},
  Iterable<String> provedImplementationSlots = const [],
  String? caseId,
  String? testOn,
  test_api.Timeout? timeout,
  Object? skip,
  Object? tags,
  Map<String, dynamic>? onPlatform,
  int? retry,
}) {
  final context = RunnerExecutionContext.fromEnvironment(Platform.environment);
  final selectedScenarios = scenarioFilterFromEnvironment(Platform.environment);
  final scenarioSkip = shouldRunScenario(scenario.id.value, selectedScenarios)
      ? null
      : 'Scenario filtered by Zuke';
  final types = evidenceTypes.toSet().toList();
  final implementationSlots = provedImplementationSlots.toSet().toList()
    ..sort();
  if (context != null) {
    if (types.isEmpty) {
      throw ArgumentError.value(
        evidenceTypes,
        'evidenceTypes',
        'Managed Zuke tests must declare at least one evidence type.',
      );
    }
    final scenarioControls = scenario.controlIds;
    final invalidControls = provedControls
        .where((control) => !scenarioControls.contains(control))
        .map((control) => control.value)
        .toList(growable: false);
    if (invalidControls.isNotEmpty) {
      throw ArgumentError(
        'Proved controls are not declared by ${scenario.id.value}: '
        '${invalidControls.join(', ')}',
      );
    }
    final invalidSlots = implementationSlots
        .where((slot) => !isValidBindingSlot(slot))
        .toList(growable: false);
    if (invalidSlots.isNotEmpty) {
      throw ArgumentError(
        'Implementation slots must be stable kebab-case tokens: '
        '${invalidSlots.join(', ')}',
      );
    }
    final scenarioAlreadyRegistered = _registeredScenarioIds.contains(
      scenario.id.value,
    );
    if (scenarioAlreadyRegistered &&
        (caseId == null || caseId.trim().isEmpty)) {
      throw ArgumentError(
        'Scenario ${scenario.id.value} is registered more than once; '
        'provide a stable caseId for each case.',
      );
    }
    if (caseId != null && caseId.trim().isEmpty) {
      throw ArgumentError.value(caseId, 'caseId', 'must be non-empty');
    }
    final key = '${scenario.id.value}|${caseId ?? ''}';
    if (!_registeredScenarioCases.add(key)) {
      throw ArgumentError(
        'Scenario ${scenario.id.value} case ${caseId ?? '(default)'} '
        'is registered more than once.',
      );
    }
    _registeredScenarioIds.add(scenario.id.value);
  }

  test_api.test(
    description,
    () async {
      await body();
      if (context == null) return;
      const emitter = SuiteEvidenceEmitter();
      final sortedTypes = [...types]..sort();
      final selectionDigest = Platform.environment['ZUKE_SELECTION_DIGEST'];
      final digestInput = canonicalJson({
        'scenarioId': scenario.id.value,
        'requirementId': scenario.requirementId.value,
        'title': scenario.title,
        'controlIds':
            scenario.controlIds.map((control) => control.value).toList()
              ..sort(),
        'provedControls':
            provedControls.map((control) => control.value).toList()..sort(),
        'provedImplementationSlots': implementationSlots,
        'evidenceTypes': sortedTypes,
        'caseId': caseId,
        'profile': context.profile,
        'target': context.target,
        'runnerId': context.runnerId,
        'runnerCompatibilityId': context.runnerCompatibilityId,
        'sourceIdentity': context.sourceIdentity.toJson(),
        if (selectionDigest != null && selectionDigest.isNotEmpty)
          'selectionDigest': selectionDigest,
      });
      emitter.emitPassing(
        requirementId: scenario.requirementId.value,
        scenarioId: scenario.id,
        evidenceTypes: sortedTypes,
        target: context.target,
        runnerCompatibilityId: context.runnerCompatibilityId,
        digestInput: sha256.convert(utf8.encode(digestInput)).toString(),
        controlIds: provedControls.map((control) => control.value),
        implementationSlots: implementationSlots,
        profile: context.profile,
        runnerId: context.runnerId,
        outputDirectory: context.resultDirectory,
        sourceIdentity: context.sourceIdentity,
        caseId: caseId,
      );
    },
    testOn: testOn,
    timeout: timeout,
    skip: scenarioSkip ?? skip,
    tags: tags,
    onPlatform: onPlatform,
    retry: retry,
  );
}
