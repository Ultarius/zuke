import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_core/src/atomic_file_writer.dart';
import 'step_arguments.dart';

abstract class ScenarioWorld {
  const ScenarioWorld();
}

abstract class TargetDriverFactory<W extends ScenarioWorld> {
  const TargetDriverFactory();
  Future<W> create();
  Future<void> dispose(W world);
}

/// Flutter projects implement this in a project-owned `testWidgets`
/// entrypoint so the runner never creates a second Flutter test world.
abstract class FlutterDriverFactory<W extends ScenarioWorld>
    extends TargetDriverFactory<W> {
  const FlutterDriverFactory();
}

/// HTTP projects implement this with their logical endpoint registry and
/// fixture lifecycle. The runner only depends on the world contract.
abstract class HttpDriverFactory<W extends ScenarioWorld>
    extends TargetDriverFactory<W> {
  const HttpDriverFactory();
}

class MapScenarioWorld extends ScenarioWorld {
  final Map<String, Object?> values;
  MapScenarioWorld([Map<String, Object?>? values]) : values = values ?? {};
}

typedef StepAction<W extends ScenarioWorld> =
    FutureOr<void> Function(
      W world,
      GherkinStep step,
      Map<String, String> arguments,
    );

/// Callback used by generated Cucumber Expression support. Values have already
/// passed through their registered parameter transformers.
typedef TransformedStepAction<W extends ScenarioWorld> =
    FutureOr<void> Function(W world, GherkinStep step, List<Object?> values);

/// Resolution order is semantic, not an accidental priority convention.
/// Project steps can refine vendor vocabulary, but cannot shadow generated
/// feature steps; ambiguity remains an error within the selected tier.
enum StepTier { generated, project, vendor, extension }

class StepDefinition<W extends ScenarioWorld> {
  final RegExp pattern;
  final int priority;
  final StepTier tier;
  final String target;
  final StepAction<W> action;

  const StepDefinition({
    required this.pattern,
    required this.action,
    this.priority = 100,
    this.tier = StepTier.project,
    this.target = 'generic',
  });

  factory StepDefinition.cucumber({
    required CucumberExpression expression,
    required TransformedStepAction<W> action,
    int priority = 100,
    StepTier tier = StepTier.project,
    String target = 'generic',
  }) => StepDefinition(
    pattern: expression.pattern,
    priority: priority,
    tier: tier,
    target: target,
    action: (world, step, _) async {
      final match = expression.pattern.firstMatch(step.text);
      if (match == null) {
        throw StateError('Cucumber expression did not match ${step.text}');
      }
      await action(world, step, await expression.transform(match));
    },
  );
}

class UnresolvedStepException implements Exception {
  final String text;
  const UnresolvedStepException(this.text);
  @override
  String toString() => 'No step definition matches "$text"';
}

class AmbiguousStepException implements Exception {
  final String text;
  final int priority;
  final StepTier tier;
  const AmbiguousStepException(this.text, this.priority, this.tier);
  @override
  String toString() =>
      'Multiple ${tier.name} step definitions at priority $priority match "$text"';
}

class StepRegistry<W extends ScenarioWorld> {
  final List<StepDefinition<W>> _definitions = [];

  void register(StepDefinition<W> definition) => _definitions.add(definition);

  StepMatch<W> resolve(GherkinStep step) {
    final matches = <StepMatch<W>>[];
    for (final definition in _definitions) {
      final match = definition.pattern.firstMatch(step.text);
      if (match == null) continue;
      final args = <String, String>{};
      for (var i = 1; i <= match.groupCount; i++) {
        args['$i'] = match.group(i) ?? '';
      }
      matches.add(StepMatch(definition, args));
    }
    if (matches.isEmpty) throw UnresolvedStepException(step.text);
    final selectedTier = matches
        .map((match) => match.definition.tier.index)
        .reduce((left, right) => left < right ? left : right);
    final tierMatches = matches
        .where((match) => match.definition.tier.index == selectedTier)
        .toList();
    final highest = tierMatches
        .map((m) => m.definition.priority)
        .reduce((a, b) => a > b ? a : b);
    final selected = tierMatches
        .where((m) => m.definition.priority == highest)
        .toList();
    if (selected.length != 1) {
      throw AmbiguousStepException(
        step.text,
        highest,
        StepTier.values[selectedTier],
      );
    }
    return selected.single;
  }
}

