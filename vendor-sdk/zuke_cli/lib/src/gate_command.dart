import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zuke_core/zuke_core.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'generate_command.dart';
import 'lock_command.dart';
import 'trust_bundle.dart';
import 'validate_command.dart';
import 'command_result.dart';

class GateCommand {
  final ArgResults args;
  final Future<int> Function(ArgResults)? testRunner;
  GateCommand(this.args, {this.testRunner});

  Future<int> execute() async {
    final root = args['root'] as String? ?? Directory.current.path;
    final format = args['format'] as String? ?? 'text';
    final jsonMode = format == 'json';
    final profile = args['profile'] as String? ?? 'pullRequest';
    final stages = <String, String>{
      'doctor': 'pending',
      'generate-check': 'pending',
      'test': testRunner == null ? 'skipped' : 'pending',
      'input-stability': 'pending',
      'validate': 'pending',
      'lock': 'pending',
      'trust': profile == 'release' ? 'pending' : 'skipped',
    };

    void reportStage(String stage, String status) {
      if (!jsonMode) stdout.writeln('Gate [$stage]: $status');
    }

    int finish(int exitCode) {
      final diagnostics = [
        for (final entry in stages.entries)
          if (entry.value == 'failed')
            gateDiagnostic(
              stage: entry.key,
              message: 'Gate stage ${entry.key} failed.',
              profile: profile,
            ),
      ];
      final result = CommandResult(
        command: 'gate',
        stage: 'gate',
        exitCode: exitCode,
        status: exitCode == 0 ? CommandStatus.passed : CommandStatus.failed,
        eligible: exitCode == 0,
        diagnostics: diagnostics,
      );
      if (jsonMode) {
        stdout.writeln(
          const JsonEncoder().convert({
            ...result.toJson(),
            'profile': profile,
            'stages': stages,
          }),
        );
      }
      writeCommandSummary(args['summary-file'] as String?, result);
      _writeArtifactSummary(args['artifact-dir'] as String?, result);
      return exitCode;
    }

    final validateParser = ArgParser()
      ..addOption('root')
      ..addOption('profile')
      ..addOption('format')
      ..addFlag('quiet', defaultsTo: false);
    final generateParser = ArgParser()
      ..addOption('root')
      ..addFlag('check')
      ..addOption('output')
      ..addFlag('quiet', defaultsTo: false);
    final lockParser = ArgParser()
      ..addOption('root')
      ..addOption('profile')
      ..addFlag('check')
      // Internal option: gate JSON must retain stdout for its one envelope.
      ..addFlag('quiet', defaultsTo: false);
    reportStage('doctor', 'running');
    final doctorResult = _doctor(root);
    stages['doctor'] = doctorResult == 0 ? 'passed' : 'failed';
    reportStage('doctor', stages['doctor']!);

    reportStage('generate-check', 'running');
    final generatedResult = await GenerateCommand(
      generateParser.parse([
        '--root',
        root,
        '--check',
        if (jsonMode) '--quiet',
      ]),
    ).execute();
    stages['generate-check'] = generatedResult == 0 ? 'passed' : 'failed';
    reportStage('generate-check', stages['generate-check']!);
    if (testRunner != null) {
      final testParser = ArgParser()
        ..addOption('root')
        ..addOption('profile')
        ..addOption('format', defaultsTo: 'text')
        ..addOption('runner-mode')
        // Internal option: gate JSON must retain stdout for its one envelope.
        ..addFlag('quiet', defaultsTo: false);
      reportStage('test', 'running');
      final testResult = await testRunner!(
        testParser.parse([
          '--root',
          root,
          if (args['profile'] != null) ...[
            '--profile',
            args['profile'] as String,
          ],
          '--format',
          'text',
          if (args['runner-mode'] != null) ...[
            '--runner-mode',
            args['runner-mode'] as String,
          ],
          if (jsonMode) '--quiet',
        ]),
      );
      stages['test'] = testResult == 0 ? 'passed' : 'failed';
      reportStage('test', stages['test']!);
    }
    reportStage('input-stability', 'running');
    final stable = _inputStable(root);
    stages['input-stability'] = stable ? 'passed' : 'failed';
    reportStage('input-stability', stages['input-stability']!);
    reportStage('validate', 'running');
    final validateResult = await ValidateCommand(
      validateParser.parse([
        '--root',
        root,
        if (args['profile'] != null) ...[
          '--profile',
          args['profile'] as String,
        ],
        '--format',
        'text',
        if (jsonMode) '--quiet',
      ]),
    ).execute();
    stages['validate'] = validateResult == 0 ? 'passed' : 'failed';
    reportStage('validate', stages['validate']!);
    reportStage('lock', 'running');
    final lockResult = await LockCommand(
      lockParser.parse([
        '--root',
        root,
        '--check',
        if (jsonMode) '--quiet',
        if (args['profile'] != null) ...[
          '--profile',
          args['profile'] as String,
        ],
      ]),
    ).execute();
    stages['lock'] = lockResult == 0 ? 'passed' : 'failed';
    reportStage('lock', stages['lock']!);
    if (profile == 'release') {
      reportStage('trust', 'running');
      final trustResult = _checkTrustEligibility(root);
      stages['trust'] = trustResult == 0 ? 'passed' : 'failed';
      reportStage('trust', stages['trust']!);
    }
    final failed = stages.values.any((status) => status == 'failed');
    return finish(failed ? 1 : 0);
  }

  int _doctor(String root) {
    if (!File('$root/zuke.yaml').existsSync()) return 1;
    if (!Directory('$root/specs/features').existsSync()) return 1;
    return 0;
  }

  bool _inputStable(String root) {
    try {
      final first = WorkspaceDiscovery().discover(root).inputContents;
      final second = WorkspaceDiscovery().discover(root).inputContents;
      if (first.length != second.length) return false;
      for (final entry in first.entries) {
        if (second[entry.key] != entry.value) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _writeArtifactSummary(String? directory, CommandResult result) {
    if (directory == null || directory.isEmpty) return;
    final dir = Directory(directory)..createSync(recursive: true);
    File('${dir.path}/command-result.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(result.toJson()) + '\n',
    );
  }

  int _checkTrustEligibility(String root) {
    try {
      final workspace = WorkspaceDiscovery().discover(root);
      final trustFile = configuredTrustBundle(
        root,
        configuredPath: workspace.config.trustBundle,
      );
      if (!trustFile.existsSync()) {
        stderr.writeln(
          'ZUKE-TRUST-001: Ed25519 attestation trust bundle is missing at ${trustFile.path}',
        );
        stderr.writeln(
          '  Run `zuke manifest create --signer-id <id>` to initialize the Ed25519 trust bundle.',
        );
        return 1;
      }
      final trust = loadTrustBundle(
        root,
        configuredPath: workspace.config.trustBundle,
      );
      final activeReleaseKeys = trust.keys
          .where((k) => k.active && k.usages.contains('release'))
          .toList();
      if (activeReleaseKeys.isEmpty) {
        stderr.writeln(
          'ZUKE-TRUST-001: No active release signers in ${trustFile.path}',
        );
        stderr.writeln(
          '  At least one trust key must have status "active" and usage "release".',
        );
        return 1;
      }
    } on FormatException catch (e) {
      stderr.writeln('ZUKE-TRUST-001: $e');
      return 1;
    } on StateError catch (e) {
      stderr.writeln('ZUKE-TRUST-001: ${e.message}');
      return 1;
    }
    return 0;
  }
}
