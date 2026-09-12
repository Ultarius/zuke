import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:zuke_core/zuke_core.dart';
import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke/runner.dart';
import 'extraction_service.dart';
import 'validate_command.dart';
import 'generate_command.dart';
import 'extract_command.dart';
import 'lock_command.dart';
import 'trace_command.dart';
import 'gate_command.dart';
import 'check_command.dart';
import 'scenario_selection.dart';
import 'gateway_canonicalize_command.dart';
import 'manifest_command.dart';
import 'attestation_command.dart';
import 'generator.dart';
import 'proof_engine.dart';
import 'report_command.dart';
import 'clean_command.dart';
import 'coverage_command.dart';
import 'configuration_preflight.dart';
import 'process_supervisor.dart';
import 'tool_invocation.dart';
import 'watch_coordinator.dart';
import 'test_run_summary.dart';
import 'command_result.dart';
import 'generated/release_contract.dart';
import 'source_output_catalog.dart';
import 'test_host_doctor.dart';
import 'artifact_audit.dart';
import 'alignment_doctor.dart';
import 'openapi_contract.dart';
import 'policy_command.dart';
import 'registration_audit.dart';
import 'workspace_registration_audit.dart';
import 'path_safety.dart';
import 'init_preset.dart';
import 'vscode_preset.dart';
import 'lock_refresh_roots.dart';
import 'gate_record.dart';
import 'owner_handoff.dart';

const _runnerModeNames = ['auto', 'cli', 'directSnapshot'];

ToolRunnerMode? _runnerModeFromValue(String? value) {
  if (value == null || value.isEmpty) return null;
  return switch (value) {
    'auto' => ToolRunnerMode.auto,
    'cli' => ToolRunnerMode.cli,
    'directSnapshot' => ToolRunnerMode.directSnapshot,
    _ => throw FormatException('Unknown runner mode: $value'),
  };
}

bool _isZukePackageName(String name) =>
    name == 'zuke' || name.startsWith('zuke_');

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

class ZukeCli {
  final String version;
  final ProcessSupervisor processSupervisor;
  late final ArgParser parser;

  ZukeCli({String? version, ProcessSupervisor? processSupervisor})
    : version = version ?? releasePublicPackageVersions['zuke_cli']!,
      processSupervisor = processSupervisor ?? const LocalProcessSupervisor() {
    parser = ArgParser()
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
            help:
                'Write a framework-owned JSON summary of changed profile locks',
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
              ..addOption(
                'format',
                allowed: ['text', 'json'],
                defaultsTo: 'text',
              )
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
            ..addFlag(
              'dry-run',
              help: 'Describe changes without writing files',
            ),
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
  }