/// Builds a registry from an expression-friendly iterable of definitions.
StepRegistry<W> buildStepRegistry<W extends ScenarioWorld>(
  Iterable<StepDefinition<W>> definitions,
) {
  final registry = StepRegistry<W>();
  for (final definition in definitions) {
    registry.register(definition);
  }
  return registry;
}

class StepMatch<W extends ScenarioWorld> {
  final StepDefinition<W> definition;
  final Map<String, String> arguments;
  const StepMatch(this.definition, this.arguments);
}

enum ScenarioStatus { passed, failed, unresolved, ambiguous }

enum StepStatus { passed, failed }

class StepResult {
  final String keyword;
  final String text;
  final StepStatus status;
  final String? error;
  const StepResult({
    required this.keyword,
    required this.text,
    required this.status,
    this.error,
  });

  Map<String, Object?> toJson() => {
    'keyword': keyword,
    'text': text,
    'status': status.name,
    if (error != null) 'error': error,
  };

  factory StepResult.fromJson(Map<String, Object?> json) {
    final statusStr = json['status'] as String?;
    final status = StepStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => StepStatus.failed,
    );
    return StepResult(
      keyword: json['keyword'] as String? ?? '',
      text: json['text'] as String? ?? '',
      status: status,
      error: json['error'] as String?,
    );
  }
}

class EvidenceEnvelope {
  final EvidenceRecord record;
  final String observedAt;
  final String? buildId;
  const EvidenceEnvelope(this.record, {required this.observedAt, this.buildId});
  Map<String, Object?> toJson() => {
    'record': record.toJson(),
    'observedAt': observedAt,
    if (buildId != null) 'buildId': buildId,
  };
}

class EvidenceWriter {
  const EvidenceWriter();

  void writeAtomic(String directory, EvidenceRecord record, {String? buildId}) {
    final root = Directory(directory)..createSync(recursive: true);
    final encoded =
        '${const JsonEncoder.withIndent('  ').convert(record.toJson())}\n';
    final digest = sha256.convert(utf8.encode(encoded)).toString();
    final semantic = File('${root.path}${Platform.pathSeparator}$digest.json');
    _writeEncodedAtomically(semantic, encoded);
    // Observation envelopes are written by the CLI run coordinator so this
    // semantic writer remains deterministic.
  }

  void write(String path, Iterable<EvidenceRecord> records, {String? buildId}) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final envelopes = records
        .map(
          (record) => EvidenceEnvelope(
            record,
            observedAt: DateTime.now().toUtc().toIso8601String(),
            buildId: buildId,
          ).toJson(),
        )
        .toList();
    envelopes.sort(
      (a, b) => jsonEncode(a['record']).compareTo(jsonEncode(b['record'])),
    );
    _writeEncodedAtomically(
      file,
      '${const JsonEncoder.withIndent('  ').convert(envelopes)}\n',
    );
  }
}

abstract interface class ExecutionResult {
  String get executionId;
  String get requirementId;
  String get evidenceType;
  String get target;
  String get variant;
  String get candidateId;
  String get profile;
  String get runnerId;
  String get runnerCompatibilityId;
  String? get sourcePackage;
  String? get sourceAdapter;
  String? get sourceCompatibilityId;
  List<ScenarioId> get scenarioIds;
  List<String> get controlIds;
  List<String> get attachmentDigests;
  String? get error;
  bool get isPassed;
  Map<String, Object?> toJson();
}

ExecutionSourceIdentity _sourceIdentity({
  required String? sourcePackage,
  required String? sourceAdapter,
  required String? sourceCompatibilityId,
}) {
  String requiredValue(String name, String? value) {
    if (value == null || value.isEmpty) {
      throw FormatException('Execution result requires non-empty $name');
    }
    return value;
  }

  return ExecutionSourceIdentity(
    sourcePackage: requiredValue('sourcePackage', sourcePackage),
    sourceAdapter: requiredValue('sourceAdapter', sourceAdapter),
    sourceCompatibilityId: requiredValue(
      'sourceCompatibilityId',
      sourceCompatibilityId,
    ),
  );
}

