import 'dart:io';

import 'package:args/args.dart';

import 'artifact_audit.dart';
import 'attestation_command.dart';
import 'check_command.dart';
import 'clean_command.dart';
import 'cli_help.dart';
import 'cli_parser.dart';
import 'configuration_preflight.dart';
import 'coverage_command.dart';
import 'doctor_command.dart';
import 'extraction_service.dart';
import 'extract_command.dart';
import 'gate_command.dart';
import 'gate_record.dart';
import 'gateway_canonicalize_command.dart';
import 'generate_command.dart';
import 'hosted_certify_command.dart';
import 'init_command.dart';
import 'lock_command.dart';
import 'lock_refresh_command.dart';
import 'manifest_command.dart';
import 'openapi_contract.dart';
import 'owner_handoff.dart';
import 'policy_command.dart';
import 'process_supervisor.dart';
import 'report_command.dart';
import 'test_command.dart';
import 'trace_command.dart';
import 'validate_command.dart';
import 'watch_coordinator.dart';
import 'generated/release_contract.dart';

class ZukeCli {
  final String version;
  final ProcessSupervisor processSupervisor;
  late final ArgParser parser;
  late final TestCommandRunner _testCommandRunner;

  ZukeCli({String? version, ProcessSupervisor? processSupervisor})
    : version = version ?? releasePublicPackageVersions['zuke_cli']!,
      processSupervisor = processSupervisor ?? const LocalProcessSupervisor() {
    parser = buildZukeArgParser();
    _testCommandRunner = TestCommandRunner(
      processSupervisor: this.processSupervisor,
    );
  }

  Future<int> run(List<String> args) async {
    try {
      final results = parser.parse(args);

      if (results['help'] as bool) {
        printZukeHelp(version: version);
        return 0;
      }

      if (results['version'] as bool) {
        print('zuke $version');
        return 0;
      }

      final command = results.command;
      if (command == null) {
        printZukeHelp(version: version);
        return 0;
      }

      switch (command.name) {
        case 'validate':
          return await ValidateCommand(command).execute();
        case 'generate':
          return await GenerateCommand(command).execute();
        case 'doctor':
          if (command.command?.name == 'test-host') {
            return await runTestHostDoctor(command.command!);
          }
          return await runDoctor(command);
        case 'clean':
          return CleanCommand(command).execute();
        case 'extract':
          if (command.command?.name == 'dart') {
            return await ExtractDartCommand(command.command!).execute();
          }
          printZukeHelp(version: version);
          return 1;
        case 'trace':
          return await TraceCommand(command).execute();
        case 'report':
          return await ReportCommand(command).execute();
        case 'lock':
          if (command['refresh'] as bool? ?? false) {
            return await runLockRefresh(
              command,
              testRunner: _testCommandRunner.runTests,
            );
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
          return await GateCommand(
            command,
            testRunner: _testCommandRunner.runTests,
          ).execute();
        case 'check':
          return await CheckCommand(
            command,
            testRunner: _testCommandRunner.runTests,
          ).execute();
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
          printZukeHelp(version: version);
          return 1;
        case 'attestation':
          if (command.command?.name == 'create') {
            return await AttestationCommand(command.command!).create();
          }
          printZukeHelp(version: version);
          return 1;
        case 'gateway':
          if (command.command?.name == 'canonicalize-apim') {
            return GatewayCanonicalizeCommand(command.command!).execute();
          }
          printZukeHelp(version: version);
          return 1;
        case 'artifacts':
          if (command.command?.name == 'audit') {
            return ArtifactAuditCommand(command.command!).execute();
          }
          if (command.command?.name == 'package') {
            return ArtifactPackageCommand(command.command!).execute();
          }
          printZukeHelp(version: version);
          return 1;
        case 'contract':
          if (command.command?.name == 'verify') {
            return OpenApiContractCommand(command.command!).execute();
          }
          printZukeHelp(version: version);
          return 1;
        case 'policy':
          if (command.command?.name == 'check') {
            return PolicyCommand(command.command!).execute();
          }
          printZukeHelp(version: version);
          return 1;
        case 'init':
          return runInit(command);
        case 'adopt':
          if (command.command?.name == 'package') {
            return runAdoptPackage(command.command!);
          }
          printZukeHelp(version: version);
          return 1;
        case 'watch':
          return _runWatch(command);
        case 'affected':
          return _runAffected(command);
        case 'test':
          return await _testCommandRunner.runTests(command);
        case 'coverage':
          return await CoverageCommand(command).execute();
        case 'certify':
          if (command.command?.name == 'hosted') {
            return await runHostedCertification(command.command!);
          }
          printZukeHelp(version: version);
          return 1;
        default:
          printZukeHelp(version: version);
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
}