  Future<int> run(List<String> args) async {
    try {
      final results = parser.parse(args);

      if (results['help'] as bool) {
        _printHelp();
        return 0;
      }

      if (results['version'] as bool) {
        print('zuke $version');
        return 0;
      }

      final command = results.command;
      if (command == null) {
        _printHelp();
        return 0;
      }

      switch (command.name) {
        case 'validate':
          return await ValidateCommand(command).execute();
        case 'generate':
          return await GenerateCommand(command).execute();
        case 'doctor':
          if (command.command?.name == 'test-host') {
            return await _runTestHostDoctor(command.command!);
          }
          return await _runDoctor(command);
        case 'clean':
          return CleanCommand(command).execute();
        case 'extract':
          if (command.command?.name == 'dart') {
            return await ExtractDartCommand(command.command!).execute();
          }
          _printHelp();
          return 1;
        case 'trace':
          return await TraceCommand(command).execute();
        case 'report':
          return await ReportCommand(command).execute();
        case 'lock':
          if (command['refresh'] as bool? ?? false) {
            return await _runLockRefresh(command);
          }
          if ((command['diff-output'] as String?) != null) {
            throw const FormatException(
              '--diff-output requires lock --refresh',
            );
          }
          if ((command['roots'] as List<String>).isNotEmpty) {
            throw const FormatException('--roots requires lock --refresh');
          }
          return await LockCommand(command).execute();
        case 'gate':
          if (command.command?.name == 'record') {
            return recordGate(command.command!);
          }
          if (command.command?.name == 'handoff') {
            return writeOwnerHandoff(command.command!);
          }
          return await GateCommand(command, testRunner: _runTests).execute();
        case 'check':
          return await CheckCommand(command, testRunner: _runTests).execute();
        case 'manifest':
          if (command.command?.name == 'create') {
            final sub = command.command!;
            final root = sub['root'] as String? ?? Directory.current.path;
            final path = await ManifestCommand.create(
              root: root,
              signerId: sub['signer-id'] as String,
              keyId: sub['key-id'] as String? ?? 'default',
              profile: sub['profile'] as String? ?? 'release',
            );
            print(path);
            return 0;
          }
          if (command.command?.name == 'verify') {
            final sub = command.command!;
            final valid = await ManifestCommand.verify(
              sub['root'] as String? ?? Directory.current.path,
              head: sub['head'] as String?,
              current: sub['current'] as bool? ?? false,
              requireHistory: sub['require-history'] as bool? ?? false,
            );
            print(valid ? 'Release chain valid.' : 'Release chain invalid.');
            return valid ? 0 : 1;
          }
          if (command.command?.name == 'export') {
            final sub = command.command!;
            await ManifestCommand.export(
              sub['root'] as String? ?? Directory.current.path,
              sub['output'] as String,
              head: sub['head'] as String?,
            );
            return 0;
          }
          _printHelp();
          return 1;
        case 'attestation':
          if (command.command?.name == 'create') {
            return await AttestationCommand(command.command!).create();
          }
          _printHelp();
          return 1;
        case 'gateway':
          if (command.command?.name == 'canonicalize-apim') {
            return GatewayCanonicalizeCommand(command.command!).execute();
          }
          _printHelp();
          return 1;
        case 'artifacts':
          if (command.command?.name == 'audit') {
            return ArtifactAuditCommand(command.command!).execute();
          }
          if (command.command?.name == 'package') {
            return ArtifactPackageCommand(command.command!).execute();
          }
          _printHelp();
          return 1;
        case 'contract':
          if (command.command?.name == 'verify') {
            return OpenApiContractCommand(command.command!).execute();
          }
          _printHelp();
          return 1;
        case 'policy':
          if (command.command?.name == 'check') {
            return PolicyCommand(command.command!).execute();
          }
          _printHelp();
          return 1;
        case 'init':
          return _runInit(command);
        case 'adopt':
          if (command.command?.name == 'package') {
            return _runAdoptPackage(command.command!);
          }
          _printHelp();
          return 1;
        case 'watch':
          return _runWatch(command);
        case 'affected':
          return _runAffected(command);
        case 'test':
          return await _runTests(command);
        case 'coverage':
          return await CoverageCommand(command).execute();
        case 'certify':
          if (command.command?.name == 'hosted') {
            return await _runHostedCertification(command.command!);
          }
          _printHelp();
          return 1;
        default:
          _printHelp();
          return 0;
      }
    } on FormatException catch (e) {
      stderr.writeln('Error: ${e.message}');
      return 2;
    } on ProcessException catch (e) {
      stderr.writeln('Tooling error: ${e.message}');
      return 3;
    } catch (e) {
      stderr.writeln('Error: $e');
      return 1;
    }
  }

