/// Supported application-facing Flutter scenario integration API.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke/runner.dart';

import 'src/flutter_binding_key.dart';

export 'package:zuke_annotations/zuke_annotations.dart';
export 'package:zuke_frontend/zuke_frontend.dart';
export 'package:zuke/runner.dart';
export 'src/flutter_binding_key.dart';

final _registeredFlutterScenarioCases = <String>{};
final _registeredFlutterScenarioIds = <String>{};

/// Registers a normal Flutter widget test that publishes evidence only when
/// the test process is managed by the Zuke CLI.
void zukeTestWidgets(
  String description,
  Future<void> Function(WidgetTester tester) body, {
  required ZukeScenarioContract scenario,
  Iterable<String> evidenceTypes = const [],
  Set<ControlId> provedControls = const {},
  String? caseId,
  bool? skip,
  Timeout? timeout,
  dynamic tags,
  bool semanticsEnabled = true,
  TestVariant<Object?> variant = const DefaultTestVariant(),
  int? retry,
}) {
  final context = RunnerExecutionContext.fromEnvironment(Platform.environment);
  final selectedScenarios = scenarioFilterFromEnvironment(Platform.environment);
  final scenarioSelected = shouldRunScenario(
    scenario.id.value,
    selectedScenarios,
  );
  final types = evidenceTypes.toSet().toList();
  if (context != null) {
    if (types.isEmpty) {
      throw ArgumentError.value(
        evidenceTypes,
        'evidenceTypes',
        'Managed Zuke widget tests must declare at least one evidence type.',
      );
    }
    final invalidControls = provedControls
        .where((control) => !scenario.controlIds.contains(control))
        .map((control) => control.value)
        .toList(growable: false);
    if (invalidControls.isNotEmpty) {
      throw ArgumentError(
        'Proved controls are not declared by ${scenario.id.value}: '
        '${invalidControls.join(', ')}',
      );
    }
    if (caseId != null && caseId.trim().isEmpty) {
      throw ArgumentError.value(caseId, 'caseId', 'must be non-empty');
    }
    final scenarioAlreadyRegistered = _registeredFlutterScenarioIds.contains(
      scenario.id.value,
    );
    if (scenarioAlreadyRegistered &&
        (caseId == null || caseId.trim().isEmpty)) {
      throw ArgumentError(
        'Scenario ${scenario.id.value} is registered more than once; '
        'provide a stable caseId for each case.',
      );
    }
    final key = '${scenario.id.value}|${caseId ?? ''}';
    if (!_registeredFlutterScenarioCases.add(key)) {
      throw ArgumentError(
        'Scenario ${scenario.id.value} case ${caseId ?? '(default)'} '
        'is registered more than once.',
      );
    }
    _registeredFlutterScenarioIds.add(scenario.id.value);
  }

  testWidgets(
    description,
    (tester) async {
      await body(tester);
      if (context == null) return;
      final sortedTypes = [...types]..sort();
      final digestInput = canonicalJson({
        'scenarioId': scenario.id.value,
        'requirementId': scenario.requirementId.value,
        'title': scenario.title,
        'controlIds':
            scenario.controlIds.map((control) => control.value).toList()
              ..sort(),
        'provedControls':
            provedControls.map((control) => control.value).toList()..sort(),
        'evidenceTypes': sortedTypes,
        'caseId': caseId,
        'profile': context.profile,
        'target': context.target,
        'runnerId': context.runnerId,
        'runnerCompatibilityId': context.runnerCompatibilityId,
        'sourceIdentity': context.sourceIdentity.toJson(),
      });
      const SuiteEvidenceEmitter().emitPassing(
        requirementId: scenario.requirementId.value,
        scenarioId: scenario.id,
        evidenceTypes: sortedTypes,
        target: context.target,
        runnerCompatibilityId: context.runnerCompatibilityId,
        digestInput: sha256.convert(utf8.encode(digestInput)).toString(),
        controlIds: provedControls.map((control) => control.value),
        profile: context.profile,
        runnerId: context.runnerId,
        outputDirectory: context.resultDirectory,
        sourceIdentity: context.sourceIdentity,
        caseId: caseId,
      );
    },
    skip: skip ?? !scenarioSelected,
    timeout: timeout,
    tags: tags,
    semanticsEnabled: semanticsEnabled,
    variant: variant,
    retry: retry,
  );
}