class ScenarioResult implements ExecutionResult {
  @override
  final String executionId;
  final ScenarioStatus status;
  final List<StepResult> steps;
  @override
  final String requirementId;
  @override
  final String evidenceType;
  @override
  final String target;
  @override
  final String variant;
  @override
  final String candidateId;
  @override
  final String profile;
  @override
  final String runnerId;
  @override
  final String runnerCompatibilityId;
  @override
  final String? sourcePackage;
  @override
  final String? sourceAdapter;
  @override
  final String? sourceCompatibilityId;
  @override
  final List<ScenarioId> scenarioIds;
  @override
  final List<String> controlIds;
  @override
  final List<String> attachmentDigests;
  @override
  final String? error;

  @override
  bool get isPassed => status == ScenarioStatus.passed;

  const ScenarioResult({
    required this.executionId,
    required this.status,
    this.steps = const [],
    required this.requirementId,
    required this.evidenceType,
    required this.target,
    this.variant = 'default',
    required this.candidateId,
    required this.profile,
    required this.runnerId,
    required this.runnerCompatibilityId,
    this.sourcePackage,
    this.sourceAdapter,
    this.sourceCompatibilityId,
    this.scenarioIds = const [],
    this.controlIds = const [],
    this.attachmentDigests = const [],
    this.error,
  });

  ScenarioResult withSourceIdentity(ExecutionSourceIdentity identity) =>
      ScenarioResult(
        executionId: executionId,
        status: status,
        steps: steps,
        requirementId: requirementId,
        evidenceType: evidenceType,
        target: target,
        variant: variant,
        candidateId: candidateId,
        profile: profile,
        runnerId: runnerId,
        runnerCompatibilityId: runnerCompatibilityId,
        sourcePackage: identity.sourcePackage,
        sourceAdapter: identity.sourceAdapter,
        sourceCompatibilityId: identity.sourceCompatibilityId,
        scenarioIds: scenarioIds,
        controlIds: controlIds,
        attachmentDigests: attachmentDigests,
        error: error,
      );

  Map<String, Object?> toJson() {
    final identity = _sourceIdentity(
      sourcePackage: sourcePackage,
      sourceAdapter: sourceAdapter,
      sourceCompatibilityId: sourceCompatibilityId,
    );
    return {
      'kind': 'zuke.scenario-result',
      'executionId': executionId,
      'status': status.name,
      'requirementId': requirementId,
      'evidenceType': evidenceType,
      'target': target,
      'variant': variant,
      'candidateId': candidateId,
      'profile': profile,
      'runnerId': runnerId,
      'runnerCompatibilityId': runnerCompatibilityId,
      ...identity.toJson(),
      'scenarioIds': scenarioIds.map((id) => id.value).toList()..sort(),
      'controlIds': [...controlIds]..sort(),
      'attachmentDigests': [...attachmentDigests]..sort(),
      'steps': steps.map((s) => s.toJson()).toList(),
      if (error != null) 'error': error,
    };
  }

  factory ScenarioResult.fromJson(Map<String, Object?> json) {
    if (json['kind'] != 'zuke.scenario-result') {
      throw const FormatException(
        'Unsupported scenario result format; regenerate with the current Zuke CLI',
      );
    }
    String required(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Scenario result requires non-empty $key');
      }
      return value;
    }

    final rawSteps = json['steps'];
    if (rawSteps is! List || rawSteps.any((step) => step is! Map)) {
      throw const FormatException('Scenario result steps must be a list');
    }
    List<String> strings(String key) {
      final value = json[key] ?? const [];
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('Scenario result $key must be a string list');
      }
      return value.cast<String>();
    }

    final status = switch (required('status')) {
      'passed' => ScenarioStatus.passed,
      'failed' => ScenarioStatus.failed,
      'unresolved' => ScenarioStatus.unresolved,
      'ambiguous' => ScenarioStatus.ambiguous,
      final value => throw FormatException('Unknown scenario status: $value'),
    };
    return ScenarioResult(
      executionId: required('executionId'),
      status: status,
      requirementId: required('requirementId'),
      evidenceType: required('evidenceType'),
      target: required('target'),
      variant: required('variant'),
      candidateId: required('candidateId'),
      profile: required('profile'),
      runnerId: required('runnerId'),
      runnerCompatibilityId: required('runnerCompatibilityId'),
      sourcePackage: required('sourcePackage'),
      sourceAdapter: required('sourceAdapter'),
      sourceCompatibilityId: required('sourceCompatibilityId'),
      scenarioIds: [
        for (final id in strings('scenarioIds')) ScenarioId.parse(id),
      ],
      controlIds: strings('controlIds'),
      attachmentDigests: strings('attachmentDigests'),
      steps: rawSteps
          .map(
            (step) =>
                StepResult.fromJson(Map<String, Object?>.from(step as Map)),
          )
          .toList(),
      error: json['error'] as String?,
    );
  }
}

