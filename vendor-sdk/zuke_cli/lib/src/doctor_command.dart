import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:zuke_core/zuke_core.dart';

import 'alignment_doctor.dart';
import 'plugin_cache.dart';
import 'index_contract.dart';
import 'cli_parser.dart';
import 'generate_command.dart';
import 'command_result.dart';
import 'configuration_preflight.dart';
import 'generated/release_contract.dart';
import 'test_host_doctor.dart';

bool _isZukePackageName(String name) =>
    name == 'zuke' || name.startsWith('zuke_');

bool _flag(ArgResults cmd, String name) =>
    cmd.options.contains(name) && cmd[name] == true;

int _runPluginCachePrune(
  ArgResults cmd, {
  required String root,
  required Set<String> entries,
  required bool dryRun,
  required bool jsonMode,
}) {
  final List<PluginCachePruneResult> results;
  try {
    results = PluginCacheDoctor.forWorkspace(root).pruneSelected(
      entries,
      currentContextRoot: p.normalize(Directory(root).absolute.path),
      dryRun: dryRun,
    );
  } on Object catch (error) {
    stderr.writeln('Could not inspect analyzer plugin cache: $error');
    return 1;
  }
  final failed = results.any((result) => result.failed);
  final bytes = results
      .where((result) => result.status == (dryRun ? 'ready' : 'pruned'))
      .fold<int>(0, (total, result) => total + result.bytes);
  final diagnostics = [
    for (final result in results.where((result) => result.failed))
      Diagnostic(
        code: 'ZUKE-PLUGIN-CACHE',
        stage: 'doctor',
        severity: DiagnosticSeverity.error,
        owner: DiagnosticOwner.project,
        message: '${result.path}: ${result.message}',
        remediation: 'Select only an unused Zuke-only synthetic cache entry.',
      ),
  ];
  final code = failed ? 1 : 0;
  final result = CommandResult(
    command: 'doctor',
    stage: 'doctor',
    exitCode: code,
    status: failed ? CommandStatus.failed : CommandStatus.passed,
    eligible: !failed,
    diagnostics: diagnostics,
    details: {
      'pluginCachePrune': results.map((entry) => entry.toJson()).toList(),
      'bytes': bytes,
      'dryRun': dryRun,
    },
  );
  final encoded = encodeCommandResult(result);
  if (jsonMode) {
    stdout.write(encoded);
  } else {
    for (final entry in results) {
      print(
        'ZUKE-PLUGIN-CACHE [${entry.status}]: ${entry.path}: ${entry.message}',
      );
    }
    print(
      '${dryRun ? 'Would reclaim' : 'Reclaimed'} '
      '${formatPluginCacheMiB(bytes)}.',
    );
  }
  writeCommandSummaryBytes(cmd['summary-file'] as String?, encoded);
  return code;
}

/// Audits a workspace's analyzer plugin caches.
///
/// Injectable so a test can exercise the rest of [runDoctor] without reaching
/// the real `~/.dartServer/.plugin_manager`. The default walks ancestor
/// directories looking for a plugin declaration, and a fixture with no Dart
/// package boundary walks all the way to the filesystem root -- which is how a
/// `doctor --fix` test could otherwise recompile a real machine's plugin cache.
typedef PluginCacheAudit =
    Future<List<PluginCacheFinding>> Function(
      String root,
      bool fix,
      Set<String>? contextRoots,
    );

