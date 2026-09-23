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
              'Generate contracts, execute managed tests, validate, and refresh locks',
        )
        ..addOption('runner-mode', allowed: _runnerModeNames)
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
        ..addOption('runner-mode', allowed: _runnerModeNames),
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
        ..addOption('runner-mode', allowed: _runnerModeNames),
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