  void _printHelp() {
    print('''
zuke $version - Gherkin-Driven Specification Engine

Usage:
  zuke validate     Validate specification files
  zuke generate     Generate contract code from specifications
  zuke extract dart Extract resolved Dart annotations
  zuke trace RULE-ID Show requirement trace
  zuke report       Emit compiled spec model JSON (zuke-model.json)
  zuke lock --profile <name>|--all-profiles  Write or check profile locks
  zuke lock --update                     Refresh selected locks transactionally
  zuke lock --refresh                    Run generation, tests, validation, and lock refresh
  zuke gate         Run validate, generation, and lock gates
  zuke check        Verify one or more workspaces with isolated stage output
  zuke manifest create|verify|export  Manage trusted Ed25519 history
  zuke attestation create           Create a signed external-control attestation
  zuke gateway canonicalize-apim    Canonicalize APIM gateway evidence
  zuke artifacts audit              Audit the exact upload artifact bundle
  zuke artifacts package            Build and audit an upload artifact bundle
  zuke contract verify --openapi    Compare OpenAPI paths with route topology
  zuke policy check                 Validate consumer risk acceptance
  zuke doctor       Diagnose project setup
  zuke doctor --check-alignment  Check the supported Zuke dependency tuple
  zuke doctor --check-overrides   Reject release-unsafe dependency overrides
  zuke doctor test-host  Explain Flutter/test SDK compatibility
  zuke clean        Remove Zuke test temporary directories
  zuke init         Create a starter configuration
  zuke watch        Run generation and validation once
  zuke affected     List requirements affected by a git change
  zuke test         Run configured verification suites
  zuke coverage     Evaluate LCOV as an independent quality gate
  zuke certify hosted  Certify the published tuple (framework checkout only)
  zuke --help       Show this help
  zuke --version    Show version
''');
  }

  Future<int> _runHostedCertification(ArgResults cmd) async {
    final root = cmd['root'] as String? ?? Directory.current.path;
    final platform = cmd['platform'] as String?;
    final host = cmd['host'] as String?;
    if (platform == null || host == null) {
      stderr.writeln(
        'certify hosted requires --platform <linux|windows> and '
        '--host <dart|flutter>',
      );
      return 2;
    }
    final script = File(
      '$root${Platform.pathSeparator}tool${Platform.pathSeparator}'
      'check_hosted_consumer.dart',
    );
    if (!script.existsSync()) {
      stderr.writeln(
        'Hosted certification must run from a Zuke framework checkout.',
      );
      return 2;
    }
    final arguments = <String>[
      '--suppress-analytics',
      'run',
      script.path,
      '--platform',
      platform,
      '--host',
      host,
      if (cmd['flutter-version'] case final String version) ...[
        '--flutter-version',
        version,
      ],
      if (cmd['output'] case final String output) ...['--output', output],
      if (cmd['keep-fixture'] as bool? ?? false) '--keep-fixture',
    ];
    final process = await Process.start(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: root,
      runInShell: Platform.isWindows,
    );
    await Future.wait([
      stdout.addStream(process.stdout),
      stderr.addStream(process.stderr),
    ]);
    return process.exitCode;
  }

