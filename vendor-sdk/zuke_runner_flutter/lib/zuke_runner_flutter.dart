/// Supported application-facing Flutter scenario integration API.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_runner/zuke_runner.dart';

import 'src/flutter_binding_key.dart';

export 'package:zuke_annotations/zuke_annotations.dart';
export 'package:zuke_frontend/zuke_frontend.dart';
export 'package:zuke_runner/zuke_runner.dart';
export 'src/flutter_binding_key.dart';

abstract class FlutterScenarioDriver<W extends ScenarioWorld>
    extends FlutterDriverFactory<W> {
  const FlutterScenarioDriver();
  Future<void> pumpAndSettle(W world);
  Future<void> captureSemantics(W world);
  Future<void> captureScreenshot(W world, String name);
}

/// Test body for a non-Gherkin Flutter assertion that produces evidence.
///
/// The returned string is hashed only after the body completes successfully.
typedef FlutterEvidenceBody = FutureOr<String> Function(WidgetTester tester);

/// One generated scenario observed by an ordinary Flutter widget test.
final class FlutterEvidenceCase {
  final ZukeScenarioContract scenario;
  final FlutterEvidenceBody body;
  final Iterable<String>? evidenceTypes;

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
  final String runnerCompatibilityId;
  final String target;
  final String variant;
  final Iterable<String> defaultEvidenceTypes;
  final String? profile;
  final String? runnerId;
  final String? outputDirectory;
  final Map<String, String>? environment;

  const ZukeFlutterEvidenceHarness({
    required this.runnerCompatibilityId,
    required this.defaultEvidenceTypes,
    this.target = 'flutter',
    this.variant = 'default',
    this.profile,
    this.runnerId,
    this.outputDirectory,
    this.environment,
  });

  void registerAll(Iterable<FlutterEvidenceCase> cases) {
    final effectiveEnvironment = environment ?? Platform.environment;
    final selected = scenarioFilterFromEnvironment(effectiveEnvironment);
    for (final evidenceCase in cases) {
      final evidenceTypes = (evidenceCase.evidenceTypes ?? defaultEvidenceTypes)
          .toSet()
          .toList(growable: false);
      if (evidenceTypes.isEmpty) {
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
          const SuiteEvidenceEmitter().emitPassing(
            requirementId: evidenceCase.scenario.requirementId,
            scenarioId: evidenceCase.scenario.id,
            evidenceTypes: evidenceTypes,
            target: target,
            variant: variant,
            profile: profile ?? effectiveEnvironment['ZUKE_PROFILE'],
            runnerId: runnerId ?? effectiveEnvironment['ZUKE_RUNNER_ID'],
            runnerCompatibilityId: runnerCompatibilityId,
            outputDirectory: outputDirectory,
            digestInput: digestInput,
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
  final ParsedFeature feature;
  final Iterable<ZukeScenarioContract> scenarios;
  final StepRegistry<W> Function() registryFactory;
  final FutureOr<W> Function(WidgetTester tester) worldFactory;
  final FutureOr<void> Function(W world)? worldDisposer;
  final String runnerId;
  final String runnerCompatibilityId;
  final Map<String, String> digests;
  final String evidenceType;
  final String target;
  final String? resultDirectory;

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
  });

  void registerAll() {
    final selected = scenarioFilterFromEnvironment(Platform.environment);
    final profile = Platform.environment['ZUKE_PROFILE'] ?? 'pullRequest';
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
          (tester) =>
              _execute(tester, contract, resolved, profile, exampleCase),
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
    ScenarioExampleCase exampleCase,
  ) async {
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
        controlIds: contract.controlIds,
        runnerId: runnerId,
        runnerCompatibilityId: runnerCompatibilityId,
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
      const writer = ExecutionResultWriter();
      final directory = resultDirectory;
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
