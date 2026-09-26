import 'dart:io';

import 'package:args/args.dart';
import 'package:zuke_core/zuke_core.dart';

import 'alignment_doctor.dart';
import 'command_result.dart';
import 'configuration_preflight.dart';
import 'generated/release_contract.dart';
import 'test_host_doctor.dart';

bool _isZukePackageName(String name) =>
    name == 'zuke' || name.startsWith('zuke_');

Future<int> runDoctor(ArgResults cmd) async {
  final root = cmd['root'] as String? ?? Directory.current.path;
  final jsonMode = (cmd['format'] as String? ?? 'text') == 'json';
  final diagnostics = <Diagnostic>[];
  final releaseDetails = <String, Object?>{
    'publicPackageVersions': Map<String, String>.from(
      releasePublicPackageVersions,
    ),
    'retiredPackages': releaseRetiredPackages.toList()..sort(),
    'operatingSystems': releaseSupportedOperatingSystems,
    'compatibilityIds': Map<String, String>.from(releaseCompatibilityIds),
    'flutterCertification': releaseFlutterCertification,
  };
  final checkAlignment =
      cmd.options.contains('check-alignment') &&
      (cmd['check-alignment'] as bool? ?? false);
  final checkOverrides =
      cmd.options.contains('check-overrides') &&
      (cmd['check-overrides'] as bool? ?? false);
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
  return finish(0);
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