  Future<int> _runDoctor(ArgResults cmd) async {
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
            stderr.writeln(
              '  ERROR [${diagnostic.code}]: ${diagnostic.message}',
            );
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

  Future<int> _runTestHostDoctor(ArgResults cmd) async {
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

  /// Runs the complete lock refresh pipeline in one process.
  ///
  /// Keeping orchestration here means consumers do not need a copy of the
  /// framework's generate/test/validate/lock loop.  LockCommand still owns
  /// the transactional write and final stale-lock checks; this method only
  /// supplies the fresh inputs it requires.
  Future<int> _runLockRefresh(ArgResults cmd) async {
    final additionalRoots = cmd['roots'] as List<String>;
    final roots = lockRefreshRoots([
      if (cmd['root'] case final String root) root,
      ...additionalRoots,
      if (cmd['root'] == null && additionalRoots.isEmpty)
        Directory.current.path,
    ]);
    // Resolve every root and profile before any generation or evidence writes.
    for (final root in roots) {
      final configured = requireCurrentWorkspace(root.path).config.lockProfiles;
      final requested = [
        if (cmd['profile'] case final String profile) profile,
        ...cmd['profiles'] as List<String>,
      ];
      if (requested.any((profile) => !configured.contains(profile))) {
        throw FormatException(
          'Requested profile is not configured at ${root.path}',
        );
      }
    }
    final diffOutput = cmd['diff-output'] as String?;
    if (diffOutput != null && diffOutput.isNotEmpty && roots.length != 1) {
      throw const FormatException(
        'lock --diff-output requires exactly one refreshed workspace root',
      );
    }
    if (diffOutput != null && diffOutput.isNotEmpty) {
      final outputPath = canonicalComparablePath(diffOutput);
      final lockDirectory = canonicalComparablePath(
        p.join(
          roots.single.path,
          requireCurrentWorkspace(roots.single.path).config.lockDirectory ??
              'assurance/locks',
        ),
      );
      if (pathEqualsOrWithin(lockDirectory, outputPath) ||
          FileSystemEntity.typeSync(outputPath, followLinks: false) !=
              FileSystemEntityType.notFound) {
        throw const FormatException(
          '--diff-output must be a new file outside the lock directory',
        );
      }
    }
    final before = roots.length == 1
        ? _lockSnapshot(roots.single)
        : <String, String?>{};
    var exitCode = 0;
    try {
      for (final root in roots) {
        final result = await _runLockRefreshRoot(cmd, root.path);
        if (result != 0) {
          exitCode = result;
          break;
        }
      }
      return exitCode;
    } finally {
      if (diffOutput != null && diffOutput.isNotEmpty) {
        _writeLockDiff(roots.single, before, diffOutput);
      }
    }
  }

  Map<String, String?> _lockSnapshot(Directory root) {
    final workspace = requireCurrentWorkspace(root.path);
    final directory = workspace.config.lockDirectory ?? 'assurance/locks';
    return {
      for (final profile in workspace.config.lockProfiles)
        profile:
            File(
              '${root.path}${Platform.pathSeparator}$directory${Platform.pathSeparator}$profile.lock.json',
            ).existsSync()
            ? File(
                '${root.path}${Platform.pathSeparator}$directory${Platform.pathSeparator}$profile.lock.json',
              ).readAsStringSync()
            : null,
    };
  }

  void _writeLockDiff(
    Directory root,
    Map<String, String?> before,
    String output,
  ) {
    final after = _lockSnapshot(root);
    final changed = <Map<String, Object?>>[];
    for (final profile in {...before.keys, ...after.keys}.toList()..sort()) {
      final previous = before[profile];
      final current = after[profile];
      if (previous == current) continue;
      changed.add({
        'profile': profile,
        'beforeSha256': previous == null
            ? null
            : sha256.convert(utf8.encode(previous)).toString(),
        'afterSha256': current == null
            ? null
            : sha256.convert(utf8.encode(current)).toString(),
        'beforePresent': previous != null,
        'afterPresent': current != null,
      });
    }
    final file = File(output);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'kind': 'zuke.lock-diff', 'root': root.path, 'changed': changed})}\n',
    );
  }

  Future<int> _runLockRefreshRoot(ArgResults cmd, String root) async {
    if (cmd['check'] as bool? ?? false) {
      throw const FormatException(
        'lock --refresh and lock --check are mutually exclusive',
      );
    }
    final output = cmd['output'] as String?;
    if (output != null && output.isNotEmpty) {
      throw const FormatException(
        'lock --refresh cannot be combined with --output',
      );
    }
    final requestedProfile = cmd['profile'] as String?;
    final requestedProfiles = cmd['profiles'] as List<String>;
    final allProfiles = cmd['all-profiles'] as bool? ?? false;
    if ((allProfiles &&
            (requestedProfile != null || requestedProfiles.isNotEmpty)) ||
        (requestedProfile != null && requestedProfiles.isNotEmpty)) {
      throw const FormatException(
        'lock --all-profiles and --profile are mutually exclusive',
      );
    }
    final workspace = requireCurrentWorkspace(root);
    final configuredProfiles = workspace.config.lockProfiles;
    final profiles = requestedProfiles.isNotEmpty
        ? requestedProfiles.toSet().toList()
        : requestedProfile == null
        ? (configuredProfiles.isEmpty
              ? const ['pullRequest', 'merge', 'release', 'nightly']
              : configuredProfiles)
        : [requestedProfile];

    final generateParser = ArgParser()
      ..addOption('root')
      ..addFlag('check')
      ..addOption('output')
      ..addFlag('quiet');
    final generated = await GenerateCommand(
      generateParser.parse(['--root', root]),
    ).execute();
    if (generated != 0) return generated;
    final generationCheck = await GenerateCommand(
      generateParser.parse(['--root', root, '--check', '--quiet']),
    ).execute();
    if (generationCheck != 0) return generationCheck;

    final testParser = ArgParser()
      ..addOption('root')
      ..addOption('profile')
      ..addOption('format')
      ..addOption('runner-mode')
      ..addFlag('quiet');
    final validateParser = ArgParser()
      ..addOption('root')
      ..addOption('profile')
      ..addOption('format')
      ..addFlag('quiet');
    for (final profile in profiles) {
      stdout.writeln('Refreshing Zuke evidence for profile $profile...');
      final testArgs = <String>[
        '--root',
        root,
        '--profile',
        profile,
        '--format',
        'text',
        if (cmd['runner-mode'] case final String runnerMode) ...[
          '--runner-mode',
          runnerMode,
        ],
      ];
      final tested = await _runTests(testParser.parse(testArgs));
      if (tested != 0) return tested;
      final validated = await ValidateCommand(
        validateParser.parse([
          '--root',
          root,
          '--profile',
          profile,
          '--format',
          'text',
        ]),
      ).execute();
      if (validated != 0) return validated;
    }

    final lockParser = ArgParser()
      ..addOption('root')
      ..addOption('profile')
      ..addMultiOption('profiles')
      ..addFlag('all-profiles')
      ..addFlag('update')
      ..addFlag('check')
      ..addFlag('quiet');
    final lockArgs = <String>['--root', root, '--update'];
    if (requestedProfiles.isNotEmpty) {
      for (final profile in profiles) {
        lockArgs.addAll(['--profiles', profile]);
      }
    } else if (requestedProfile != null) {
      lockArgs.addAll(['--profile', requestedProfile]);
    } else {
      lockArgs.add('--all-profiles');
    }
    return LockCommand(lockParser.parse(lockArgs)).execute();
  }

  int _runInit(ArgResults cmd) {
    final root = cmd['root'] as String? ?? Directory.current.path;
    final enableHooks = cmd['enable-dart-build-hooks'] as bool? ?? false;
    final dryRun = cmd['dry-run'] as bool? ?? false;
    final packagePath = cmd['package'] as String?;
    if (enableHooks && (packagePath == null || packagePath.isEmpty)) {
      stderr.writeln(
        '--enable-dart-build-hooks requires --package <workspace-relative-path>',
      );
      return 2;
    }
    final file = File('$root/zuke.yaml');
    final editorRequested = cmd['editor'] == 'vscode';
    final existingConfig = file.existsSync();
    if (existingConfig && !editorRequested) {
      stderr.writeln('zuke.yaml already exists');
      return 1;
    }
    final editorUpdates = editorRequested
        ? prepareVscodePreset(root)
        : const <EditorFileUpdate>[];
    if (enableHooks) {
      final adoption = _adoptBuildHook(root, packagePath!, dryRun: true);
      if (adoption != 0) return adoption;
    }
    final preset = switch (cmd['preset']) {
      'flutter' => InitPreset.flutter,
      'dart-frog' => InitPreset.dartFrog,
      'dart' => InitPreset.dart,
      _ => InitPreset.detect(Directory(root)),
    };
    final config = preset.configuration(Directory(root));
    if (dryRun) {
      if (!existingConfig) {
        print('Would create ${file.path}');
        print(config);
      }
      for (final update in editorUpdates) {
        print('Would update ${update.file.path}');
        print(update.contents);
      }
      return 0;
    }
    if (!existingConfig) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(config);
      Directory('$root/specs/features').createSync(recursive: true);
      print('Created ${file.path}');
    }
    for (final update in editorUpdates) {
      update.write();
      print('Updated ${update.file.path}');
    }
    if (enableHooks) {
      return _adoptBuildHook(root, packagePath!);
    }
    return 0;
  }

  int _runAdoptPackage(ArgResults cmd) {
    if (!(cmd['enable-build-hook'] as bool? ?? false)) {
      stderr.writeln('Only --enable-build-hook is currently supported.');
      return 2;
    }
    if (cmd.rest.length != 1) {
      stderr.writeln(
        'Usage: zuke adopt package <workspace-relative-path> --enable-build-hook',
      );
      return 2;
    }
    final root = cmd['root'] as String? ?? Directory.current.path;
    return _adoptBuildHook(
      root,
      cmd.rest.single,
      dryRun: cmd['dry-run'] as bool? ?? false,
    );
  }

  int _adoptBuildHook(
    String rootPath,
    String relativePackagePath, {
    bool dryRun = false,
  }) {
    if (relativePackagePath.isEmpty ||
        File(relativePackagePath).isAbsolute ||
        relativePackagePath.replaceAll('\\', '/').split('/').contains('..')) {
      stderr.writeln('Package path must be workspace-relative and confined.');
      return 2;
    }
    final root = Directory(rootPath).absolute;
    final package = Directory(
      root.uri
          .resolve('${relativePackagePath.replaceAll('\\', '/')}/')
          .toFilePath(),
    ).absolute;
    final normalizedRoot = root.path.replaceAll('\\', '/');
    final normalizedPackage = package.path.replaceAll('\\', '/');
    final packageIsWorkspaceRoot =
        normalizedPackage == normalizedRoot ||
        normalizedPackage == '$normalizedRoot/';
    if (!packageIsWorkspaceRoot &&
        !normalizedPackage.startsWith('$normalizedRoot/')) {
      stderr.writeln('Package path escapes the workspace.');
      return 2;
    }
    final pubspec = File(
      '${package.path}${Platform.pathSeparator}pubspec.yaml',
    );
    if (!pubspec.existsSync()) {
      stderr.writeln('No pubspec.yaml found at ${package.path}');
      return 2;
    }

    final hook = File(
      '${package.path}${Platform.pathSeparator}hook${Platform.pathSeparator}build.dart',
    );
    const shim =
        '''import 'package:zuke_dart_build_hook/zuke_dart_build_hook.dart'
    as zuke;

Future<void> main(List<String> arguments) => zuke.build(arguments);
''';
    if (hook.existsSync() && hook.readAsStringSync() != shim) {
      stderr.writeln('Refusing to replace existing hook at ${hook.path}');
      return 1;
    }

    var pubspecText = pubspec.readAsStringSync();
    try {
      final parsed = loadYaml(pubspecText);
      if (parsed is! YamlMap) {
        stderr.writeln('pubspec.yaml must contain a YAML mapping.');
        return 1;
      }
      final editor = YamlEditor(pubspecText);
      final dependencies = parsed['dependencies'];
      if (dependencies != null && dependencies is! YamlMap) {
        stderr.writeln(
          'Refusing to modify non-mapping dependencies: in ${pubspec.path}',
        );
        return 1;
      }
      if (dependencies is! YamlMap ||
          dependencies['zuke_dart_build_hook'] == null) {
        final hookPackage = Directory(
          '${root.path}${Platform.pathSeparator}vendor-sdk${Platform.pathSeparator}zuke_dart_build_hook',
        );
        if (!hookPackage.existsSync()) {
          stderr.writeln(
            'Zuke build-hook package is missing from this workspace.',
          );
          return 1;
        }
        final dependency = {
          'path': _relativePath(package.path, hookPackage.path),
        };
        if (dependencies == null) {
          editor.update(['dependencies'], {'zuke_dart_build_hook': dependency});
        } else {
          editor.update(['dependencies', 'zuke_dart_build_hook'], dependency);
        }
      }
      final hooks = parsed['hooks'];
      if (hooks != null && hooks is! YamlMap) {
        stderr.writeln(
          'Refusing to modify non-mapping hooks: in ${pubspec.path}',
        );
        return 1;
      }
      if (_isFlowMap(hooks)) {
        stderr.writeln(
          'Refusing to modify flow-style hooks: in ${pubspec.path}',
        );
        return 1;
      }
      final userDefines = hooks is YamlMap ? hooks['user_defines'] : null;
      if (userDefines != null && userDefines is! YamlMap) {
        stderr.writeln(
          'Refusing to modify non-mapping hooks.user_defines: in ${pubspec.path}',
        );
        return 1;
      }
      if (_isFlowMap(userDefines)) {
        stderr.writeln(
          'Refusing to modify flow-style hooks.user_defines: in ${pubspec.path}',
        );
        return 1;
      }
      final hookDefines = userDefines is YamlMap
          ? userDefines['zuke_dart_build_hook']
          : null;
      if (hookDefines != null && hookDefines is! YamlMap) {
        stderr.writeln(
          'Refusing to modify non-mapping hooks.user_defines.zuke_dart_build_hook in ${pubspec.path}',
        );
        return 1;
      }
      if (_isFlowMap(hookDefines)) {
        stderr.writeln(
          'Refusing to modify flow-style Zuke hook user-defines in ${pubspec.path}',
        );
        return 1;
      }

      if (hookDefines == null) {
        if (hooks == null) {
          editor.update(
            ['hooks'],
            {
              'user_defines': {
                'zuke_dart_build_hook': {'mode': 'warn'},
              },
            },
          );
        } else if (userDefines == null) {
          editor.update(
            ['hooks', 'user_defines'],
            {
              'zuke_dart_build_hook': {'mode': 'warn'},
            },
          );
        } else {
          editor.update(
            ['hooks', 'user_defines', 'zuke_dart_build_hook'],
            {'mode': 'warn'},
          );
        }
      } else if (hookDefines['mode'] == null) {
        editor.update([
          'hooks',
          'user_defines',
          'zuke_dart_build_hook',
          'mode',
        ], 'warn');
      }
      pubspecText = editor.toString();
    } on YamlException catch (error) {
      stderr.writeln('Unable to parse ${pubspec.path}: $error');
      return 1;
    }

    if (dryRun) {
      if (!hook.existsSync()) print('Would create ${hook.path}');
      if (pubspecText != pubspec.readAsStringSync()) {
        print('Would update ${pubspec.path}');
      }
      return 0;
    }
    hook.parent.createSync(recursive: true);
    if (!hook.existsSync()) hook.writeAsStringSync(shim);
    pubspec.writeAsStringSync(pubspecText);
    print(
      'Enabled Zuke build hook for ${relativePackagePath.replaceAll('\\', '/')}',
    );
    return 0;
  }

  bool _isFlowMap(Object? value) =>
      value is YamlMap && value.span.text.trimLeft().startsWith('{');

  String _relativePath(String fromPath, String toPath) {
    final from = Directory(
      fromPath,
    ).absolute.path.replaceAll('\\', '/').split('/');
    final to = Directory(toPath).absolute.path.replaceAll('\\', '/').split('/');
    var shared = 0;
    while (shared < from.length &&
        shared < to.length &&
        from[shared].toLowerCase() == to[shared].toLowerCase()) {
      shared++;
    }
    return [
      ...List.filled(from.length - shared, '..'),
      ...to.skip(shared),
    ].join('/');
  }

  Future<int> _runWatch(ArgResults cmd) async {
    final root = cmd['root'] as String? ?? Directory.current.path;
    final generate = cmd['generate'] as bool? ?? true;
    final validate = cmd['validate'] as bool? ?? true;
    var exitCode = 0;
    Future<void> runOnce() async {
      if (generate) {
        final generateArgs =
            (ArgParser()
                  ..addOption('root')
                  ..addFlag('check')
                  ..addOption('output')
                  ..addFlag('quiet'))
                .parse(['--root', root]);
        exitCode = await GenerateCommand(generateArgs).execute();
      }
      if (exitCode == 0 && validate) {
        final validateArgs =
            (ArgParser()
                  ..addOption('root')
                  ..addOption('format'))
                .parse(['--root', root, '--format', 'text']);
        exitCode = await ValidateCommand(validateArgs).execute();
      }
    }

    final coordinator = WatchCoordinator(
      changes: Directory(root).watch(recursive: true),
      shutdown: ProcessSignal.sigint.watch(),
      runOnce: () async {
        await runOnce();
        return exitCode;
      },
    );
    return coordinator.run();
  }

  Future<int> _runAffected(ArgResults cmd) async {
    final root = cmd['root'] as String? ?? Directory.current.path;
    final workspace = requireCurrentWorkspace(root);
    final ref = cmd['changed-since'] as String?;
    if (ref != null && ref.isNotEmpty) {
      final changed = Process.runSync('git', [
        'diff',
        '--name-only',
        '$ref...HEAD',
      ], workingDirectory: root);
      if (changed.exitCode != 0) {
        // An unknown impact map is unsafe to narrow; select everything.
        stderr.writeln(
          'Unable to compute Git impact; selecting the full suite.',
        );
      } else {
        final paths = changed.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            .where((path) => path.isNotEmpty)
            .map((path) => path.replaceAll('\\', '/'))
            .toSet();
        final normalizedRoot = root
            .replaceAll('\\', '/')
            .replaceFirst(RegExp(r'/$'), '');
        final affectedRules = <String>{};

        for (final feature in workspace.data.features) {
          final file = feature.metadata.source.file.replaceAll('\\', '/');
          final relative = file.startsWith('$normalizedRoot/')
              ? file.substring(normalizedRoot.length + 1)
              : file;
          if (paths.contains(relative)) {
            for (final rule in feature.rules) {
              if (rule.metadata.id != null) {
                affectedRules.add(rule.metadata.id!);
              }
            }
          }
        }

        final extraction = await ExtractionService().extract(workspace);
        for (final output in extraction.outputs) {
          for (final symbol in output.symbols) {
            final uri = symbol.source.uri.replaceAll('\\', '/');
            final relative = uri.startsWith('$normalizedRoot/')
                ? uri.substring(normalizedRoot.length + 1)
                : uri;
            if (paths.contains(relative)) {
              affectedRules.addAll(symbol.requirementIds);
            }
          }
        }

        for (final ruleId in affectedRules) {
          print(ruleId);
        }
        return 0;
      }
    }
    for (final feature in workspace.data.features) {
      for (final rule in feature.rules) {
        if (rule.metadata.id != null) print(rule.metadata.id);
      }
    }
    return 0;
  }

  Future<int> _runTests(ArgResults cmd) async {
    final root = cmd['root'] as String? ?? Directory.current.path;
    final workspace = requireCurrentWorkspace(root);
    final profile = cmd['profile'] as String? ?? 'pullRequest';
    final jsonMode = (cmd['format'] as String? ?? 'text') == 'json';
    final quiet =
        cmd.options.contains('quiet') && (cmd['quiet'] as bool? ?? false);
    final cliRunnerMode = _runnerModeFromValue(
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
      '${workspace.config.root}${Platform.pathSeparator}generated${Platform.pathSeparator}evidence${Platform.pathSeparator}.results-${pid}-${DateTime.now().microsecondsSinceEpoch}',
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
        for (final runner in configuredRunners.whereType<Map>()) {
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
          final configuredRunnerMode = _runnerModeFromValue(
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
        final configuredRunnerMode = _runnerModeFromValue(
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
      '${directory.path}.publish-${pid}-${DateTime.now().microsecondsSinceEpoch}',
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
        const JsonEncoder.withIndent('  ').convert(observation) + '\n',
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
    Map runner, {
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
    final mappingDigest = WorkspaceDigest.computeFiltered(
      workspace.config.root!,
      (path) =>
          path.startsWith('specs/registry/') ||
          path.startsWith('policies/') ||
          path.endsWith('zuke.yaml'),
    );
    final specificationIndexDigest = WorkspaceDigest.computeFiltered(
      workspace.config.root!,
      (path) => path.startsWith('specs/'),
    );
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