enum SuiteStatus { passed, failed, skipped }

/// Raw result produced by an ordinary test adapter.  It is deliberately not
/// an [EvidenceRecord]: only the CLI may bind a result to current workspace
/// digests and publish semantic evidence.
class SuiteResult implements ExecutionResult {
  @override
  final String executionId;
  final SuiteStatus status;
  @override
  final String requirementId;
  @override
  final String evidenceType;
  @override
  final String target;
  @override
  final String variant;
  @override
  final String candidateId;
  @override
  final String profile;
  @override
  final String runnerId;
  @override
  final String runnerCompatibilityId;
  @override
  final String? sourcePackage;
  @override
  final String? sourceAdapter;
  @override
  final String? sourceCompatibilityId;
  final String resultDigest;
  @override
  final List<ScenarioId> scenarioIds;
  @override
  final List<String> controlIds;
  @override
  final List<String> attachmentDigests;
  @override
  final String? error;

  @override
  bool get isPassed => status == SuiteStatus.passed;

  const SuiteResult({
    required this.executionId,
    required this.status,
    required this.requirementId,
    required this.evidenceType,
    required this.target,
    this.variant = 'default',
    required this.candidateId,
    required this.profile,
    required this.runnerId,
    required this.runnerCompatibilityId,
    this.sourcePackage,
    this.sourceAdapter,
    this.sourceCompatibilityId,
    required this.resultDigest,
    this.scenarioIds = const [],
    this.controlIds = const [],
    this.attachmentDigests = const [],
    this.error,
  });

  SuiteResult withSourceIdentity(ExecutionSourceIdentity identity) =>
      SuiteResult(
        executionId: executionId,
        status: status,
        requirementId: requirementId,
        evidenceType: evidenceType,
        target: target,
        variant: variant,
        candidateId: candidateId,
        profile: profile,
        runnerId: runnerId,
        runnerCompatibilityId: runnerCompatibilityId,
        sourcePackage: identity.sourcePackage,
        sourceAdapter: identity.sourceAdapter,
        sourceCompatibilityId: identity.sourceCompatibilityId,
        resultDigest: resultDigest,
        scenarioIds: scenarioIds,
        controlIds: controlIds,
        attachmentDigests: attachmentDigests,
        error: error,
      );

  Map<String, Object?> toJson() {
    final identity = _sourceIdentity(
      sourcePackage: sourcePackage,
      sourceAdapter: sourceAdapter,
      sourceCompatibilityId: sourceCompatibilityId,
    );
    return {
      'kind': 'zuke.suite-result',
      'executionId': executionId,
      'status': status.name,
      'requirementId': requirementId,
      'evidenceType': evidenceType,
      'target': target,
      'variant': variant,
      'candidateId': candidateId,
      'profile': profile,
      'runnerId': runnerId,
      'runnerCompatibilityId': runnerCompatibilityId,
      ...identity.toJson(),
      'resultDigest': resultDigest,
      'scenarioIds': scenarioIds.map((id) => id.value).toList()..sort(),
      'controlIds': [...controlIds]..sort(),
      'attachmentDigests': [...attachmentDigests]..sort(),
      if (error != null) 'error': error,
    };
  }

  factory SuiteResult.fromJson(Map<String, Object?> json) {
    if (json['kind'] != 'zuke.suite-result') {
      throw const FormatException(
        'Unsupported suite result format; regenerate with the current Zuke CLI',
      );
    }
    String required(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Suite result requires non-empty $key');
      }
      return value;
    }

