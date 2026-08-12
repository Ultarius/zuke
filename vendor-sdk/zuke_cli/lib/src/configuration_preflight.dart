import 'dart:io';

import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

/// Performs the configuration checks that must happen before any command
/// stage is allowed to execute.
///
/// Keeping this in one CLI-owned service prevents `doctor` and composed
/// commands such as `gate` from having subtly different ideas of what a
/// current workspace is. In particular, a legacy schema must be rejected at
/// the first preflight boundary rather than being discovered only after a
/// generator or validator has started.
final class ConfigurationPreflight {
  const ConfigurationPreflight();

  List<Diagnostic> diagnose(String root) {
    final configFile = File('$root/zuke.yaml');
    if (!configFile.existsSync()) {
      return [
        const Diagnostic(
          code: 'ZK-DOCTOR-001',
          stage: 'doctor',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.project,
          message: 'zuke.yaml not found',
          remediation:
              'Create a current schema-3 zuke.yaml before running Zuke.',
        ),
      ];
    }

    try {
      ZukeConfig.fromYaml(configFile.readAsStringSync(), root: root);
      return const [];
    } on Object catch (error) {
      final message = error.toString();
      final legacy =
          message.contains('schemaVersion') || message.contains('migration.md');
      return [
        Diagnostic(
          code: legacy ? 'ZK-CONFIG-LEGACY-FORMAT' : 'ZK-CONFIG-INVALID',
          stage: 'doctor',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.project,
          message: legacy
              ? 'The workspace configuration is not the current schema-3 format: $message'
              : 'The workspace configuration could not be parsed: $message',
          remediation:
              'Upgrade the Zuke packages, follow docs/migration.md, and regenerate current artifacts.',
          context: {'path': configFile.path},
        ),
      ];
    }
  }
}