abstract class FlutterScenarioDriver<W extends ScenarioWorld>
    extends FlutterDriverFactory<W> {
  /// Creates a Flutter scenario driver.
  const FlutterScenarioDriver();

  /// Settles the widget tree for [world].
  Future<void> pumpAndSettle(W world);

  /// Captures semantics for [world].
  Future<void> captureSemantics(W world);

  /// Captures a named screenshot for [world].
  Future<void> captureScreenshot(W world, String name);
}

/// Test body for a non-Gherkin Flutter assertion that produces evidence.
///
/// The returned string is hashed only after the body completes successfully.
typedef FlutterEvidenceBody = FutureOr<String> Function(WidgetTester tester);

/// One generated scenario observed by an ordinary Flutter widget test.
final class FlutterEvidenceCase {
  /// Generated scenario observed by the case.
  final ZukeScenarioContract scenario;

  /// Widget-test body that produces the evidence digest input.
  final FlutterEvidenceBody body;

  /// Optional evidence types emitted by the case.
  final Iterable<String>? evidenceTypes;

  /// Creates a Flutter evidence case.
  const FlutterEvidenceCase({
    required this.scenario,
    required this.body,
    this.evidenceTypes,
  });
}

/// Registers Flutter widget cases and publishes evidence after their
/// assertions have passed. This complements [ZukeFlutterHarness] for
/// applications whose tests are not executed through Gherkin steps.
final class ZukeFlutterEvidenceHarness {
  /// Compatibility identifier for the runner.
  final String runnerCompatibilityId;

  /// Target recorded in evidence.
  final String target;

  /// Variant recorded in evidence.
  final String variant;

  /// Evidence types used when a case does not override them.
  final Iterable<String> defaultEvidenceTypes;

  /// Optional execution profile.
  final String? profile;

  /// Optional runner identifier.
  final String? runnerId;

  /// Optional evidence output directory.
  final String? outputDirectory;

  /// Environment used for scenario selection and evidence output.
  final Map<String, String>? environment;

  /// Source identity required by current evidence records. When omitted it is
  /// loaded from the effective environment at test registration time.
  final ExecutionSourceIdentity? sourceIdentity;

  /// Creates an evidence harness.
  const ZukeFlutterEvidenceHarness({
    required this.runnerCompatibilityId,
    required this.defaultEvidenceTypes,
    this.target = 'flutter',
    this.variant = 'default',
    this.profile,
    this.runnerId,
    this.outputDirectory,
    this.environment,
    this.sourceIdentity,
  });

  /// Registers all [cases] as widget tests.
  void registerAll(Iterable<FlutterEvidenceCase> cases) {
    final effectiveEnvironment = environment ?? Platform.environment;
    final context = RunnerExecutionContext.fromEnvironment(
      effectiveEnvironment,
    );
    final managed =
        context != null || sourceIdentity != null || outputDirectory != null;
    final selected = scenarioFilterFromEnvironment(effectiveEnvironment);
    for (final evidenceCase in cases) {
      final evidenceTypes = (evidenceCase.evidenceTypes ?? defaultEvidenceTypes)
          .toSet()
          .toList(growable: false);
      if (managed && evidenceTypes.isEmpty) {
        throw ArgumentError.value(
          evidenceTypes,
          'evidenceTypes',
          'Each Flutter evidence case must emit at least one evidence type.',
        );
      }
      testWidgets(
        '${evidenceCase.scenario.id}: ${evidenceCase.scenario.title}',
        (tester) async {
          final digestInput = await evidenceCase.body(tester);
          if (!managed) return;
          final identity = sourceIdentity ?? context?.sourceIdentity;
          if (identity == null) {
            throw const FormatException(
              'Managed Flutter evidence is missing source identity.',
            );
          }
          const SuiteEvidenceEmitter().emitPassing(
            requirementId: evidenceCase.scenario.requirementId.value,
            scenarioId: evidenceCase.scenario.id,
            evidenceTypes: evidenceTypes,
            target: target,
            variant: variant,
            profile: profile ?? context?.profile,
            runnerId: runnerId ?? context?.runnerId,
            runnerCompatibilityId: runnerCompatibilityId,
            outputDirectory: outputDirectory ?? context?.resultDirectory,
            digestInput: digestInput,
            sourceIdentity: identity,
          );
        },
        skip: !shouldRunScenario(evidenceCase.scenario.id.value, selected),
      );
    }
  }
}