    List<String> strings(String key) {
      final value = json[key] ?? const [];
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('Suite result $key must be a string list');
      }
      return value.cast<String>();
    }

    return SuiteResult(
      executionId: required('executionId'),
      status: switch (required('status')) {
        'passed' => SuiteStatus.passed,
        'failed' => SuiteStatus.failed,
        'skipped' => SuiteStatus.skipped,
        final value => throw FormatException('Unknown suite status: $value'),
      },
      requirementId: required('requirementId'),
      evidenceType: required('evidenceType'),
      target: required('target'),
      variant: required('variant'),
      candidateId: required('candidateId'),
      profile: required('profile'),
      runnerId: required('runnerId'),
      runnerCompatibilityId: required('runnerCompatibilityId'),
      sourcePackage: required('sourcePackage'),
      sourceAdapter: required('sourceAdapter'),
      sourceCompatibilityId: required('sourceCompatibilityId'),
      resultDigest: required('resultDigest'),
      scenarioIds: [
        for (final id in strings('scenarioIds')) ScenarioId.parse(id),
      ],
      controlIds: strings('controlIds'),
      attachmentDigests: strings('attachmentDigests'),
      error: json['error'] as String?,
    );
  }
}

class ExecutionResultWriter {
  final ExecutionSourceIdentity identity;

  const ExecutionResultWriter({required this.identity});

  factory ExecutionResultWriter.fromEnvironment([
    Map<String, String>? environment,
  ]) => ExecutionResultWriter(
    identity: ExecutionSourceIdentity.fromEnvironment(
      environment ?? Platform.environment,
    ),
  );

  File writeScenario(String directory, ScenarioResult result) => _writeAtomic(
    directory,
    'scenario-${result.executionId}',
    result.withSourceIdentity(identity).toJson(),
  );

  File writeSuite(String directory, SuiteResult result) => _writeAtomic(
    directory,
    'suite-${result.executionId}',
    result.withSourceIdentity(identity).toJson(),
  );

  File? writeScenarioToEnvironment(ScenarioResult result) {
    final directory = Platform.environment['ZUKE_RESULT_DIR'];
    if (directory == null || directory.isEmpty) return null;
    return writeScenario(directory, result);
  }

  File? writeSuiteToEnvironment(SuiteResult result) {
    final directory = Platform.environment['ZUKE_RESULT_DIR'];
    if (directory == null || directory.isEmpty) return null;
    return writeSuite(directory, result);
  }

  File _writeAtomic(String directory, String stem, Map<String, Object?> json) {
    final root = Directory(directory)..createSync(recursive: true);
    final destination = File('${root.path}${Platform.pathSeparator}$stem.json');
    _writeEncodedAtomically(
      destination,
      '${const JsonEncoder.withIndent('  ').convert(json)}\n',
    );
    return destination;
  }
}

void _writeEncodedAtomically(File destination, String encoded) {
  writeBytesAtomically(
    destination,
    utf8.encode(encoded),
    conflictCode: 'ZK-EVIDENCE-WRITE-CONFLICT',
  );
}

/// Emits deterministic passed suite evidence for non-Gherkin test bodies.
///
/// A single assertion can substantiate several evidence types, for example a
/// Flutter widget assertion and its corresponding Gherkin UI observation.
final class SuiteEvidenceEmitter {
  const SuiteEvidenceEmitter();

