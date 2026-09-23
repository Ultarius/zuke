import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:zuke/runner.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'cli_parser.dart';
import 'command_result.dart';
import 'configuration_preflight.dart';
import 'extraction_service.dart';
import 'generator.dart';
import 'process_supervisor.dart';
import 'registration_audit.dart';
import 'scenario_selection.dart';
import 'source_output_catalog.dart';
import 'test_run_summary.dart';
import 'tool_invocation.dart';
import 'workspace_digest.dart';
import 'workspace_registration_audit.dart';

class _EvidencePublication {
  final int recordCount;
  final String evidenceOutput;
  final String? observationPath;

  const _EvidencePublication({
    required this.recordCount,
    required this.evidenceOutput,
    this.observationPath,
  });
}

void _writeSemanticEvidenceAtomic(String directory, EvidenceRecord record) {
  final root = Directory(directory)..createSync(recursive: true);
  final encoded =
      '${const JsonEncoder.withIndent('  ').convert(record.toJson())}\n';
  final digest = sha256.convert(utf8.encode(encoded)).toString();
  final semantic = File('${root.path}${Platform.pathSeparator}$digest.json');
  writeCommandResult(semantic, encoded);
}

final class TestCommandRunner {
  TestCommandRunner({required this.processSupervisor});

  final ProcessSupervisor processSupervisor;

