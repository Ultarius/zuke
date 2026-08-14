import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
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
          ..addOption('profile', defaultsTo: 'pullRequest')
          ..addFlag('check')
          ..addFlag('all-profiles')
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
          ..addOption('runner-mode', allowed: _runnerModeNames),
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
        'doctor',
        ArgParser()
          ..addOption('root', abbr: 'r', help: 'Workspace root directory')
          ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
          ..addOption('summary-file'),
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
        ..addOption('output')
        ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text'),
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
          return await LockCommand(command).execute();
        case 'gate':
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
  zuke gate         Run validate, generation, and lock gates
  zuke check        Verify one or more workspaces with isolated stage output
  zuke manifest create|verify|export  Manage trusted Ed25519 history
  zuke attestation create           Create a signed external-control attestation
  zuke gateway canonicalize-apim    Canonicalize APIM gateway evidence
  zuke doctor       Diagnose project setup
  zuke clean        Remove Zuke test temporary directories
  zuke init         Create a starter configuration
  zuke watch        Run generation and validation once
  zuke affected     List requirements affected by a git change
  zuke test         Run configured verification suites
  zuke coverage     Evaluate LCOV as an independent quality gate
  zuke --help       Show this help
  zuke --version    Show version
''');
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
    };
    int finish(int code) {
      final result = CommandResult(
        command: 'doctor',
        stage: 'doctor',
        exitCode: code,
        status: code == 0 ? CommandStatus.passed : CommandStatus.failed,
        eligible: code == 0,
        diagnostics: diagnostics,
        details: {'release': releaseDetails},
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
    if (file.existsSync()) {
      stderr.writeln('zuke.yaml already exists');
      return 1;
    }
    if (enableHooks) {
      final adoption = _adoptBuildHook(root, packagePath!, dryRun: true);
      if (adoption != 0) return adoption;
    }
    final config =
        '''schemaVersion: 3\nworkspace:\n  name: ${Directory(root).uri.pathSegments.where((s) => s.isNotEmpty).last}\n  root: .\nspecifications:\n  features: [specs/features/**/*.feature]\ntargets: {}\ntrust:\n  bundle: assurance-history/trust/ed25519.json\n  algorithm: ed25519\n''';
    if (dryRun) {
      print('Would create ${file.path}');
      return 0;
    }
    file.writeAsStringSync(config);
    print('Created ${file.path}');
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
    try {
      if (configuredRunners is List) {
        for (final runner in configuredRunners.whereType<Map>()) {
          final profiles = runner['profiles'];
          if (profiles is List &&
              !profiles.whereType<String>().contains(profile)) {
            continue;
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
          final runnerKind = runner['kind'] as String? ?? 'test';
          if (runnerKind != 'setup' &&
              runnerKind != 'test' &&
              runnerKind != 'gherkin') {
            return 2;
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
            runner['runnerMode']?.toString(),
          );
          final runnerMode = isFlutterTool(configuredExecutable)
              ? (cliRunnerMode ?? configuredRunnerMode ?? ToolRunnerMode.auto)
              : (configuredRunnerMode ?? ToolRunnerMode.auto);
          final workingDirectory = runner['workingDirectory'] is String
              ? Directory(
                  '${workspace.config.root}/${runner['workingDirectory']}',
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
                  seconds: (runner['timeoutSeconds'] as num?)?.toInt() ?? 600,
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
      final hasRequiredEvidence = workspace.data.features.any(
        (feature) => feature.rules.any(
          (rule) =>
              rule.metadata.requiredEvidence != null &&
              rule.metadata.requiredEvidence!.isNotEmpty,
        ),
      );
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