  List<File> emitPassing({
    required String requirementId,
    required ScenarioId scenarioId,
    required Iterable<String> evidenceTypes,
    required String target,
    required String runnerCompatibilityId,
    required String digestInput,
    Iterable<String> controlIds = const [],
    String variant = 'default',
    String? outputDirectory,
    String? profile,
    String? runnerId,
    ExecutionSourceIdentity? sourceIdentity,
    String? caseId,
  }) {
    final managedContext = RunnerExecutionContext.fromEnvironment(
      Platform.environment,
    );
    if (managedContext == null) {
      final explicitManaged =
          sourceIdentity != null ||
          outputDirectory != null ||
          profile != null ||
          runnerId != null;
      if (!explicitManaged) {
        // Ordinary direct tests run normally and publish no evidence.
        return const [];
      }
      if (sourceIdentity == null ||
          outputDirectory == null ||
          profile == null ||
          runnerId == null) {
        throw const FormatException(
          'Managed evidence options require a complete RunnerExecutionContext',
        );
      }
    }
    final effectiveIdentity = managedContext?.sourceIdentity ?? sourceIdentity!;
    final effectiveOutputDirectory =
        managedContext?.resultDirectory ?? outputDirectory!;
    final effectiveProfile = managedContext?.profile ?? profile!;
    final effectiveRunnerId = managedContext?.runnerId ?? runnerId!;
    if (managedContext != null &&
        profile != null &&
        profile != managedContext.profile) {
      throw const FormatException(
        'Evidence profile disagrees with managed context',
      );
    }
    if (managedContext != null &&
        runnerId != null &&
        runnerId != managedContext.runnerId) {
      throw const FormatException(
        'Evidence runner disagrees with managed context',
      );
    }
    if (managedContext != null &&
        runnerCompatibilityId != managedContext.runnerCompatibilityId) {
      throw const FormatException(
        'Evidence runner compatibility disagrees with managed context',
      );
    }
    if (managedContext != null &&
        sourceIdentity != null &&
        canonicalJson(sourceIdentity.toJson()) !=
            canonicalJson(managedContext.sourceIdentity.toJson())) {
      throw const FormatException(
        'Evidence source identity disagrees with managed context',
      );
    }
    final digest = 'sha256:${sha256.convert(utf8.encode(digestInput))}';
    final sortedControlIds = [...controlIds.toSet()]..sort();
    final identity = effectiveIdentity;
    final writer = ExecutionResultWriter(identity: identity);
    final files = <File>[];
    for (final evidenceType in evidenceTypes.toSet()) {
      final executionId = _suiteExecutionId(
        profile: effectiveProfile,
        requirementId: requirementId,
        scenarioId: scenarioId,
        evidenceType: evidenceType,
        target: target,
        variant: variant,
        runnerCompatibilityId: runnerCompatibilityId,
        caseId: caseId,
      );
      final result = SuiteResult(
        executionId: executionId,
        status: SuiteStatus.passed,
        requirementId: requirementId,
        evidenceType: evidenceType,
        target: target,
        variant: variant,
        candidateId: scenarioId.value,
        profile: effectiveProfile,
        runnerId: effectiveRunnerId,
        runnerCompatibilityId: runnerCompatibilityId,
        sourcePackage: identity.sourcePackage,
        sourceAdapter: identity.sourceAdapter,
        sourceCompatibilityId: identity.sourceCompatibilityId,
        resultDigest: digest,
        scenarioIds: [scenarioId],
        controlIds: sortedControlIds,
      );
      files.add(writer.writeSuite(effectiveOutputDirectory, result));
    }
    return files;
  }

  String _suiteExecutionId({
    required String profile,
    required String requirementId,
    required ScenarioId scenarioId,
    required String evidenceType,
    required String target,
    required String variant,
    required String runnerCompatibilityId,
    required String? caseId,
  }) {
    final identity = canonicalJson({
      'profile': profile,
      'requirementId': requirementId,
      'scenarioId': scenarioId.value,
      'evidenceType': evidenceType,
      'target': target,
      'variant': variant,
      'runnerCompatibilityId': runnerCompatibilityId,
      'caseId': caseId,
    });
    return 'exec-${sha256.convert(utf8.encode(identity))}';
  }
}

/// One executable instance of a Gherkin scenario.
///
/// A scenario without Examples has one case with empty values. A Scenario
/// Outline has one case for every row in every Examples block. Keeping this
/// enumeration in the core runner ensures adapters cannot accidentally run
/// only the first row.
final class ScenarioExampleCase {
  final int examplesIndex;
  final int rowIndex;
  final String displayLabel;
  final Map<String, String> values;

  const ScenarioExampleCase({
    required this.examplesIndex,
    required this.rowIndex,
    required this.displayLabel,
    required this.values,
  });
}