  Future<int> runTests(ArgResults cmd) async {
    final root = cmd['root'] as String? ?? Directory.current.path;
    final workspace = requireCurrentWorkspace(root);
    final profile = cmd['profile'] as String? ?? 'pullRequest';
    final jsonMode = (cmd['format'] as String? ?? 'text') == 'json';
    final quiet =
        cmd.options.contains('quiet') && (cmd['quiet'] as bool? ?? false);
    final cliRunnerMode = runnerModeFromValue(
      cmd.options.contains('runner-mode')
          ? cmd['runner-mode'] as String?
          : null,
    );
    final selection = const ScenarioSelector().resolve(workspace, profile);
    final scenarioFilter = selection.scenarioIds;
    final selectedRequiredEvidence = selection.tagExpression == null
        ? null
        : _requiredEvidenceForSelectedScenarios(workspace, scenarioFilter);
    var ran = false;
    final artifacts = <ExecutionResult>[];
    final runRoot = Directory(
      '${workspace.config.root}${Platform.pathSeparator}generated${Platform.pathSeparator}evidence${Platform.pathSeparator}.results-$pid-${DateTime.now().microsecondsSinceEpoch}',
    ).absolute..createSync(recursive: true);
    final configuredRunners = workspace.config.executionConfig['runners'];
    // Typed runner view takes precedence; raw map remains for forward-compat
    // keys. Defaults preserved: kind `test`, runnerMode `auto`, timeout 600.
    // CLI `--runner-mode` always overrides configured runnerMode below.
    final typedRunners = {
      for (final typed in workspace.config.workspaceRunners) typed.id: typed,
    };
    try {
      if (configuredRunners is List) {
        for (final runner
            in configuredRunners.whereType<Map<Object?, Object?>>()) {
          final runnerIdForFilter = runner['id'] as String?;
          final typedRunner = runnerIdForFilter == null
              ? null
              : typedRunners[runnerIdForFilter];
          final typedProfiles = typedRunner?.profiles;
          if (typedProfiles != null &&
              (typedRunner!.hasProfileRestriction ||
                  typedProfiles.isNotEmpty)) {
            if (!typedProfiles.contains(profile)) continue;
          } else {
            final profiles = runner['profiles'];
            if (profiles is List &&
                !profiles.whereType<String>().contains(profile)) {
              continue;
            }
          }
          final runnerId = runner['id'] as String?;
          if (runnerId == null || runnerId.isEmpty) return 2;
          final runnerTarget = runner['target']?.toString();
          final runnerSourcePackage = runner['sourcePackage']?.toString();
          final runnerSourceAdapter = runner['sourceAdapter']?.toString();
          final runnerSourceCompatibilityId = runner['sourceCompatibilityId']
              ?.toString();
          final runnerCompatibilityId = runner['runnerCompatibilityId']
              ?.toString();
          if (runnerTarget == null ||
              runnerTarget.isEmpty ||
              runnerSourcePackage == null ||
              runnerSourcePackage.isEmpty ||
              runnerSourceAdapter == null ||
              runnerSourceAdapter.isEmpty ||
              runnerSourceCompatibilityId == null ||
              runnerSourceCompatibilityId.isEmpty ||
              runnerCompatibilityId == null ||
              runnerCompatibilityId.isEmpty) {
            throw StateError(
              'Runner $runnerId must declare target, sourcePackage, '
              'sourceAdapter, sourceCompatibilityId, and '
              'runnerCompatibilityId',
            );
          }
          if (!_targetContainsPackage(
            workspace,
            runnerTarget,
            runnerSourcePackage,
          )) {
            throw StateError(
              'Runner $runnerId source package $runnerSourcePackage is not '
              'configured for target $runnerTarget',
            );
          }
          final runnerKind =
              typedRunner?.kind ?? runner['kind'] as String? ?? 'test';
          if (runnerKind != 'setup' &&
              runnerKind != 'test' &&
              runnerKind != 'gherkin') {
            return 2;
          }
          final expectedRunnerScenarios = _selectedScenarioIdsForTarget(
            workspace,
            selection,
            runnerTarget,
          );
          final registrationAudit = _auditRunnerRegistrations(
            workspace,
            runner,
            expectedScenarioIds: expectedRunnerScenarios,
            knownScenarioIds: _allScenarioIds(workspace),
          );
          if (!registrationAudit.passed) {
            throw StateError(
              'ZK-REGISTRATION-AUDIT: ${registrationAudit.diagnostics.map((diagnostic) => diagnostic.toJson()).join('; ')}',
            );
          }
          // A tag-selected profile may contain scenarios for another
          // execution target.  Do not launch a target runner with an empty
          // selection: an empty result directory is correct in that case and
          // must not be confused with a runner that omitted required cases.
          // Runner-managed (unfiltered) executions still launch every runner,
          // because an empty selection there means "run all".
          if (runnerKind != 'setup' &&
              selection.tagExpression != null &&
              expectedRunnerScenarios.isEmpty) {
            continue;
          }
          final resultDirectory = Directory(
            '${runRoot.path}${Platform.pathSeparator}$runnerId',
          )..createSync(recursive: true);
          final configuredExecutable = runner['executable']?.toString();
          if (configuredExecutable == null || configuredExecutable.isEmpty) {
            return 2;
          }
          final executable = _resolveExecutable(configuredExecutable);
          if (runner['args'] != null && runner['args'] is! List) return 2;
          final args = _runnerArguments(
            configuredExecutable,
            ((runner['args'] as List?) ?? const []).cast<String>(),
          );
          final configuredRunnerMode = runnerModeFromValue(
            typedRunner?.runnerMode ?? runner['runnerMode']?.toString(),
          );
          final runnerMode = isFlutterTool(configuredExecutable)
              ? (cliRunnerMode ?? configuredRunnerMode ?? ToolRunnerMode.auto)
              : (configuredRunnerMode ?? ToolRunnerMode.auto);
          final typedWorkingDirectory = typedRunner?.workingDirectory;
          final rawWorkingDirectory = runner['workingDirectory'];
          final effectiveWorkingDirectory =
              typedWorkingDirectory ??
              (rawWorkingDirectory is String ? rawWorkingDirectory : null);
          final workingDirectory = effectiveWorkingDirectory != null
              ? Directory(
                  '${workspace.config.root}/$effectiveWorkingDirectory',
                ).path
              : root;
          if (!jsonMode && !quiet) {
            stdout.writeln(
              'runner: launching $runnerId '
              '($configuredExecutable ${args.join(' ')})',
            );
          }
          ProcessResult result;
          try {
            result = await processSupervisor.run(
              ProcessRunRequest(
                executable: executable,
                arguments: args,
                workingDirectory: workingDirectory,
                environment: {
                  ...Platform.environment,
                  'ZUKE_RESULT_DIR': resultDirectory.path,
                  'ZUKE_RUNNER_ID': runnerId,
                  'ZUKE_PROFILE': profile,
                  'ZUKE_TARGET': runnerTarget,
                  'ZUKE_SOURCE_PACKAGE': runnerSourcePackage,
                  'ZUKE_SOURCE_ADAPTER': runnerSourceAdapter,
                  'ZUKE_SOURCE_COMPATIBILITY_ID': runnerSourceCompatibilityId,
                  'ZUKE_RUNNER_COMPATIBILITY_ID': runnerCompatibilityId,
                  if (scenarioFilter.isNotEmpty)
                    'ZUKE_SCENARIO_FILTER': scenarioFilter.join(','),
                  'ZUKE_SELECTION_DIGEST': selection.digest,
                  'FLUTTER_SUPPRESS_ANALYTICS': 'true',
                },
                startupTimeout: const Duration(seconds: 60),
                executionTimeout: Duration(
                  seconds:
                      typedRunner?.timeoutSeconds ??
                      (runner['timeoutSeconds'] as num?)?.toInt() ??
                      600,
                ),
                runnerMode: runnerMode,
                firstOutputTimeout:
                    Platform.isWindows && isFlutterTool(configuredExecutable)
                    ? const Duration(seconds: 90)
                    : null,
                onStdoutChunk: (jsonMode || quiet) ? (_) {} : stdout.write,
                onStderrChunk: stderr.write,
              ),
            );
          } on SupervisedProcessException catch (error) {
            return _handleSupervisorException(error);
          }
          ran = true;
          if (result.exitCode != 0) {
            if (jsonMode) {
              stdout.writeln(
                const JsonEncoder().convert({
                  'kind': 'zuke.command-result',
                  'command': 'test',
                  'stage': 'test',
                  'exitCode': result.exitCode,
                  'status': 'failed',
                  'eligible': false,
                  'diagnostics': const <Object?>[],
                  'profile': profile,
                }),
              );
            }
            return 1;
          }
          if (runnerKind != 'setup') {
            final runnerArtifacts = _loadExecutionResults(
              resultDirectory,
              expectedRunnerId: runnerId,
              expectedProfile: profile,
              expectedTarget: runnerTarget,
              expectedSourcePackage: runnerSourcePackage,
              expectedSourceAdapter: runnerSourceAdapter,
              expectedSourceCompatibilityId: runnerSourceCompatibilityId,
            );
            final configuredEvidenceTypes =
                ((runner['evidenceTypes'] as List?) ?? const [])
                    .whereType<String>()
                    .toSet();
            final expectedTypes = selectedRequiredEvidence == null
                ? configuredEvidenceTypes
                : configuredEvidenceTypes.intersection(
                    selectedRequiredEvidence,
                  );
            if (runnerArtifacts.isEmpty && expectedTypes.isNotEmpty) {
              throw StateError(
                'Runner $runnerId succeeded without producing result artifacts',
              );
            }
            if (expectedTypes.isNotEmpty) {
              final observedTypes = runnerArtifacts
                  .map((a) => a.evidenceType)
                  .toSet();
              final missing = expectedTypes.difference(observedTypes);
              if (missing.isNotEmpty) {
                throw StateError(
                  'Runner $runnerId did not produce expected results: ${missing.toList()..sort()}',
                );
              }
            }
            final executionAudit = const RegistrationExecutionAudit().reconcile(
              registrations: registrationAudit.registrations,
              executions: runnerArtifacts,
              selectedScenarioIds: expectedRunnerScenarios,
              target: runnerTarget,
            );
            if (!executionAudit.passed) {
              throw StateError(
                'ZK-REGISTRATION-EXECUTION: ${executionAudit.diagnostics.map((diagnostic) => diagnostic.toJson()).join('; ')}',
              );
            }
            artifacts.addAll(runnerArtifacts);
          }
        }
      }
      for (final entry in workspace.config.targetsConfig.entries) {
        final config = entry.value;
        if (config is! Map) continue;
        final configured = config['runner'] ?? config['testCommand'];
        if (configured == null) continue;
        if (configured is String) {
          stderr.writeln(
            'Runner configuration must use executable and args arrays; shell strings are not supported.',
          );
          return 2;
        }
        final configuredExecutable = configured is Map
            ? configured['executable'] as String?
            : null;
        if (configuredExecutable == null || configuredExecutable.isEmpty) {
          return 2;
        }
        final executable = _resolveExecutable(configuredExecutable);
        final configuredParts = configured is Map
            ? ((configured['args'] as List?) ?? const []).cast<String>()
            : const <String>[];
        final parts = _runnerArguments(configuredExecutable, configuredParts);
        final configuredRunnerMode = runnerModeFromValue(
          configured is Map ? configured['runnerMode']?.toString() : null,
        );
        final runnerMode = isFlutterTool(configuredExecutable)
            ? (cliRunnerMode ?? configuredRunnerMode ?? ToolRunnerMode.auto)
            : (configuredRunnerMode ?? ToolRunnerMode.auto);
        final workingDirectory = config['path'] is String
            ? Directory('${workspace.config.root}/${config['path']}').path
            : root;
        if (!jsonMode && !quiet) {
          stdout.writeln(
            'runner: launching ${entry.key} '
            '($configuredExecutable ${parts.join(' ')})',
          );
        }
        ProcessResult result;
        try {
          result = await processSupervisor.run(
            ProcessRunRequest(
              executable: executable,
              arguments: parts,
              workingDirectory: workingDirectory,
              environment: {
                ...Platform.environment,
                'FLUTTER_SUPPRESS_ANALYTICS': 'true',
              },
              startupTimeout: const Duration(seconds: 60),
              executionTimeout: Duration(
                seconds: (config['timeoutSeconds'] as num?)?.toInt() ?? 600,
              ),
              runnerMode: runnerMode,
              firstOutputTimeout:
                  Platform.isWindows && isFlutterTool(configuredExecutable)
                  ? const Duration(seconds: 90)
                  : null,
              onStdoutChunk: (jsonMode || quiet) ? (_) {} : stdout.write,
              onStderrChunk: stderr.write,
            ),
          );
        } on SupervisedProcessException catch (error) {
          return _handleSupervisorException(error);
        }
        ran = true;
        if (result.exitCode != 0) {
          if (jsonMode) {
            stdout.writeln(
              const JsonEncoder().convert({
                'kind': 'zuke.command-result',
                'command': 'test',
                'stage': 'test',
                'exitCode': result.exitCode,
                'status': 'failed',
                'eligible': false,
                'diagnostics': const <Object?>[],
                'profile': profile,
              }),
            );
          }
          return 1;
        }
      }
      if (!ran) {
        stderr.writeln('No configured test runners.');
        return 2;
      }

      late final _EvidencePublication publication;
      try {
        publication = await _publishEvidence(
          workspace,
          profile,
          selection: selection,
          artifacts: artifacts,
        );
      } on StateError catch (error) {
        stderr.writeln('ZUKE-EVIDENCE-EXECUTION: $error');
        return 1;
      }

      final summary = TestRunSummary(
        profile: profile,
        runnersExecuted: ran,
        selectionDigest: selection.digest,
        scenarioIds: selection.scenarioIds,
        evidenceRecords: publication.recordCount,
        evidenceOutput: publication.evidenceOutput,
        evidenceObservation: publication.observationPath,
      );
      if (jsonMode) {
        stdout.writeln(const JsonEncoder().convert(summary.toJson()));
      } else if (!quiet) {
        for (final line in summary.toTextLines()) {
          stdout.writeln(line);
        }
      }
      return 0;
    } on StateError catch (error) {
      stderr.writeln('ZUKE-EVIDENCE-EXECUTION: $error');
      return 1;
    } finally {
      if (runRoot.existsSync()) runRoot.deleteSync(recursive: true);
    }
  }