/// Registers generated scenario contracts as Flutter tests with a fresh world
/// and registry per scenario.  This centralises evidence publication and makes
/// runner failures report the exact scenario result consistently.
///
/// A Scenario Outline produces one widget test and one scenario result for
/// every Examples row. [resultDirectory] is useful for embedding hosts and
/// tests; when omitted, results use `ZUKE_RESULT_DIR`.
final class ZukeFlutterHarness<W extends ScenarioWorld> {
  /// Parsed feature containing the scenarios.
  final ParsedFeature feature;

  /// Generated scenario contracts to register.
  final Iterable<ZukeScenarioContract> scenarios;

  /// Creates a fresh step registry per scenario.
  final StepRegistry<W> Function() registryFactory;

  /// Creates a scenario world for a widget test.
  final FutureOr<W> Function(WidgetTester tester) worldFactory;

  /// Optionally disposes a created world.
  final FutureOr<void> Function(W world)? worldDisposer;

  /// Logical runner identifier.
  final String runnerId;

  /// Runner compatibility identifier.
  final String runnerCompatibilityId;

  /// Source digests used for evidence.
  final Map<String, String> digests;

  /// Evidence type emitted by the harness.
  final String evidenceType;

  /// Evidence target.
  final String target;

  /// Optional output directory for results.
  final String? resultDirectory;

  /// Source identity required by current scenario results.
  final ExecutionSourceIdentity? sourceIdentity;

  /// Creates a generated-scenario Flutter harness.
  const ZukeFlutterHarness({
    required this.feature,
    required this.scenarios,
    required this.registryFactory,
    required this.worldFactory,
    this.worldDisposer,
    required this.runnerId,
    required this.runnerCompatibilityId,
    this.digests = const {},
    this.evidenceType = 'gherkin-ui',
    this.target = 'flutter',
    this.resultDirectory,
    this.sourceIdentity,
  });

  void registerAll() {
    final environment = Platform.environment;
    final context = RunnerExecutionContext.fromEnvironment(environment);
    final identity = sourceIdentity ?? context?.sourceIdentity;
    final managed =
        context != null || sourceIdentity != null || resultDirectory != null;
    if (managed && identity == null) {
      throw const FormatException(
        'Managed Flutter harness is missing source identity.',
      );
    }
    final selected = scenarioFilterFromEnvironment(environment);
    final profile =
        context?.profile ?? environment['ZUKE_PROFILE'] ?? 'pullRequest';
    for (final contract in scenarios) {
      // Resolve before test execution so feature/contract drift is surfaced at
      // registration instead of as a late unresolved step.
      final resolved = resolveScenarioContract(feature, contract);
      for (final exampleCase in scenarioExampleCases(resolved.scenario)) {
        final suffix = exampleCase.displayLabel.isEmpty
            ? ''
            : ' (${exampleCase.displayLabel})';
        testWidgets(
          '${contract.id}: ${contract.title}$suffix',
          (tester) => _execute(
            tester,
            contract,
            resolved,
            profile,
            exampleCase,
            context: context,
            identity: identity,
            managed: managed,
          ),
          skip: !shouldRunScenario(contract.id.value, selected),
        );
      }
    }
  }

  Future<void> _execute(
    WidgetTester tester,
    ZukeScenarioContract contract,
    ResolvedScenarioContract resolved,
    String profile,
    ScenarioExampleCase exampleCase, {
    required RunnerExecutionContext? context,
    required ExecutionSourceIdentity? identity,
    required bool managed,
  }) async {
    final semantics = tester.ensureSemantics();
    W? world;
    try {
      world = await worldFactory(tester);
      final executor = ScenarioExecutor<W>(
        registry: registryFactory(),
        evidenceType: evidenceType,
        target: target,
        profile: profile,
        candidateId: contract.id,
        controlIds: contract.controlIds.map((control) => control.value).toSet(),
        runnerId: runnerId,
        runnerCompatibilityId: runnerCompatibilityId,
        sourceIdentity: identity,
        digests: digests,
      );
      final result = await executor.executeScenario(
        feature,
        resolved.rule,
        resolved.scenario,
        () => world!,
        rowIndex: exampleCase.rowIndex,
        examplesIndex: exampleCase.examplesIndex,
      );
      if (result.status != ScenarioStatus.passed) {
        // ignore: avoid_print
        print(result.toJson());
      }
      expect(result.status, ScenarioStatus.passed);
      if (!managed) return;
      final managedIdentity = identity;
      if (managedIdentity == null) {
        throw const FormatException(
          'Managed Flutter harness is missing source identity.',
        );
      }
      final writer = ExecutionResultWriter(identity: managedIdentity);
      final directory = resultDirectory ?? context?.resultDirectory;
      if (directory == null) {
        writer.writeScenarioToEnvironment(result);
      } else {
        writer.writeScenario(directory, result);
      }
    } finally {
      if (world != null && worldDisposer != null) await worldDisposer!(world);
      semantics.dispose();
    }
  }
}