/// Enumerates every executable case for [scenario] in source order.
Iterable<ScenarioExampleCase> scenarioExampleCases(
  GherkinScenario scenario,
) sync* {
  if (scenario.examples.isEmpty) {
    yield const ScenarioExampleCase(
      examplesIndex: 0,
      rowIndex: 0,
      displayLabel: '',
      values: <String, String>{},
    );
    return;
  }

  for (
    var examplesIndex = 0;
    examplesIndex < scenario.examples.length;
    examplesIndex++
  ) {
    final examples = scenario.examples[examplesIndex];
    for (var rowIndex = 0; rowIndex < examples.rows.length; rowIndex++) {
      yield ScenarioExampleCase(
        examplesIndex: examplesIndex,
        rowIndex: rowIndex,
        displayLabel: _exampleDisplayLabel(examples, examplesIndex, rowIndex),
        values: Map.unmodifiable(
          Map<String, String>.fromIterables(
            examples.headers,
            examples.rows[rowIndex],
          ),
        ),
      );
    }
  }
}

/// Resolves one executable case and validates its indexes.
ScenarioExampleCase scenarioExampleCaseAt(
  GherkinScenario scenario, {
  required int examplesIndex,
  required int rowIndex,
}) {
  if (scenario.examples.isEmpty) {
    if (examplesIndex != 0 || rowIndex != 0) {
      throw RangeError(
        'A scenario without Examples only has case indexes 0, 0.',
      );
    }
    return const ScenarioExampleCase(
      examplesIndex: 0,
      rowIndex: 0,
      displayLabel: '',
      values: <String, String>{},
    );
  }

  if (examplesIndex < 0 || examplesIndex >= scenario.examples.length) {
    throw RangeError.index(examplesIndex, scenario.examples, 'examplesIndex');
  }
  final examples = scenario.examples[examplesIndex];
  if (rowIndex < 0 || rowIndex >= examples.rows.length) {
    throw RangeError.index(rowIndex, examples.rows, 'rowIndex');
  }
  return ScenarioExampleCase(
    examplesIndex: examplesIndex,
    rowIndex: rowIndex,
    displayLabel: _exampleDisplayLabel(examples, examplesIndex, rowIndex),
    values: Map.unmodifiable(
      Map<String, String>.fromIterables(
        examples.headers,
        examples.rows[rowIndex],
      ),
    ),
  );
}

String _exampleDisplayLabel(
  GherkinExamples examples,
  int examplesIndex,
  int rowIndex,
) {
  final title = examples.title.trim();
  final block = title.isEmpty ? 'Examples ${examplesIndex + 1}' : title;
  return '$block row ${rowIndex + 1}';
}

class ScenarioExecutor<W extends ScenarioWorld> {
  final StepRegistry<W> registry;
  final String evidenceType;
  final String target;
  final String variant;
  final String profile;
  final ScenarioId? candidateId;
  final Map<String, String> digests;
  final String? runnerId;
  final String? runnerCompatibilityId;

  /// Controls exercised by every result emitted by this executor.
  final Set<String> controlIds;
  final ExecutionSourceIdentity? sourceIdentity;

  const ScenarioExecutor({
    required this.registry,
    required this.evidenceType,
    this.target = 'generic',
    this.variant = 'default',
    this.profile = 'pullRequest',
    this.candidateId,
    this.digests = const {},
    this.runnerId,
    this.runnerCompatibilityId,
    this.controlIds = const {},
    this.sourceIdentity,
  });

  Future<List<ScenarioResult>> executeRule(
    ParsedFeature feature,
    ParsedRule rule,
    W Function() worldFactory,
  ) async {
    final results = <ScenarioResult>[];
    for (final scenario in rule.scenarios) {
      for (final exampleCase in scenarioExampleCases(scenario)) {
        results.add(
          await executeScenario(
            feature,
            rule,
            scenario,
            worldFactory,
            rowIndex: exampleCase.rowIndex,
            examplesIndex: exampleCase.examplesIndex,
          ),
        );
      }
    }
    return results;
  }