  Future<_EvidencePublication> _publishEvidence(
    WorkspaceDiscoveryResult workspace,
    String profile, {
    required ScenarioSelection selection,
    List<ExecutionResult> artifacts = const [],
  }) async {
    final evidencePath =
        workspace.config.evidenceOutput ?? 'generated/evidence/records';
    final directory = Directory('${workspace.config.root}/$evidencePath');
    final records = await _recordsFromArtifacts(workspace, profile, artifacts);

    // A successful process exit is insufficient: an incomplete (or overly
    // broad) run must never atomically replace the last accepted evidence.
    if (selection.tagExpression != null) {
      final declared = _declaredScenarioIds(workspace);
      final observed = <String>{
        for (final record in records) ...[
          if (record.candidateId != null &&
              declared.contains(record.candidateId))
            record.candidateId!,
          ...record.scenarioIds.map((id) => id.value).where(declared.contains),
        ],
      };
      final selected = selection.scenarioIds.toSet();
      final missing = selected.difference(observed).toList()..sort();
      if (missing.isNotEmpty) {
        throw StateError('ZUKE-SCENARIO-UNTESTED: ${missing.join(', ')}');
      }
      final unexpected = observed.difference(selected).toList()..sort();
      if (unexpected.isNotEmpty) {
        throw StateError('ZUKE-SCENARIO-UNEXPECTED: ${unexpected.join(', ')}');
      }
    }

    // Extracted symbols and `requiredEvidence` declarations are candidates,
    // never evidence. Only records emitted by a successfully executed runner
    // may cross this boundary.
    if (records.isEmpty) {
      final hasRequiredEvidence = selection.tagExpression == null
          ? workspace.data.features.any(
              (feature) => feature.rules.any(
                (rule) =>
                    rule.metadata.requiredEvidence != null &&
                    rule.metadata.requiredEvidence!.isNotEmpty,
              ),
            )
          : _requiredEvidenceForSelectedScenarios(
              workspace,
              selection.scenarioIds,
            ).isNotEmpty;
      if (hasRequiredEvidence) {
        throw StateError('No execution result artifacts were produced');
      }
      return _EvidencePublication(
        recordCount: 0,
        evidenceOutput: directory.path,
      );
    }

    // Profile runs share the configured evidence directory. Replace only the
    // current profile's records so sequential profile execution retains the
    // independently proved records needed by later validation and lock
    // construction. Malformed files are intentionally not carried forward;
    // the successful current run replaces the publication set atomically.
    final retainedRecords = _loadPublishedEvidence(
      directory,
    ).where((record) => record.profile != profile).toList(growable: false);
    final publishedRecords = <EvidenceRecord>[...retainedRecords, ...records];

    final staging = Directory(
      '${directory.path}.publish-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    final backup = Directory('${staging.path}.previous');
    try {
      for (final record in publishedRecords) {
        _writeSemanticEvidenceAtomic(staging.path, record);
      }
      if (directory.existsSync()) await _renameDirectory(directory, backup);
      try {
        await _renameDirectory(staging, directory);
      } catch (_) {
        if (backup.existsSync() && !directory.existsSync()) {
          await _renameDirectory(backup, directory);
        }
        rethrow;
      }
      if (backup.existsSync()) backup.deleteSync(recursive: true);
      final observationDirectory = Directory(
        '${workspace.config.root}${Platform.pathSeparator}generated${Platform.pathSeparator}evidence${Platform.pathSeparator}runs',
      )..createSync(recursive: true);
      final recordDigests =
          records
              .map((record) => _sha256Text(canonicalJson(record.toJson())))
              .toList()
            ..sort();
      final observation = <String, Object?>{
        'kind': 'zuke.evidence-observation',
        'profile': profile,
        'observedAt': DateTime.now().toUtc().toIso8601String(),
        'recordDigests': recordDigests,
        'selection': selection.toJson(),
      };
      final observationFile = File(
        '${observationDirectory.path}${Platform.pathSeparator}${DateTime.now().toUtc().microsecondsSinceEpoch}.json',
      );
      final observationTemporary = File('${observationFile.path}.tmp');
      observationTemporary.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(observation)}\n',
        flush: true,
      );
      observationTemporary.renameSync(observationFile.path);
      selection.writeAtomic(
        File(
          '${observationDirectory.path}${Platform.pathSeparator}selection-$profile.json',
        ),
      );
      return _EvidencePublication(
        recordCount: records.length,
        evidenceOutput: directory.path,
        observationPath: observationFile.path,
      );
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
  }