/// Default Flutter mechanics used by generated binding-driven drivers.
abstract class BindingDrivenFlutterScenarioDriver<
  W extends ScenarioWorld,
  T extends Key
>
    extends FlutterScenarioDriver<W> {
  const BindingDrivenFlutterScenarioDriver();

  WidgetTester testerFor(W world);

  /// Project-owned root contents; the common MaterialApp host is supplied by
  /// the vendor base so ordinary drivers do not repeat pump boilerplate.
  Widget buildRoot(W world);

  @override
  Future<W> create() => throw UnsupportedError(
    'Create the scenario world from the enclosing testWidgets callback.',
  );

  @override
  Future<void> dispose(W world) async {}

  @override
  Future<void> pumpAndSettle(W world) => testerFor(world).pumpAndSettle();

  @override
  Future<void> captureSemantics(W world) => testerFor(world).pump();

  Future<void> open(W world) async {
    await testerFor(world).pumpWidget(MaterialApp(home: buildRoot(world)));
    await pumpAndSettle(world);
  }

  @override
  Future<void> captureScreenshot(W world, String name) async {
    if (name.isEmpty) throw ArgumentError.value(name, 'name');
    await testerFor(world).pump();
  }

  Future<void> zukeEnterBinding(W world, T key, String value) async {
    await testerFor(world).enterText(findFlutterBinding(key), value);
    await pumpAndSettle(world);
  }

  Future<void> zukeTapBinding(W world, T key) async {
    await testerFor(world).tap(findFlutterBinding(key));
    await pumpAndSettle(world);
  }

  Future<String?> zukeReadBinding(W world, T key) async {
    return _readFinder(findFlutterBinding(key), key);
  }

  Future<String?> _readFinder(Finder finder, Object key) async {
    // Evaluate once. Finder evaluation is lazy and a second evaluation can
    // observe a different frame when a project schedules a rebuild.
    final matches = finder.evaluate().toList(growable: false);
    if (matches.isEmpty) return null;
    if (matches.length != 1) {
      throw StateError(
        'Flutter key $key resolves to ${matches.length} widgets; reading '
        'requires exactly one.',
      );
    }
    final widget = matches.single.widget;
    return widget is Text ? widget.data : null;
  }

  Future<void> zukeEnterBindingInstance(
    W world,
    T family,
    Object instanceId,
    String value,
  ) async {
    await testerFor(
      world,
    ).enterText(_instanceFinder(family, instanceId), value);
    await pumpAndSettle(world);
  }

  Future<void> zukeTapBindingInstance(
    W world,
    T family,
    Object instanceId,
  ) async {
    await testerFor(world).tap(_instanceFinder(family, instanceId));
    await pumpAndSettle(world);
  }

  Future<String?> zukeReadBindingInstance(
    W world,
    T family,
    Object instanceId,
  ) async => _readFinder(_instanceFinder(family, instanceId), family);

  Future<List<String>> zukeReadAllBindings(W world, T family) async {
    final matches = findFlutterBinding(
      family,
    ).evaluate().toList(growable: false);
    return matches
        .map((match) {
          final widget = match.widget;
          if (widget is! Text || widget.data == null) {
            throw StateError(
              'Flutter binding $family contains a widget without readable Text.data.',
            );
          }
          return widget.data!;
        })
        .toList(growable: false);
  }
}

/// Resolver functions keep vendor vocabulary independent of a product's key
/// types and page-object layout. Project code maps logical binding IDs to
/// finders; the vendor library owns only reusable interaction semantics.
typedef FlutterTesterResolver<W extends ScenarioWorld> =
    WidgetTester Function(W world);
typedef FlutterBindingDecoder<B extends ZukeBindingDescriptor> =
    B Function(String bindingId);