  Future<ScenarioResult> executeScenario(
    ParsedFeature feature,
    ParsedRule rule,
    GherkinScenario scenario,
    W Function() worldFactory, {
    int rowIndex = 0,
    int examplesIndex = 0,
  }) async {
    final exampleCase = scenarioExampleCaseAt(
      scenario,
      examplesIndex: examplesIndex,
      rowIndex: rowIndex,
    );
    final examples = scenario.examples;
    final selectedExamples = examples.isEmpty ? null : examples[examplesIndex];
    final row = exampleCase.values;
    final executionId = _executionId(
      feature,
      rule,
      scenario,
      row,
      selectedExamples?.title,
      examplesIndex,
      rowIndex,
    );
    final requirementId =
        rule.metadata.id ??
        feature.metadata.id ??
        scenario.scenarioElement.title;
    final scenarioIds = <ScenarioId>[if (candidateId != null) candidateId!];
    ScenarioResult result(
      ScenarioStatus status, {
      List<StepResult> steps = const [],
      String? error,
    }) => ScenarioResult(
      executionId: executionId,
      status: status,
      steps: steps,
      requirementId: requirementId,
      evidenceType: evidenceType,
      target: target,
      variant: variant,
      candidateId: candidateId?.value ?? executionId,
      profile: profile,
      runnerId: runnerId ?? 'zuke-runner',
      runnerCompatibilityId: runnerCompatibilityId ?? 'zuke-runner-scenario-v1',
      sourcePackage: sourceIdentity?.sourcePackage,
      sourceAdapter: sourceIdentity?.sourceAdapter,
      sourceCompatibilityId: sourceIdentity?.sourceCompatibilityId,
      scenarioIds: scenarioIds,
      controlIds: controlIds.toList(),
      error: error,
    );
    final allSteps = [
      ...feature.backgroundSteps,
      ...rule.backgroundSteps,
      ...scenario.steps,
    ].map((step) => _substitute(step, row)).toList();
    final matches = <(GherkinStep, StepMatch<W>)>[];
    try {
      for (final step in allSteps) {
        matches.add((step, registry.resolve(step)));
      }
    } on UnresolvedStepException catch (e) {
      return result(ScenarioStatus.unresolved, error: e.toString());
    } on AmbiguousStepException catch (e) {
      return result(ScenarioStatus.ambiguous, error: e.toString());
    }

    final world = worldFactory();
    final stepResults = <StepResult>[];
    for (final pair in matches) {
      try {
        await pair.$2.definition.action(world, pair.$1, pair.$2.arguments);
        stepResults.add(
          StepResult(
            keyword: pair.$1.keyword,
            text: pair.$1.text,
            status: StepStatus.passed,
          ),
        );
      } catch (e, stackTrace) {
        final diagnostic = '$e\n$stackTrace';
        stepResults.add(
          StepResult(
            keyword: pair.$1.keyword,
            text: pair.$1.text,
            status: StepStatus.failed,
            error: diagnostic,
          ),
        );
        return result(
          ScenarioStatus.failed,
          steps: stepResults,
          error: diagnostic,
        );
      }
    }
    return result(ScenarioStatus.passed, steps: stepResults);
  }

  String _executionId(
    ParsedFeature feature,
    ParsedRule rule,
    GherkinScenario scenario,
    Map<String, String> row,
    String? examplesTitle,
    int examplesIndex,
    int rowIndex,
  ) {
    final stableFeature =
        feature.metadata.id ??
        feature.featureElement.title.trim().toLowerCase();
    final stableRule =
        rule.metadata.id ?? rule.ruleElement.title.trim().toLowerCase();
    final stableScenario = scenario.scenarioElement.title.trim().toLowerCase();
    final stableRow = row.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final stableDigests = digests.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final rowIdentity = stableRow
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
    final digestIdentity = stableDigests
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
    final input =
        '$stableFeature\x00$stableRule\x00$stableScenario\x00'
        '${examplesTitle ?? ''}\x00$examplesIndex\x00$rowIndex\x00'
        '$rowIdentity\x00$profile\x00$target\x00$variant\x00'
        '$digestIdentity';
    return sha256.convert(utf8.encode(input)).toString();
  }

  GherkinStep _substitute(GherkinStep step, Map<String, String> row) {
    String replace(String value) => value.replaceAllMapped(
      RegExp(r'<([^>]+)>'),
      (m) => row[m.group(1)] ?? m.group(0)!,
    );
    return GherkinStep(
      keyword: step.keyword,
      inheritedKeyword: step.inheritedKeyword,
      text: replace(step.text),
      source: step.source,
      docString: step.docString == null ? null : replace(step.docString!),
      table: step.table.map((r) => r.map(replace).toList()).toList(),
    );
  }
}