  List<EvidenceRecord> _loadPublishedEvidence(Directory directory) {
    if (!directory.existsSync()) return const [];
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final records = <EvidenceRecord>[];
    for (final file in files) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is! Map) continue;
        records.add(
          EvidenceRecord.fromJson(Map<Object?, Object?>.from(decoded)),
        );
      } on Object {
        // A fresh successful profile run is allowed to replace malformed
        // prior publication files instead of carrying them forward.
      }
    }
    return records;
  }

  Future<void> _renameDirectory(Directory source, Directory destination) async {
    Object? lastError;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        source.renameSync(destination.path);
        return;
      } on FileSystemException catch (error) {
        lastError = error;
        await Future<void>.delayed(Duration(milliseconds: 25 * (attempt + 1)));
      }
    }
    throw lastError ?? StateError('Could not rename ${source.path}');
  }

  List<ExecutionResult> _loadExecutionResults(
    Directory directory, {
    required String expectedRunnerId,
    required String expectedProfile,
    String? expectedTarget,
    String? expectedSourcePackage,
    String? expectedSourceAdapter,
    String? expectedSourceCompatibilityId,
  }) {
    final artifacts = <ExecutionResult>[];
    final executionIds = <String>{};
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final file in files) {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        throw StateError('Result artifact is not an object: ${file.path}');
      }
      final json = Map<String, Object?>.from(decoded);
      final ExecutionResult artifact = switch (json['kind']) {
        'zuke.scenario-result' => ScenarioResult.fromJson(json),
        'zuke.suite-result' => SuiteResult.fromJson(json),
        _ => throw StateError(
          'Unsupported result artifact schema in ${file.path}',
        ),
      };
      if (artifact.runnerId != expectedRunnerId) {
        throw StateError(
          'Result artifact runner mismatch in ${file.path}: '
          '${artifact.runnerId} != $expectedRunnerId',
        );
      }
      if (artifact.profile != expectedProfile) {
        throw StateError(
          'Result artifact profile mismatch in ${file.path}: '
          '${artifact.profile} != $expectedProfile',
        );
      }
      if (expectedTarget != null && artifact.target != expectedTarget) {
        throw StateError(
          'Result artifact target mismatch in ${file.path}: '
          '${artifact.target} != $expectedTarget',
        );
      }
      if (expectedSourcePackage != null &&
          artifact.sourcePackage != expectedSourcePackage) {
        throw StateError(
          'Result artifact source package mismatch in ${file.path}: '
          '${artifact.sourcePackage ?? '(missing)'} != $expectedSourcePackage',
        );
      }
      if (expectedSourceAdapter != null &&
          artifact.sourceAdapter != expectedSourceAdapter) {
        throw StateError(
          'Result artifact source adapter mismatch in ${file.path}: '
          '${artifact.sourceAdapter ?? '(missing)'} != $expectedSourceAdapter',
        );
      }
      if (expectedSourceCompatibilityId != null &&
          artifact.sourceCompatibilityId != expectedSourceCompatibilityId) {
        throw StateError(
          'Result artifact source compatibility mismatch in ${file.path}: '
          '${artifact.sourceCompatibilityId ?? '(missing)'} != '
          '$expectedSourceCompatibilityId',
        );
      }
      final executionId = artifact.executionId;
      if (!executionIds.add(executionId)) {
        throw StateError('Duplicate execution result: $executionId');
      }
      artifacts.add(artifact);
    }
    return artifacts;
  }

  bool _targetContainsPackage(
    WorkspaceDiscoveryResult workspace,
    String target,
    String packageId,
  ) =>
      workspace.config.workspaceTargets[target]?.packages.any(
        (package) => package.id == packageId,
      ) ??
      false;

  RegistrationAuditResult _auditRunnerRegistrations(
    WorkspaceDiscoveryResult workspace,
    Map<Object?, Object?> runner, {
    required Set<String> expectedScenarioIds,
    required Set<String> knownScenarioIds,
  }) => const WorkspaceRegistrationAudit().inspectRunner(
    workspace,
    target: runner['target']?.toString(),
    sourcePackage: runner['sourcePackage']?.toString(),
    workingDirectory: runner['workingDirectory']?.toString(),
    expectedScenarioIds: expectedScenarioIds,
    knownScenarioIds: knownScenarioIds,
  );

  Set<String> _allScenarioIds(WorkspaceDiscoveryResult workspace) => {
    for (final feature in workspace.data.features)
      for (final rule in feature.rules)
        for (final scenario in rule.scenarios)
          for (final tag in scenario.tags)
            if (tag.name.startsWith('SCN-')) tag.name,
  };

  Set<String> _selectedScenarioIdsForTarget(
    WorkspaceDiscoveryResult workspace,
    ScenarioSelection selection,
    String target,
  ) {
    final selected = selection.scenarioIds.toSet();
    final result = <String>{};
    for (final feature in workspace.data.features) {
      final targets = feature.metadata.targets;
      if (targets != null && targets.isNotEmpty && !targets.contains(target)) {
        continue;
      }
      for (final rule in feature.rules) {
        // Feature targets describe the broad product surface, while the
        // rule-level evidence slots identify which configured execution
        // target actually proves a rule. A feature can legitimately contain
        // backend, Flutter, and dashboard rules together, so selecting every
        // scenario from a multi-target feature would report valid
        // target-specific registrations as missing.
        final evidenceTargets = (rule.metadata.evidenceRequirements ?? const [])
            .map((slot) => slot['target'])
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toSet();
        if (evidenceTargets.isNotEmpty && !evidenceTargets.contains(target)) {
          continue;
        }
        for (final scenario in rule.scenarios) {
          final scenarioTags = scenario.tags
              .map((tag) => tag.name.replaceFirst('@', '').toLowerCase())
              .toSet();
          // Rule evidence is intentionally aggregated for the rule, but a
          // scenario can still be target-specific. Do not make a backend
          // runner register a UI-only case, or a Flutter runner register an
          // API-only case, merely because sibling scenarios in the same rule
          // have evidence for both targets. Shared cases tagged with both
          // `api` and `ui` remain selected for both targets.
          if (target == 'backend' &&
              scenarioTags.contains('ui') &&
              !scenarioTags.contains('api')) {
            continue;
          }
          if (target == 'flutter' &&
              scenarioTags.contains('api') &&
              !scenarioTags.contains('ui')) {
            continue;
          }
          for (final tag in scenario.tags) {
            if (tag.name.startsWith('SCN-') && selected.contains(tag.name)) {
              result.add(tag.name);
            }
          }
        }
      }
    }
    return result;
  }

  Future<List<EvidenceRecord>> _recordsFromArtifacts(
    WorkspaceDiscoveryResult workspace,
    String profile,
    List<ExecutionResult> artifacts,
  ) async {
    if (artifacts.isEmpty) return const [];
    // Previous evidence is the replaceable publication target. It must not
    // prevent a successful new runner result from being validated and
    // atomically replacing stale or malformed records.
    final extraction = await ExtractionService().extract(
      workspace,
      includeEvidence: false,
    );
    if (extraction.errors.isNotEmpty) {
      throw StateError(
        'Cannot bind execution results while extraction is invalid: '
        '${extraction.errors.join('; ')}',
      );
    }
    final sourceCatalog = SourceOutputCatalog.build(
      workspace,
      extraction.outputs,
    );
    final generated = DartContractGenerator().generate(
      workspace: workspace,
      outputDir: workspace.config.contractOutput ?? 'lib/src/generated',
      exportPath: workspace.config.contractExport,
    );
    final contractDigest = _sha256Text(generated.manifest.toJson());
    final evidenceDigests = WorkspaceDigest.computeEvidenceIndexDigests(
      workspace.config.root!,
    );
    final mappingDigest = evidenceDigests['mapping']!;
    final specificationIndexDigest = evidenceDigests['specificationIndex']!;
    final records = <EvidenceRecord>[];
    final evidenceKeys = <String>{};
    for (final artifact in artifacts) {
      if (artifact.profile != profile) {
        throw StateError('Execution result belongs to a different profile');
      }
      if (!artifact.isPassed) {
        throw StateError(
          'Execution result ${artifact.executionId} is not passed',
        );
      }
      final requirementId = artifact.requirementId;
      final target = artifact.target;
      final SourceOutputResolution sourceResolution;
      try {
        sourceResolution = sourceCatalog.resolve(
          target: target,
          sourcePackage: artifact.sourcePackage ?? '',
          sourceAdapter: artifact.sourceAdapter ?? '',
          sourceCompatibilityId: artifact.sourceCompatibilityId ?? '',
        );
      } on SourceResolveFailure catch (failure) {
        throw FormatException('$failure');
      }
      final sourceOutput = sourceResolution.output;
      final sourceDigest = _normalizeHash(sourceOutput.inputDigest);
      final artifactJson = Map<String, Object?>.from(artifact.toJson())
        ..remove('profile');
      final record = EvidenceRecord(
        requirementId: requirementId,
        evidenceType: artifact.evidenceType,
        target: target,
        variant: artifact.variant,
        executionId: artifact.executionId,
        status: EvidenceStatus.passed,
        scenarioIds: artifact.scenarioIds,
        controlIds: artifact.controlIds,
        implementationSlots: artifact.implementationSlots,
        digests: {
          'source': sourceDigest,
          'contract': contractDigest,
          'mapping': mappingDigest,
          'specificationIndex': specificationIndexDigest,
          'result': _sha256Text(canonicalJson(artifactJson)),
        },
        candidateId: artifact.candidateId,
        profile: profile,
        runnerId: artifact.runnerId,
        runnerCompatibilityId: artifact.runnerCompatibilityId,
        sourcePackage: artifact.sourcePackage,
        sourceAdapter: artifact.sourceAdapter,
        sourceCompatibilityId: artifact.sourceCompatibilityId,
        attachmentDigests: artifact.attachmentDigests,
      );
      final key = [
        record.requirementId,
        record.evidenceType,
        record.target,
        record.variant,
        record.sourcePackage,
        record.sourceAdapter,
        record.executionId,
      ].join('|');
      if (!evidenceKeys.add(key)) {
        throw StateError('Duplicate evidence key: $key');
      }
      // Round-trip through the strict boundary validator before publication.
      records.add(EvidenceRecord.fromJson(record.toJson()));
    }
    return records;
  }

  String _sha256Text(String value) =>
      'sha256:${sha256.convert(utf8.encode(value))}';

  String _normalizeHash(String value) =>
      value.startsWith('sha256:') ? value : 'sha256:$value';

  Set<String> _declaredScenarioIds(WorkspaceDiscoveryResult workspace) => {
    for (final feature in workspace.data.features)
      for (final rule in feature.rules)
        for (final scenario in rule.scenarios)
          ...[
            ...scenario.tags.map((tag) => tag.name),
            for (final examples in scenario.examples)
              ...examples.tags.map((tag) => tag.name),
          ].where((tag) => tag.startsWith('SCN-')),
  };

  Set<String> _requiredEvidenceForSelectedScenarios(
    WorkspaceDiscoveryResult workspace,
    Iterable<String> selectedScenarioIds,
  ) {
    final selected = selectedScenarioIds.toSet();
    final required = <String>{};
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        final containsSelectedScenario = rule.scenarios.any(
          (scenario) => [
            ...scenario.tags.map((tag) => tag.name),
            for (final examples in scenario.examples)
              ...examples.tags.map((tag) => tag.name),
          ].any(selected.contains),
        );
        if (containsSelectedScenario) {
          required.addAll(rule.metadata.requiredEvidence ?? const []);
        }
      }
    }
    return required;
  }

  String _resolveExecutable(String executable) {
    // `flutter test` can launch this CLI with the embedded Dart SDK even when
    // the SDK's bin directory is not present in PATH (notably on Windows
    // desktop shells). Resolve that exact SDK before falling back to PATH.
    if (executable == 'dart') {
      final resolved = File(Platform.resolvedExecutable);
      if (resolved.existsSync() &&
          resolved.path.toLowerCase().endsWith(
            Platform.isWindows ? 'dart.exe' : 'dart',
          )) {
        return resolved.absolute.path;
      }
    }
    if (!Platform.isWindows) return executable;
    try {
      final result = Process.runSync('where.exe', [executable]);
      if (result.exitCode == 0) {
        final candidates = result.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        for (final candidate in candidates) {
          final path =
              [
                candidate,
                '$candidate.bat',
                '$candidate.cmd',
                '$candidate.exe',
              ].firstWhere((value) {
                final extension = value.toLowerCase().split('.').last;
                return File(value).existsSync() &&
                    const {'bat', 'cmd', 'exe'}.contains(extension);
              }, orElse: () => '');
          if (path.isNotEmpty) return path;
        }
      }
    } catch (_) {
      // Process.run will produce the stable tooling error if resolution fails.
    }
    return executable;
  }

  List<String> _runnerArguments(String executable, List<String> configured) {
    final name = executable.replaceAll('\\', '/').split('/').last.toLowerCase();
    if ((name == 'dart' || name == 'dart.exe') &&
        !configured.contains('--disable-dart-dev')) {
      return ['--disable-dart-dev', '--suppress-analytics', ...configured];
    }
    return configured;
  }

  int _handleSupervisorException(SupervisedProcessException error) {
    stderr.writeln('${error.diagnosticCode}: ${error.message}');
    return 3;
  }
}
