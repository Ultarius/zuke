import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'generate_command.dart';
import 'lock_command.dart';
import 'trust_bundle.dart';
import 'validate_command.dart';

class GateCommand {
  final ArgResults args;
  final Future<int> Function(ArgResults)? testRunner;
  GateCommand(this.args, {this.testRunner});

  Future<int> execute() async {
    final root = args['root'] as String? ?? Directory.current.path;
    final format = args['format'] as String? ?? 'text';
    final jsonMode = format == 'json';
    final stages = <String, String>{
      'generate': 'pending',
      'test': testRunner == null ? 'skipped' : 'pending',
      'validate': 'pending',
      'lock': 'pending',
      'trust': args['profile'] == 'release' ? 'pending' : 'skipped',
    };

    void reportStage(String stage, String status) {
      if (!jsonMode) stdout.writeln('Gate [$stage]: $status');
    }

    int finish(int exitCode) {
      if (jsonMode) {
        stdout.writeln(
          const JsonEncoder().convert({
            'schemaVersion': 'zuke.gate.v1',
            'status': exitCode == 0 ? 'passed' : 'failed',
            'profile': args['profile'] as String? ?? 'pullRequest',
            'stages': stages,
          }),
        );
      }
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
    reportStage('generate', 'running');
    final generatedResult = await GenerateCommand(
      generateParser.parse([
        '--root',
        root,
        '--check',
        if (jsonMode) '--quiet',
      ]),
    ).execute();
    stages['generate'] = generatedResult == 0 ? 'passed' : 'failed';
    reportStage('generate', stages['generate']!);
    if (generatedResult != 0) return finish(generatedResult);
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
      if (testResult != 0) return finish(testResult);
    }
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
    if (validateResult != 0) return finish(validateResult);
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
    if (lockResult != 0) return finish(lockResult);
    if (args['profile'] == 'release') {
      reportStage('trust', 'running');
      final trustResult = _checkTrustEligibility(root);
      stages['trust'] = trustResult == 0 ? 'passed' : 'failed';
      reportStage('trust', stages['trust']!);
      if (trustResult != 0) return finish(trustResult);
    }
    return finish(0);
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
          'ZUKE-TRUST-001: No trust metadata found at ${trustFile.path}',
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
