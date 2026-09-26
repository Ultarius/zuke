import 'package:args/args.dart';

import 'tool_invocation.dart';

const _runnerModeNames = ['auto', 'cli', 'directSnapshot'];

ToolRunnerMode? runnerModeFromValue(String? value) {
  if (value == null || value.isEmpty) return null;
  return switch (value) {
    'auto' => ToolRunnerMode.auto,
    'cli' => ToolRunnerMode.cli,
    'directSnapshot' => ToolRunnerMode.directSnapshot,
    _ => throw FormatException('Unknown runner mode: $value'),
  };
}

/// Reads a boolean flag that the composing parser may not declare.
///
/// `check` and `lock --refresh` build reduced parsers, and `ArgResults.[]`
/// throws for an option its parser never registered. The membership test is
/// therefore load-bearing, not a redundant null guard.
bool boolFlag(ArgResults args, String name) =>
    args.options.contains(name) && (args[name] as bool? ?? false);

/// Builds the `validate` argv accepted by [ValidateCommand].
///
/// Shared by `check` and the `lock --refresh` skip probe so a new flag cannot
/// be added to one composer and forgotten in the other.
ArgResults buildValidateArgs({
  required String root,
  String profile = 'pullRequest',
  String format = 'text',
  bool requireEvidence = false,
  bool quiet = false,
  bool silent = false,
}) =>
    (ArgParser()
          ..addOption('root', abbr: 'r')
          ..addOption('profile')
          ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
          ..addFlag('require-evidence')
          ..addFlag('silent')
          ..addFlag('quiet'))
        .parse([
          '--root',
          root,
          '--profile',
          profile,
          '--format',
          format,
          if (requireEvidence) '--require-evidence',
          if (silent) '--silent',
          if (quiet) '--quiet',
        ]);

/// Builds the `test` argv accepted by [TestCommandRunner].
ArgResults buildTestArgs({
  required String root,
  String profile = 'pullRequest',
  String format = 'text',
  String? runnerMode,
  bool coverage = false,
  bool quiet = false,
}) =>
    (ArgParser()
          ..addOption('root', abbr: 'r')
          ..addOption('profile')
          ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
          ..addOption('runner-mode', allowed: _runnerModeNames)
          ..addFlag('coverage')
          ..addFlag('quiet'))
        .parse([
          '--root',
          root,
          '--profile',
          profile,
          '--format',
          format,
          if (runnerMode != null) ...['--runner-mode', runnerMode],
          if (coverage) '--coverage',
          if (quiet) '--quiet',
        ]);

/// Builds the `generate` argv accepted by [GenerateCommand].
ArgResults buildGenerateArgs({
  required String root,
  bool check = false,
  bool quiet = false,
}) =>
    (ArgParser()
          ..addOption('root', abbr: 'r')
          ..addFlag('check')
          ..addOption('output', abbr: 'o')
          ..addFlag('quiet'))
        .parse(['--root', root, if (check) '--check', if (quiet) '--quiet']);

/// Builds the `lock` argv accepted by [LockCommand].
ArgResults buildLockArgs({
  required String root,
  String? profile,
  List<String> profiles = const [],
  bool allProfiles = false,
  bool update = false,
  bool check = false,
  bool quiet = false,
}) =>
    (ArgParser()
          ..addOption('root', abbr: 'r')
          ..addMultiOption('roots')
          ..addMultiOption('profiles')
          ..addOption('profile')
          ..addFlag('check')
          ..addFlag('all-profiles')
          ..addFlag('update')
          ..addFlag('refresh')
          ..addOption('runner-mode', allowed: _runnerModeNames)
          ..addFlag('retest')
          ..addOption('diff-output')
          ..addOption('output')
          ..addFlag('quiet'))
        .parse([
          '--root',
          root,
          if (profile != null) ...['--profile', profile],
          for (final selected in profiles) ...['--profiles', selected],
          if (allProfiles) '--all-profiles',
          if (update) '--update',
          if (check) '--check',
          if (quiet) '--quiet',
        ]);

/// Builds the `report` argv accepted by [ReportCommand].
ArgResults buildReportArgs({required String root, bool quiet = false}) =>
    (ArgParser()
          ..addOption('root', abbr: 'r')
          ..addOption('output')
          ..addFlag('quiet'))
        .parse(['--root', root, if (quiet) '--quiet']);