Future<int> runDoctor(ArgResults cmd, {PluginCacheAudit? pluginAudit}) async {
  final root = cmd['root'] as String? ?? Directory.current.path;
  final contextRoot = p.normalize(Directory(root).absolute.path);
  final jsonMode = (cmd['format'] as String? ?? 'text') == 'json';
  final diagnostics = <Diagnostic>[];
  final fix = _flag(cmd, 'fix');
  final limitText = cmd.options.contains('max-plugin-repairs')
      ? cmd['max-plugin-repairs'] as String?
      : null;
  final maxPluginRepairs = limitText == null ? null : int.tryParse(limitText);
  final requestedEntries = cmd.options.contains('plugin-cache-entry')
      ? (cmd['plugin-cache-entry'] as List<String>).toSet()
      : <String>{};
  final currentContext = _flag(cmd, 'current-context');
  final pruneCache = _flag(cmd, 'prune-cache');
  final dryRun = _flag(cmd, 'dry-run');
  final serverStopped = _flag(cmd, 'analysis-server-stopped');
  if (pruneCache) {
    if (fix ||
        _flag(cmd, 'check-build') ||
        _flag(cmd, 'check-alignment') ||
        _flag(cmd, 'check-overrides') ||
        currentContext ||
        limitText != null ||
        requestedEntries.isEmpty ||
        (!dryRun && !serverStopped)) {
      stderr.writeln(
        '--prune-cache requires --plugin-cache-entry and either --dry-run '
        'or --analysis-server-stopped; it cannot be combined with other doctor checks or repair flags.',
      );
      return 64;
    }
    return _runPluginCachePrune(
      cmd,
      root: root,
      entries: requestedEntries,
      dryRun: dryRun,
      jsonMode: jsonMode,
    );
  }
  if (dryRun || serverStopped) {
    stderr.writeln(
      '--dry-run and --analysis-server-stopped require --prune-cache.',
    );
    return 64;
  }
  if (limitText != null && (maxPluginRepairs == null || maxPluginRepairs < 0)) {
    stderr.writeln('--max-plugin-repairs must be a non-negative integer.');
    return 64;
  }
  if (limitText != null && !fix) {
    stderr.writeln('--max-plugin-repairs requires --fix.');
    return 64;
  }
  if (requestedEntries.isNotEmpty && !fix) {
    stderr.writeln('--plugin-cache-entry requires --fix.');
    return 64;
  }
  if (currentContext && requestedEntries.isNotEmpty) {
    stderr.writeln(
      '--current-context cannot be combined with --plugin-cache-entry.',
    );
    return 64;
  }
  final checkBuild = _flag(cmd, 'check-build');
  if (!jsonMode) {
    print(
      fix
          ? 'Checking and repairing analyzer plugin caches...'
          : checkBuild
          ? 'Checking whether analyzer plugin caches build...'
          : 'Checking analyzer plugin caches...',
    );
  }
  // `--fix` already compiles every entry it repairs, so verifying buildability
  // alongside it would compile the same entry twice for no new information.
  final pluginFindings = pluginAudit == null
      ? await auditPluginCache(
          root,
          fix: fix,
          checkBuild: checkBuild && !fix,
          maxRepairs: maxPluginRepairs,
          onlyEntries: requestedEntries.isEmpty ? null : requestedEntries,
          contextRoots: currentContext ? {contextRoot} : null,
          onProgress: jsonMode || !fix
              ? null
              : (completed, total, finding) {
                  if (finding == null) {
                    print('Repairing $total plugin cache entries...');
                  } else {
                    print(
                      'Plugin repairs: $completed/$total (${finding.status})',
                    );
                  }
                },
        )
      : await pluginAudit(root, fix, currentContext ? {contextRoot} : null);
  final unmatchedContext = currentContext && pluginFindings.isEmpty;
  if (unmatchedContext) {
    final message =
        'No Zuke analyzer plugin cache entry matched the analysis '
        'context root "$contextRoot". Check the exact path and case used by '
        'the editor. If this workspace has never been analyzed, run dart analyze '
        'once to create its cache entry, then retry.';
    diagnostics.add(
      Diagnostic(
        code: 'ZUKE-PLUGIN-CACHE-CONTEXT',
        stage: 'doctor',
        severity: DiagnosticSeverity.error,
        owner: DiagnosticOwner.project,
        message: message,
        remediation:
            'Run zuke doctor without --current-context to inspect '
            'available entries, or analyze a new workspace once to create one.',
      ),
    );
    if (!jsonMode) {
      stderr.writeln('  ERROR [ZUKE-PLUGIN-CACHE-CONTEXT]: $message');
    }
  }
  if (!jsonMode) printPluginCacheFindings(pluginFindings);
  final pluginSummary = PluginCacheSummary.fromFindings(pluginFindings);
  if (!jsonMode && pluginSummary.entries > 0) {
    print(
      'Plugin cache: ${pluginSummary.entries} entries, '
      '${formatPluginCacheMiB(pluginSummary.snapshotBytes)} in snapshots.',
    );
  }
  for (final finding in pluginFindings.where((f) => f.needsRepair)) {
    diagnostics.add(
      Diagnostic(
        code: 'ZUKE-PLUGIN-CACHE',
        stage: 'doctor',
        severity: fix ? DiagnosticSeverity.error : DiagnosticSeverity.warning,
        owner: DiagnosticOwner.project,
        message: '${finding.path}: ${finding.message}',
        // Only a status a rebuild can resolve gets the rebuild advice. A plugin
        // that does not compile, or a dependency checkout that has gone away,
        // would be sent straight back to the command that already failed.
        remediation: switch (finding.status) {
          'stale' || 'unverified' =>
            'Run zuke doctor --fix, then restart the analysis server.',
          'orphaned' =>
            'Restore the local dependency checkout the entry points at, then run '
                'zuke doctor --fix.',
          _ =>
            'The entry could not be repaired automatically; see the message.',
        },
      ),
    );
  }
  var repairFailed =
      unmatchedContext || (fix && pluginFindings.any((f) => f.needsRepair));
  final releaseDetails = <String, Object?>{
    'publicPackageVersions': Map<String, String>.from(
      releasePublicPackageVersions,
    ),
    'retiredPackages': releaseRetiredPackages.toList()..sort(),
    'operatingSystems': releaseSupportedOperatingSystems,
    'compatibilityIds': Map<String, String>.from(releaseCompatibilityIds),
    'flutterCertification': releaseFlutterCertification,
  };
  final checkAlignment = _flag(cmd, 'check-alignment');
  final checkOverrides = _flag(cmd, 'check-overrides');
  if (checkOverrides && !checkAlignment) {
    // Override validation uses the same effective dependency inspection as
    // alignment; keep the two switches composable for release workflows.
  }
  int finish(int code) {
    final result = CommandResult(
      command: 'doctor',
      stage: 'doctor',
      exitCode: code,
      status: code == 0 ? CommandStatus.passed : CommandStatus.failed,
      eligible: code == 0,
      diagnostics: diagnostics,
      details: {
        'release': releaseDetails,
        'pluginCache': pluginFindings.map((f) => f.toJson()).toList(),
        'pluginCacheSummary': pluginSummary.toJson(),
        if (checkAlignment) 'alignmentChecked': true,
        if (checkOverrides) 'overridesChecked': true,
      },
    );
    final encoded = encodeCommandResult(result);
    if (jsonMode) {
      stdout.write(encoded);
    }
    writeCommandSummaryBytes(cmd['summary-file'] as String?, encoded);
    return code;
  }

  if (jsonMode) {
    // Keep JSON mode free of human-readable preamble output.
  } else {
    print('Checking project setup...');
  }

  final configurationDiagnostics = const ConfigurationPreflight().diagnose(
    root,
  );
  diagnostics.addAll(configurationDiagnostics);
  if (configurationDiagnostics.any(
    (diagnostic) => diagnostic.severity == DiagnosticSeverity.error,
  )) {
    if (!jsonMode) {
      for (final diagnostic in configurationDiagnostics) {
        stderr.writeln('  ERROR [${diagnostic.code}]: ${diagnostic.message}');
        if (diagnostic.remediation.isNotEmpty) {
          stderr.writeln('  Remediation: ${diagnostic.remediation}');
        }
      }
    }
    return finish(1);
  }
  if (fix) {
    final indexFile = File('$root/.zuke/analyzer-index.json');
    bool regenerate;
    try {
      regenerate =
          !indexFile.existsSync() ||
          ZukeIndexHeader.read(indexFile).contractVersion != zukeIndexContract;
    } on FormatException {
      regenerate = true;
    }
    if (regenerate) {
      final generate = buildZukeArgParser().parse([
        'generate',
        '--root',
        root,
        '--quiet',
      ]).command!;
      if (await GenerateCommand(generate).execute() != 0) {
        repairFailed = true;
        diagnostics.add(
          const Diagnostic(
            code: 'ZUKE-INDEX-STALE',
            stage: 'doctor',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.project,
            message: 'Index regeneration failed.',
            remediation: 'Fix generation errors and retry zuke doctor --fix.',
          ),
        );
      }
    }
  }
  if (!jsonMode) print('  zuke.yaml: found');
  if (!jsonMode) {
    for (final diagnostic in configurationDiagnostics.where(
      (diagnostic) => diagnostic.severity == DiagnosticSeverity.warning,
    )) {
      stderr.writeln('  [${diagnostic.code}] WARNING: ${diagnostic.message}');
    }
  }

  if (checkAlignment || checkOverrides) {
    final alignment = const AlignmentDoctor().inspect(Directory(root));
    diagnostics.addAll(alignment.diagnostics);
    releaseDetails['alignment'] = alignment.details;
    if (checkOverrides) {
      final overrides = alignment.details['overrides'];
      if (overrides is Map) {
        for (final entry in overrides.entries) {
          final name = entry.key.toString();
          final value = entry.value.toString();
          if (name == 'analyzer') {
            diagnostics.add(
              const Diagnostic(
                code: 'ZK-ALIGNMENT-ANALYZER-OVERRIDE',
                stage: 'doctor',
                severity: DiagnosticSeverity.error,
                owner: DiagnosticOwner.project,
                message: 'An analyzer dependency override is release-unsafe.',
                remediation:
                    'Remove the analyzer override and use a supported SDK tuple.',
              ),
            );
          }
          if (_isZukePackageName(name) && value.startsWith('path:')) {
            diagnostics.add(
              Diagnostic(
                code: 'ZK-ALIGNMENT-PATH-OVERRIDE',
                stage: 'doctor',
                severity: DiagnosticSeverity.error,
                owner: DiagnosticOwner.project,
                message: '$name uses a local path override.',
                remediation:
                    'Use a pinned hosted or Git revision for release verification.',
              ),
            );
          }
        }
      }
    }
    final overrideFailed = diagnostics.any(
      (diagnostic) => diagnostic.severity == DiagnosticSeverity.error,
    );
    if (!alignment.passed || overrideFailed) {
      if (!jsonMode) {
        for (final diagnostic in alignment.diagnostics) {
          stderr.writeln('  ERROR [${diagnostic.code}]: ${diagnostic.message}');
          if (diagnostic.remediation.isNotEmpty) {
            stderr.writeln('  Remediation: ${diagnostic.remediation}');
          }
        }
      }
      return finish(1);
    }
    if (!jsonMode) print('  Zuke dependency tuple: aligned');
  }

  final featuresDir = Directory('$root/specs/features');
  if (!featuresDir.existsSync()) {
    diagnostics.add(
      const Diagnostic(
        code: 'ZK-DOCTOR-002',
        stage: 'doctor',
        severity: DiagnosticSeverity.error,
        owner: DiagnosticOwner.project,
        message: 'specs/features/ directory not found',
        remediation:
            'Add the current specification feature directory before running Zuke.',
      ),
    );
    if (!jsonMode) {
      stderr.writeln('  ERROR: specs/features/ directory not found');
    }
    return finish(1);
  }
  final featureCount = featuresDir
      .listSync()
      .where((f) => f.path.endsWith('.feature'))
      .length;
  if (!jsonMode) print('  Feature files: $featureCount found');

  final retiredFile = File('$root/specs/registry/retired-ids.yaml');
  if (!retiredFile.existsSync()) {
    diagnostics.add(
      const Diagnostic(
        code: 'ZUKE-DOCTOR-001',
        stage: 'doctor',
        severity: DiagnosticSeverity.warning,
        owner: DiagnosticOwner.project,
        message:
            'specs/registry/retired-ids.yaml not found (retired ID governance inactive)',
        remediation:
            'Add the retired ID registry if the workspace uses ID retirement governance.',
      ),
    );
    if (!jsonMode) {
      stderr.writeln(
        '  [ZUKE-DOCTOR-001] WARNING: specs/registry/retired-ids.yaml not found (retired ID governance inactive)',
      );
    }
  } else {
    if (!jsonMode) print('  specs/registry/retired-ids.yaml: found');
  }

  if (!jsonMode) print('Doctor check complete.');
  return finish(repairFailed ? 1 : 0);
}

