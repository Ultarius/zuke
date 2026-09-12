import 'dart:io';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke/runner.dart';
import 'configuration_preflight.dart';
import 'registration_audit.dart';

/// Static registration checks over configured runner roots and contracts.
/// Execution evidence is verified separately by the managed test command.
final class WorkspaceRegistrationAudit {
  const WorkspaceRegistrationAudit();

  RegistrationAuditResult inspect(String root) {
    final workspace = requireCurrentWorkspace(root);
    final known = _scenarioCaseIds(workspace).keys.toSet();
    final registrations = <ZukeRegistration>[];
    final diagnostics = <RegistrationAuditDiagnostic>[];
    for (final error in workspace.data.errors) {
      diagnostics.add(
        RegistrationAuditDiagnostic(
          code: 'ZK-REGISTRATION-WORKSPACE-INVALID',
          message: error,
          file: '<configured-specification>',
          line: 1,
          column: 1,
        ),
      );
    }
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        for (final scenario in rule.scenarios) {
          if (scenario.tags
                  .where((tag) => tag.name.startsWith('SCN-'))
                  .length !=
              1) {
            diagnostics.add(
              const RegistrationAuditDiagnostic(
                code: 'ZK-REGISTRATION-SCENARIO-IDENTITY',
                message:
                    'Each configured scenario must have exactly one SCN- tag.',
                file: '<configured-specification>',
                line: 1,
                column: 1,
              ),
            );
          }
        }
      }
    }
    final runners = workspace.config.executionConfig['runners'];
    final inspected = <String>{};
    final sourceRegistrations = <String>{};
    final identities = <String>{};
    final runnerSources = <_RunnerSources>[];
    final allFiles = <String, File>{};
    final diagnosticKeys = <String>{};
    if (runners is List) {
      for (final runner in runners.whereType<Map>()) {
        final target = runner['target']?.toString();
        final sourcePackage = runner['sourcePackage']?.toString();
        final workingDirectory = runner['workingDirectory']?.toString();
        if (!inspected.add('$target|$sourcePackage|$workingDirectory')) {
          continue;
        }
        final sources = _collectRunnerSources(
          workspace,
          target: target,
          sourcePackage: sourcePackage,
          workingDirectory: workingDirectory,
        );
        if (sources.diagnostic != null) {
          diagnostics.add(sources.diagnostic!);
          continue;
        }
        runnerSources.add(sources);
        for (final entry in sources.files.entries) {
          allFiles.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }
    final snapshot = const RegistrationAudit().prepareFiles(allFiles.values);
    final scenarioCaseIds = _scenarioCaseIds(workspace);
    for (final sources in runnerSources) {
      final result = const RegistrationAudit().inspectSnapshot(
        snapshot,
        files: sources.files.values,
        expectedScenarioIds: const {},
        knownScenarioIds: known,
        scenarioCaseIds: scenarioCaseIds,
        targetForFile: (_) => sources.target,
      );
      for (final registration in result.registrations) {
        final source =
            '${registration.file}|${registration.line}|'
            '${registration.column}|${registration.target}';
        if (!sourceRegistrations.add(source)) continue;
        registrations.add(registration);
        if (registration.scenarioId == null) continue;
        final identity =
            '${registration.runner}|${registration.target}|'
            '${registration.scenarioId}|${registration.caseId}';
        if (!identities.add(identity)) {
          diagnostics.add(
            RegistrationAuditDiagnostic(
              code: 'ZK-REGISTRATION-DUPLICATE-IDENTITY',
              message:
                  'Registration identity $identity is declared more than once.',
              file: registration.file,
              line: registration.line,
              column: registration.column,
            ),
          );
        }
      }
      for (final diagnostic in result.diagnostics) {
        final key =
            '${diagnostic.code}|${diagnostic.file}|${diagnostic.line}|'
            '${diagnostic.column}|${diagnostic.message}';
        if (diagnosticKeys.add(key)) diagnostics.add(diagnostic);
      }
    }
    final registered = registrations
        .map((entry) => entry.scenarioId)
        .whereType<String>()
        .toSet();
    for (final missing in known.difference(registered).toList()..sort()) {
      diagnostics.add(
        RegistrationAuditDiagnostic(
          code: 'ZK-REGISTRATION-EXPECTED-MISSING',
          message:
              'Configured scenario $missing has no direct Zuke registration.',
          file: '<configured-specification>',
          line: 1,
          column: 1,
        ),
      );
    }
    return RegistrationAuditResult(
      registrations: List.unmodifiable(registrations),
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  RegistrationAuditResult inspectRunner(
    WorkspaceDiscoveryResult workspace, {
    required String? target,
    required String? sourcePackage,
    String? workingDirectory,
    required Set<String> expectedScenarioIds,
    required Set<String> knownScenarioIds,
  }) {
    final sources = _collectRunnerSources(
      workspace,
      target: target,
      sourcePackage: sourcePackage,
      workingDirectory: workingDirectory,
    );
    if (sources.diagnostic != null) {
      return RegistrationAuditResult(
        registrations: const [],
        diagnostics: [sources.diagnostic!],
      );
    }
    final snapshot = const RegistrationAudit().prepareFiles(
      sources.files.values,
    );
    return const RegistrationAudit().inspectSnapshot(
      snapshot,
      expectedScenarioIds: expectedScenarioIds,
      knownScenarioIds: knownScenarioIds,
      scenarioCaseIds: _scenarioCaseIds(workspace),
      targetForFile: (_) => target,
    );
  }

  _RunnerSources _collectRunnerSources(
    WorkspaceDiscoveryResult workspace, {
    required String? target,
    required String? sourcePackage,
    String? workingDirectory,
  }) {
    final targetConfig = workspace.config.workspaceTargets[target];
    WorkspacePackage? package;
    if (targetConfig != null) {
      for (final candidate in targetConfig.packages) {
        if (candidate.id == sourcePackage) {
          package = candidate;
          break;
        }
      }
    }
    if (package == null) {
      return _RunnerSources(
        target: target,
        files: const {},
        diagnostic: RegistrationAuditDiagnostic(
          code: 'ZK-REGISTRATION-PACKAGE-MISSING',
          message:
              'Runner source package $sourcePackage is not configured for target $target.',
          file: '<zuke.yaml>',
          line: 1,
          column: 1,
        ),
      );
    }
    final files = <String, File>{};
    void addDirectory(String path, {bool contracts = false}) {
      final directory = Directory(path);
      if (!directory.existsSync()) return;
      for (final file
          in directory
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final normalizedFilePath = file.path.replaceAll('\\', '/');
        if (contracts ||
            file.path.endsWith('_test.dart') ||
            normalizedFilePath.contains('/generated/')) {
          files[Platform.isWindows
                  ? file.absolute.path.toLowerCase()
                  : file.absolute.path] =
              file;
        }
      }
    }

    final packageRoot = Directory(
      '${workspace.config.root}${Platform.pathSeparator}${package.path}',
    ).path;
    // Contract generation is configured on a target in schema v3. The
    // convenience `config.contractOutput` value is intentionally only the
    // first configured output, which is insufficient for a runner whose
    // source package belongs to another target (a common workspace layout is
    // a Flutter target consuming contracts generated for a separate target).
    // Inspect every configured target so generated enum constants are
    // available to the Analyzer-based registration audit regardless of which
    // target owns the runner.
    final contractOutputs = <String>{};
    final topLevelContractOutput = workspace.config.contractOutput;
    if (topLevelContractOutput != null && topLevelContractOutput.isNotEmpty) {
      contractOutputs.add(topLevelContractOutput);
    }
    for (final target in workspace.config.targetsConfig.values) {
      if (target is! Map) continue;
      final output = target['contractOutput'];
      if (output is String && output.trim().isNotEmpty) {
        contractOutputs.add(output);
      }
    }
    for (final contractOutput in contractOutputs) {
      addDirectory(
        '${workspace.config.root}${Platform.pathSeparator}$contractOutput',
        contracts: true,
      );
    }
    addDirectory('$packageRoot${Platform.pathSeparator}test');
    addDirectory('$packageRoot${Platform.pathSeparator}integration_test');
    for (final configuredRoot in package.roots) {
      addDirectory('$packageRoot${Platform.pathSeparator}$configuredRoot');
    }
    if (workingDirectory != null && workingDirectory.isNotEmpty) {
      final runnerRoot = Directory(
        '${workspace.config.root}${Platform.pathSeparator}$workingDirectory',
      ).path;
      addDirectory('$runnerRoot${Platform.pathSeparator}test');
      addDirectory('$runnerRoot${Platform.pathSeparator}integration_test');
    }
    return _RunnerSources(target: target, files: Map.unmodifiable(files));
  }

  Map<String, Iterable<String?>> _scenarioCaseIds(
    WorkspaceDiscoveryResult workspace,
  ) {
    final result = <String, Set<String?>>{};
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        for (final scenario in rule.scenarios) {
          final ids = scenario.tags
              .map((tag) => tag.name)
              .where((tag) => tag.startsWith('SCN-'));
          final caseIds = scenarioExampleCases(
            scenario,
          ).map(scenarioExampleCaseId).toSet();
          for (final scenarioId in ids) {
            result.putIfAbsent(scenarioId, () => <String?>{}).addAll(caseIds);
          }
        }
      }
    }
    return result;
  }
}

final class _RunnerSources {
  const _RunnerSources({
    required this.target,
    required this.files,
    this.diagnostic,
  });

  final String? target;
  final Map<String, File> files;
  final RegistrationAuditDiagnostic? diagnostic;
}