typedef FlutterFinderResolver<
  W extends ScenarioWorld,
  B extends ZukeBindingDescriptor
> = Finder Function(W world, B binding);
typedef FlutterBindingKeyResolver<
  W extends ScenarioWorld,
  B extends ZukeBindingDescriptor
> = Key Function(W world, B binding);
typedef FlutterFinderOverride<
  W extends ScenarioWorld,
  B extends ZukeBindingDescriptor
> = Finder Function(W world, B binding);

List<StepDefinition<W>>
flutterVendorSteps<W extends ScenarioWorld, B extends ZukeBindingDescriptor>({
  required FlutterTesterResolver<W> testerFor,
  required FlutterBindingDecoder<B> bindingFromId,
  required FlutterBindingKeyResolver<W, B> keyFor,
  Map<B, FlutterFinderOverride<W, B>> finderOverrides = const {},
}) {
  _ResolvedFlutterBinding<B> resolveBinding(W world, String bindingId) {
    final binding = bindingFromId(bindingId);
    final override = finderOverrides[binding];
    final key = keyFor(world, binding);
    if (override != null) {
      return _ResolvedFlutterBinding(binding, override(world, binding));
    }
    _validateBindingKey(binding, key);
    return _ResolvedFlutterBinding(binding, findFlutterBinding(key));
  }

  Finder resolveFinder(W world, String bindingId) =>
      resolveBinding(world, bindingId).finder;

  void requireExactlyOne(W world, String bindingId, String operation) {
    final resolved = resolveBinding(world, bindingId);
    final count = resolved.finder.evaluate().length;
    if (count == 0) throw StateError('No Flutter binding for $bindingId');
    if (count != 1) {
      throw StateError(
        'Flutter binding $bindingId declares '
        '${resolved.binding.instanceCardinality.name} runtime instances but '
        'resolves to $count widgets; $operation requires exactly one.',
      );
    }
  }

  return [
    StepDefinition.cucumber(
      tier: StepTier.vendor,
      target: 'flutter',
      expression: CucumberExpression(
        'the user enters {int} spaces into {string}',
        StepParameterTypeRegistry.standard(),
      ),
      action: (world, _, values) async {
        final count = values[0] as int;
        final bindingId = values[1] as String;
        if (count < 0) {
          throw StateError('The number of spaces must not be negative.');
        }
        final tester = testerFor(world);
        requireExactlyOne(world, bindingId, 'entering text');
        final finder = resolveFinder(world, bindingId);
        await tester.enterText(finder, List<String>.filled(count, ' ').join());
        await tester.pump();
      },
    ),
    StepDefinition(
      tier: StepTier.vendor,
      target: 'flutter',
      pattern: RegExp(r'^the user enters "([^"]*)" into "([^"]+)"$'),
      action: (world, _, arguments) async {
        final tester = testerFor(world);
        final bindingId = arguments['2']!;
        requireExactlyOne(world, bindingId, 'entering text');
        final finder = resolveFinder(world, bindingId);
        await tester.enterText(finder, arguments['1']!);
        await tester.pump();
      },
    ),
    StepDefinition(
      tier: StepTier.vendor,
      target: 'flutter',
      pattern: RegExp(r'^the user taps "([^"]+)"$'),
      action: (world, _, arguments) async {
        final tester = testerFor(world);
        final bindingId = arguments['1']!;
        requireExactlyOne(world, bindingId, 'tapping');
        final finder = resolveFinder(world, bindingId);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      },
    ),
    StepDefinition(
      tier: StepTier.vendor,
      target: 'flutter',
      pattern: RegExp(r'^element "([^"]+)" displays "([^"]*)"$'),
      action: (world, _, arguments) {
        final tester = testerFor(world);
        final bindingId = arguments['1']!;
        final target = resolveFinder(world, bindingId);
        if (target.evaluate().isEmpty) {
          throw StateError('No Flutter binding for ${arguments['1']}');
        }
        final display = find.descendant(
          of: target,
          matching: find.text(arguments['2']!),
          matchRoot: true,
        );
        if (display.evaluate().isEmpty) {
          final observed = _readableTextValues(target);
          throw StateError(
            'Expected $bindingId to display ${arguments['2']}. '
            'Observed: ${observed.isEmpty ? '<no readable text>' : observed.join(', ')}',
          );
        }
        // Ensures the test binding has processed any pending render update.
        return tester.pump();
      },
    ),
    StepDefinition(
      tier: StepTier.vendor,
      target: 'flutter',
      pattern: RegExp(r'^element "([^"]+)" is not present$'),
      action: (world, _, arguments) {
        final bindingId = arguments['1']!;
        final resolved = resolveBinding(world, bindingId);
        if (!resolved.binding.instanceCardinality.allowsZero) {
          throw StateError(
            'Binding $bindingId declares a mandatory '
            '${resolved.binding.instanceCardinality.name} runtime instance and '
            'cannot be asserted absent.',
          );
        }
        final count = resolved.finder.evaluate().length;
        if (count != 0) {
          throw StateError(
            'Expected $bindingId to be absent, but it resolves to $count widgets',
          );
        }
      },
    ),
    StepDefinition(
      tier: StepTier.vendor,
      target: 'flutter',
      pattern: RegExp(r'^element "([^"]+)" is focused$'),
      action: (world, _, arguments) {
        final bindingId = arguments['1']!;
        requireExactlyOne(world, bindingId, 'checking focus');
        final finder = resolveFinder(world, bindingId);
        final editable = find.descendant(
          of: finder,
          matching: find.byType(EditableText),
        );
        if (editable.evaluate().isEmpty) {
          throw StateError(
            'Binding ${arguments['1']} does not expose an editable focus target',
          );
        }
        final field = testerFor(world).widget<EditableText>(editable.first);
        if (!field.focusNode.hasFocus) {
          throw StateError('Expected ${arguments['1']} to be focused');
        }
      },
    ),
    StepDefinition(
      tier: StepTier.vendor,
      target: 'flutter',
      pattern: RegExp(r'^element "([^"]+)" has accessible name "([^"]+)"$'),
      action: (world, _, arguments) {
        final bindingId = arguments['1']!;
        requireExactlyOne(world, bindingId, 'checking an accessible name');
        if (find.bySemanticsLabel(arguments['2']!).evaluate().isEmpty) {
          throw StateError('Expected accessible name ${arguments['2']}');
        }
      },
    ),
  ];
}