Future<int> runTestHostDoctor(ArgResults cmd) async {
  final root = cmd['root'] as String? ?? Directory.current.path;
  final jsonMode = (cmd['format'] as String? ?? 'text') == 'json';
  final report = TestHostDoctor(Directory(root)).inspect();
  final diagnostics = report.diagnostics;
  final compatible = report.status == 'compatible';
  final result = CommandResult(
    command: 'doctor test-host',
    stage: 'doctor',
    exitCode: compatible
        ? 0
        : report.status == 'incompatible'
        ? 1
        : 2,
    status: compatible ? CommandStatus.passed : CommandStatus.failed,
    eligible: compatible,
    diagnostics: diagnostics,
    details: {'testHost': report.details, 'root': root},
  );
  final encoded = encodeCommandResult(result);
  if (jsonMode) {
    stdout.write(encoded);
  } else {
    print('Checking consumer test-host compatibility...');
    for (final diagnostic in diagnostics) {
      final prefix = diagnostic.severity == DiagnosticSeverity.error
          ? 'ERROR'
          : 'WARNING';
      stderr.writeln('  $prefix [${diagnostic.code}]: ${diagnostic.message}');
      if (diagnostic.remediation.isNotEmpty) {
        stderr.writeln('  Remediation: ${diagnostic.remediation}');
      }
    }
    if (diagnostics.isEmpty) print('  No SDK pin conflict detected.');
  }
  writeCommandSummaryBytes(cmd['summary-file'] as String?, encoded);
  return result.exitCode;
}
