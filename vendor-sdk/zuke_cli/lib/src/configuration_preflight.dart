import 'dart:io';

import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

final class WorkspacePreflightResult {
  final String root;
  final WorkspaceDiscoveryResult? workspace;
  final List<Diagnostic> diagnostics;

  const WorkspacePreflightResult({
    required this.root,
    this.workspace,
    this.diagnostics = const [],
  });

  bool get eligible =>
      workspace != null &&
      diagnostics.every(
        (diagnostic) => diagnostic.severity != DiagnosticSeverity.error,
      );
}

/// Performs the configuration checks that must happen before any command
/// stage is allowed to execute.
///
/// Keeping this in one CLI-owned service prevents `doctor` and composed
/// commands such as `gate` from having subtly different ideas of what a
/// current workspace is. In particular, a legacy schema must be rejected at
/// the first preflight boundary rather than being discovered only after a
/// generator or validator has started.
final class WorkspacePreflight {
  const WorkspacePreflight();

  WorkspacePreflightResult inspect(String root) {
    final canonicalRoot = _canonicalRoot(root);
    final configFile = File('$root/zuke.yaml');
    if (!configFile.existsSync()) {
      return WorkspacePreflightResult(
        root: canonicalRoot,
        diagnostics: [
          const Diagnostic(
            code: 'ZK-DOCTOR-001',
            stage: 'doctor',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.project,
            message: 'zuke.yaml not found',
            remediation:
                'Create a current schema-3 zuke.yaml before running Zuke.',
          ),
        ],
      );
    }

    try {
      final workspace = WorkspaceDiscovery().discover(canonicalRoot);
      // Surface non-fatal config warnings as structured warning diagnostics.
      // Warnings never block eligibility and never touch stdout directly;
      // JSON consumers read them from the command-result diagnostics array.
      final warnings = [
        for (final warning in workspace.config.warnings)
          Diagnostic(
            code: 'ZK-CONFIG-UNKNOWN-KEY',
            stage: 'doctor',
            severity: DiagnosticSeverity.warning,
            owner: DiagnosticOwner.project,
            message: warning.message,
            remediation:
                'Remove the unrecognized key or pin a CLI that documents it.',
            context: {'path': warning.path},
          ),
      ];
      return WorkspacePreflightResult(
        root: canonicalRoot,
        workspace: workspace,
        diagnostics: warnings,
      );
    } on LegacyWorkspaceConfigError catch (error) {
      return WorkspacePreflightResult(
        root: canonicalRoot,
        diagnostics: [
          Diagnostic(
            code: 'ZK-CONFIG-LEGACY-FORMAT',
            stage: 'doctor',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.project,
            message:
                'The workspace configuration is not the current schema-3 format: ${error.message}',
            remediation:
                'Upgrade the Zuke packages, follow docs/migration.md, and regenerate current artifacts.',
            context: {'path': configFile.path},
          ),
        ],
      );
    } on WorkspaceConfigError catch (error) {
      return WorkspacePreflightResult(
        root: canonicalRoot,
        diagnostics: [
          Diagnostic(
            code: 'ZK-CONFIG-INVALID',
            stage: 'doctor',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.project,
            message:
                'The workspace configuration could not be parsed: ${error.message}',
            remediation:
                'Correct the current schema-3 zuke.yaml and rerun doctor.',
            context: {'path': configFile.path},
          ),
        ],
      );
    } on Object catch (error) {
      return WorkspacePreflightResult(
        root: canonicalRoot,
        diagnostics: [
          Diagnostic(
            code: 'ZK-CONFIG-INVALID',
            stage: 'doctor',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.project,
            message: 'Workspace discovery failed: $error',
            remediation:
                'Correct the current schema-3 workspace inputs and rerun doctor.',
            context: {'path': configFile.path},
          ),
        ],
      );
    }
  }

  List<Diagnostic> diagnose(String root) => inspect(root).diagnostics;

  String _canonicalRoot(String root) {
    try {
      return Directory(root).absolute.resolveSymbolicLinksSync();
    } on Object {
      return Directory(root).absolute.path;
    }
  }
}

/// Backwards-compatible internal name for callers being migrated in this
/// release. It does not expose a second implementation.
typedef ConfigurationPreflight = WorkspacePreflight;

/// Loads a workspace only after the CLI preflight has accepted it. Commands
/// use this helper when they need a workspace object and cannot continue with
/// a diagnostic-only result.
WorkspaceDiscoveryResult requireCurrentWorkspace(String root) {
  final result = const WorkspacePreflight().inspect(root);
  if (!result.eligible || result.workspace == null) {
    final message = result.diagnostics
        .map((diagnostic) => '${diagnostic.code}: ${diagnostic.message}')
        .join('; ');
    throw FormatException(
      message.isEmpty ? 'Workspace preflight failed' : message,
    );
  }
  return result.workspace!;
}