ArgParser buildZukeArgParser() {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', help: 'Show help')
    ..addFlag('version', abbr: 'v', help: 'Show version')
    ..addCommand(
      'validate',
      ArgParser()
        ..addOption('root', abbr: 'r', help: 'Workspace root directory')
        ..addOption('profile')
        ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
        ..addFlag(
          'require-evidence',
          help: 'Fail when the profile has no executed evidence',
        )
        ..addFlag(
          'silent',
          hide: true,
          help: 'Suppress findings as well as progress output',
        )
        ..addFlag('quiet', hide: true),
    )
    ..addCommand(
      'generate',
      ArgParser()
        ..addOption('root', abbr: 'r', help: 'Workspace root directory')
        ..addFlag('check', help: 'Check without modifying')
        ..addOption('output', abbr: 'o', help: 'Output directory')
        ..addFlag('quiet', hide: true),
    )
    ..addCommand(
      'extract',
      ArgParser()..addCommand(
        'dart',
        ArgParser()
          ..addOption('root', abbr: 'r')
          ..addOption('package', help: 'Package path relative to workspace')
          ..addOption('target', help: 'Active configured extraction target')
          ..addOption('emit', help: 'Optional diagnostic fragment path'),
      ),
    )
    ..addCommand('trace', ArgParser()..addOption('root', abbr: 'r'))
    ..addCommand(
      'lock',
      ArgParser()
        ..addOption('root', abbr: 'r')
        ..addMultiOption(
          'roots',
          help: 'Additional roots or pub workspaces for --refresh',
        )
        ..addMultiOption('profiles', help: 'Selected profiles for --refresh')
        ..addOption('profile')
        ..addFlag('check')
        ..addFlag('all-profiles')
        ..addFlag('update', help: 'Refresh selected locks transactionally')
        ..addFlag(
          'refresh',
          help:
              'Generate contracts, reuse current evidence or execute managed '
              'tests, validate, and refresh locks',
        )
        ..addOption('runner-mode', allowed: _runnerModeNames)
        ..addFlag(
          'retest',
          help: 'Execute managed tests even when evidence is already current',
        )
        ..addOption(
          'diff-output',
          help: 'Write a framework-owned JSON summary of changed profile locks',
        )
        ..addOption('output', hide: true)
        // Reserved for composed commands which must keep stdout structured.
        ..addFlag('quiet', hide: true),
    )
    ..addCommand(
      'gate',
      ArgParser()
        ..addOption('root', abbr: 'r')
        ..addOption('profile')
        ..addFlag('all-profiles')
        ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
        ..addOption('summary-file')
        ..addOption('artifact-dir')
        ..addFlag(
          'audit-artifacts',
          help: 'Audit the final safe artifact bundle before returning',
        )
        ..addOption('blocker-file')
        ..addOption('handoff-file')
        ..addOption('runner-mode', allowed: _runnerModeNames)
        ..addCommand(
          'record',
          ArgParser()
            ..addOption('summary-file', mandatory: true)
            ..addOption('blocker-file')
            ..addOption('output')
            ..addOption('release-id')
            ..addOption('commit-sha'),
        )
        ..addCommand(
          'handoff',
          ArgParser()
            ..addOption('summary-file')
            ..addOption('blocker-file')
            ..addOption('output')
            ..addOption('release-id')
            ..addOption('commit-sha')
            ..addOption('coverage'),
        ),
    )
    ..addCommand(
      'check',
      ArgParser()
        ..addMultiOption('root', abbr: 'r', help: 'Workspace root directory')
        ..addOption('profile', defaultsTo: 'pullRequest')
        ..addOption('jobs', defaultsTo: '1')
        ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
        ..addOption('summary-file')
        ..addOption('runner-mode', allowed: _runnerModeNames)
        ..addFlag(
          'coverage',
          help:
              'Collect coverage from test runners (Flutter: --coverage, '
              'Dart: --coverage=coverage)',
        ),
    )
    ..addCommand(
      'manifest',
      ArgParser()
        ..addCommand(
          'create',
          ArgParser()
            ..addOption('root')
            ..addOption('signer-id', mandatory: true)
            ..addOption('key-id')
            ..addOption('profile', defaultsTo: 'release'),
        )
        ..addCommand(
          'verify',
          ArgParser()
            ..addOption('root')
            ..addOption('head')
            ..addFlag('current', help: 'Require current release inputs')
            ..addFlag(
              'require-history',
              help: 'Reject an empty release history',
            ),
        )
        ..addCommand(
          'export',
          ArgParser()
            ..addOption('root')
            ..addOption('head')
            ..addOption('output', mandatory: true),
        ),
    )
    ..addCommand(
      'attestation',
      ArgParser()..addCommand(
        'create',
        ArgParser()
          ..addOption('root')
          ..addOption('provider-id', mandatory: true)
          ..addOption('evidence', mandatory: true)
          ..addOption('reference', mandatory: true)
          ..addOption('signer-id', mandatory: true)
          ..addOption('key-id')
          ..addOption('issued-at', mandatory: true)
          ..addOption('expires-at', mandatory: true),
      ),
    )
    ..addCommand(
      'gateway',
      ArgParser()..addCommand(
        'canonicalize-apim',
        ArgParser()
          ..addOption('input', mandatory: true)
          ..addOption('output', mandatory: true)
          ..addOption('route', mandatory: true)
          ..addOption('reference', mandatory: true),
      ),
    )
    ..addCommand(
      'contract',
      ArgParser()..addCommand(
        'verify',
        ArgParser()
          ..addOption('root', abbr: 'r')
          ..addFlag('openapi')
          ..addOption('input')
          ..addOption('target')
          ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
          ..addOption('summary-file'),
      ),
    )
    ..addCommand(
      'artifacts',
      ArgParser()
        ..addCommand(
          'audit',
          ArgParser()
            ..addOption('input', mandatory: true)
            ..addOption('output')
            ..addOption('summary-file')
            ..addOption(
              'format',
              allowed: ['text', 'json'],
              defaultsTo: 'text',
            ),
        )
        ..addCommand(
          'package',
          ArgParser()
            ..addOption('output', mandatory: true)
            ..addMultiOption('include')
            ..addOption('output-file')
            ..addOption('summary-file')
            ..addOption(
              'format',
              allowed: ['text', 'json'],
              defaultsTo: 'text',
            ),
        ),
    )
    ..addCommand(
      'doctor',
      ArgParser()
        ..addOption('root', abbr: 'r', help: 'Workspace root directory')
        ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
        ..addOption('summary-file')
        ..addFlag('check-alignment')
        ..addFlag('check-overrides')
        ..addCommand(
          'test-host',
          ArgParser()
            ..addOption('root', abbr: 'r', help: 'Workspace root directory')
            ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
            ..addOption('summary-file'),
        ),
    )
    ..addCommand(
      'policy',
      ArgParser()..addCommand(
        'check',
        ArgParser()
          ..addOption('root', abbr: 'r')
          ..addOption('input')
          ..addOption('policy')
          ..addOption('commit')
          ..addOption('release')
          ..addOption('now')
          ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
          ..addOption('summary-file'),
      ),
    )
    ..addCommand(
      'clean',
      ArgParser()
        ..addOption('root', abbr: 'r', help: 'Directory to clean')
        ..addFlag(
          'dry-run',
          help: 'List test temporary directories without removing them',
        ),
    )
    ..addCommand(
      'init',
      ArgParser()
        ..addOption('root', abbr: 'r')
        ..addOption(
          'preset',
          allowed: ['auto', 'dart', 'flutter', 'dart-frog'],
          defaultsTo: 'auto',
        )
        ..addOption(
          'editor',
          allowed: ['vscode'],
          help: 'Merge Zuke editor commands, preserving existing entries',
        )
        ..addFlag('enable-dart-build-hooks')
        ..addFlag('dry-run', help: 'Describe changes without writing files')
        ..addOption(
          'package',
          help: 'Workspace-relative package to enroll when enabling hooks',
        ),
    )
    ..addCommand(
      'adopt',
      ArgParser()..addCommand(
        'package',
        ArgParser()
          ..addOption('root', abbr: 'r')
          ..addFlag('enable-build-hook')
          ..addFlag('dry-run', help: 'Describe changes without writing files'),
      ),
    )
    ..addCommand(
      'watch',
      ArgParser()
        ..addOption('root', abbr: 'r')
        ..addFlag('generate', defaultsTo: true)
        ..addFlag('validate', defaultsTo: true),
    )
    ..addCommand(
      'affected',
      ArgParser()
        ..addOption('root', abbr: 'r')
        ..addOption('changed-since'),
    )
    ..addCommand(
      'report',
      ArgParser()
        ..addOption('root', abbr: 'r', help: 'Workspace root directory')
        ..addOption('output', help: 'Output file path')
        ..addFlag('quiet', hide: true),
    )
    ..addCommand(
      'test',
      ArgParser()
        ..addOption('root', abbr: 'r')
        ..addOption('profile')
        ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
        ..addOption('runner-mode', allowed: _runnerModeNames)
        ..addFlag(
          'coverage',
          help:
              'Collect coverage from test runners (Flutter: --coverage, '
              'Dart: --coverage=coverage)',
        )
        ..addFlag('quiet', hide: true),
    );
  parser.addCommand(
    'coverage',
    ArgParser()
      ..addOption('root', abbr: 'r')
      ..addOption('input')
      ..addOption('changed-since')
      ..addOption('minimum')
      ..addOption('changed-line-minimum')
      ..addOption('baseline')
      ..addFlag(
        'write-baseline',
        help: 'Write the configured coverage baseline from this LCOV run',
      )
      ..addOption('output')
      ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text'),
  );
  parser.addCommand(
    'certify',
    ArgParser()..addCommand(
      'hosted',
      ArgParser()
        ..addOption('root', abbr: 'r')
        ..addOption('platform', allowed: ['linux', 'windows'])
        ..addOption('host', allowed: ['dart', 'flutter'])
        ..addOption('flutter-version')
        ..addOption('output')
        ..addFlag('keep-fixture'),
    ),
  );
  return parser;
}