/// Resolves a typed binding key to the widgets that belong to it.
///
/// Collection family keys match every typed instance in that family. Legacy
/// raw keys remain supported for single bindings and for projects that supply
/// an explicit [FlutterFinderOverride].
Finder findFlutterBinding(Key key) => switch (key) {
  FlutterBindingKey(kind: FlutterBindingKind.collection) =>
    find.byWidgetPredicate(
      (widget) => key.matches(widget.key),
      description: 'widgets in Flutter binding collection ${key.bindingId}',
    ),
  _ => find.byKey(key),
};

Key _instanceKey(Key family, Object instanceId) {
  if (family is! FlutterBindingKey ||
      family.kind != FlutterBindingKind.collection) {
    throw StateError(
      'Repeated binding instances require a FlutterBindingKey.collection; '
      'received $family.',
    );
  }
  return family.instance(instanceId);
}

Finder _instanceFinder(Key family, Object instanceId) =>
    find.byKey(_instanceKey(family, instanceId));

void _validateBindingKey(ZukeBindingDescriptor binding, Key key) {
  final repeated = binding.instanceCardinality.allowsMany;
  if (key is! FlutterBindingKey) {
    if (repeated) {
      throw StateError(
        'Binding ${binding.id} declares ${binding.instanceCardinality.name} '
        'runtime instances and requires FlutterBindingKey.collection or a '
        'finder override for legacy keys.',
      );
    }
    return;
  }
  final expected = repeated
      ? FlutterBindingKind.collection
      : FlutterBindingKind.single;
  if (key.kind != expected) {
    throw StateError(
      'Binding ${binding.id} declares ${binding.instanceCardinality.name} '
      'runtime instances but was given FlutterBindingKey.${key.kind.name}; '
      'use FlutterBindingKey.${expected.name}.',
    );
  }
}

List<String> _readableTextValues(Finder finder) => finder
    .evaluate()
    .expand((match) {
      final root = match.widget;
      if (root is Text && root.data != null) return [root.data!];
      return <String>[];
    })
    .toList(growable: false);

final class _ResolvedFlutterBinding<B extends ZukeBindingDescriptor> {
  final B binding;
  final Finder finder;

  const _ResolvedFlutterBinding(this.binding, this.finder);
}
