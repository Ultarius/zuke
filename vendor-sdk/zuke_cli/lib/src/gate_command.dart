import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:zuke_core/zuke_core.dart';

import 'generate_command.dart';
import 'lock_command.dart';
import 'trust_bundle.dart';
import 'validate_command.dart';
import 'command_result.dart';
import 'configuration_preflight.dart';

class GateCommand {
  final ArgResults args;
  final Future<int> Function(ArgResults)? testRunner;
  GateCommand(this.args, {this.testRunner});

  Future<int> execute() async {
    final root = args['root'] as String? ?? Directory.current.path;
    final allProfiles =
        args.options.contains('all-profiles') &&
        (args['all-profiles'] as bool? ?? false);
    if (allProfiles) {
      if (args['profile'] != null) {
        throw const FormatException(
          'gate --profile and gate --all-profiles are mutually exclusive',
        );
      }
      return _executeAllProfiles(root);
    }
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
    final stageDiagnostics = <String, List<Diagnostic>>{};

    List<Diagnostic> diagnosticsFor(String stage) {
      final existing = stageDiagnostics[stage];
      if (existing != null && existing.isNotEmpty) return existing;
      return [
        gateDiagnostic(
          stage: stage,
          message: 'Gate stage $stage failed.',
          profile: profile,
        ),
      ];
    }

    void reportStage(String stage, String status) {
      if (!jsonMode) stdout.writeln('Gate [$stage]: $status');
    }

    int finish(int exitCode) {
      final artifactDiagnostic = _artifactSafetyDiagnostic(
        args['artifact-dir'] as String?,
      );
      final finalExitCode = artifactDiagnostic == null ? exitCode : 1;
      final diagnostics = [
        for (final entry in stages.entries)
          if (entry.value == 'failed') ...[...diagnosticsFor(entry.key)],
        if (artifactDiagnostic != null) artifactDiagnostic,
      ];
      final result = CommandResult(
        command: 'gate',
        stage: 'gate',
        exitCode: finalExitCode,
        status: finalExitCode == 0
            ? CommandStatus.passed
            : CommandStatus.failed,
        eligible: finalExitCode == 0,
        diagnostics: diagnostics,
        details: {
          'profile': profile,
          'stages': [
            for (final entry in stages.entries)
              {
                'name': entry.key,
                'status': entry.value,
                'exitCode': entry.value == 'failed' ? 1 : 0,
                'eligible': entry.value == 'passed',
                'remediation': entry.value == 'failed'
                    ? 'Inspect the stage diagnostics and resolve the reported failure.'
                    : '',
                'diagnostics': entry.value == 'failed'
                    ? diagnosticsFor(entry.key)
                          .map((diagnostic) => diagnostic.toJson())
                          .toList(growable: false)
                    : const <Object?>[],
              },
          ],
        },
      );
      final encoded = encodeCommandResult(result);
      if (jsonMode) {
        stdout.write(encoded);
      }
      writeCommandSummaryBytes(args['summary-file'] as String?, encoded);
      if (artifactDiagnostic == null) {
        _writeArtifactSummary(args['artifact-dir'] as String?, encoded);
      }
      return finalExitCode;
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
    final doctorDiagnostics = _doctorDiagnostics(root);
    stageDiagnostics['doctor'] = doctorDiagnostics;
    stages['doctor'] =
        doctorDiagnostics.any(
          (diagnostic) => diagnostic.severity == DiagnosticSeverity.error,
        )
        ? 'failed'
        : 'passed';
    reportStage('doctor', stages['doctor']!);
    if (stages['doctor'] == 'failed') {
      for (final entry in stages.entries) {
        if (entry.value == 'pending') stages[entry.key] = 'skipped';
      }
      return finish(1);
    }

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

  Future<int> _executeAllProfiles(String root) async {
    final artifactDiagnostic = _artifactSafetyDiagnostic(
      args['artifact-dir'] as String?,
    );
    if (artifactDiagnostic != null) {
      final result = CommandResult(
        command: 'gate',
        stage: 'gate',
        exitCode: 1,
        status: CommandStatus.failed,
        eligible: false,
        diagnostics: [artifactDiagnostic],
        details: const {'profiles': <Object?>[]},
      );
      final encoded = encodeCommandResult(result);
      stdout.write(encoded);
      writeCommandSummaryBytes(args['summary-file'] as String?, encoded);
      return 1;
    }
    final profiles = _profilesFor(root);
    final temporary = await Directory.systemTemp.createTemp('zuke-gate-');
    final profileResults = <Map<String, Object?>>[];
    try {
      for (final profile in profiles) {
        final summary = File('${temporary.path}/$profile.json');
        final artifactDir = Directory('${temporary.path}/$profile-artifacts');
        final process = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            'zuke_cli:zuke',
            'gate',
            '--root',
            root,
            '--profile',
            profile,
            '--format',
            'json',
            '--summary-file',
            summary.path,
            '--artifact-dir',
            artifactDir.path,
          ],
          // Resolve the package executable from the caller's workspace. The
          // checked root may be an example or nested application without its
          // own .dart_tool/package_config.json.
          workingDirectory: Directory.current.path,
        );
        final decoded = summary.existsSync()
            ? jsonDecode(summary.readAsStringSync())
            : null;
        if (decoded is Map) {
          try {
            final parsed = CommandResult.fromJson(
              Map<Object?, Object?>.from(decoded),
            );
            if ((process.exitCode == 0) != parsed.succeeded) {
              profileResults.add({
                'kind': 'zuke.command-result',
                'command': 'gate',
                'stage': 'gate',
                'exitCode': 1,
                'status': 'failed',
                'eligible': false,
                'diagnostics': [
                  gateDiagnostic(
                    stage: 'all-profiles',
                    message:
                        'Profile $profile exit code disagreed with its command result.',
                    profile: profile,
                  ).toJson(),
                ],
                'profile': profile,
              });
            } else {
              profileResults.add({'profile': profile, ...parsed.toJson()});
            }
          } on FormatException catch (error) {
            profileResults.add({
              'kind': 'zuke.command-result',
              'command': 'gate',
              'stage': 'gate',
              'exitCode': 1,
              'status': 'failed',
              'eligible': false,
              'diagnostics': [
                gateDiagnostic(
                  stage: 'all-profiles',
                  message:
                      'Profile $profile emitted malformed command result: $error',
                  profile: profile,
                ).toJson(),
              ],
              'profile': profile,
            });
          }
        } else {
          profileResults.add({
            'kind': 'zuke.command-result',
            'command': 'gate',
            'stage': 'gate',
            'exitCode': process.exitCode,
            'status': process.exitCode == 0 ? 'passed' : 'failed',
            'eligible': process.exitCode == 0,
            'diagnostics': [
              gateDiagnostic(
                stage: 'all-profiles',
                message:
                    'Profile $profile did not emit a structured command result.',
                profile: profile,
              ).toJson(),
            ],
            'profile': profile,
          });
        }
      }
    } finally {
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    }
    final failed = profileResults.any((result) => result['status'] != 'passed');
    final diagnostics = <Diagnostic>[];
    for (final profile in profileResults) {
      final raw = profile['diagnostics'];
      if (raw is List) {
        for (final diagnostic in raw.whereType<Map>()) {
          diagnostics.add(Diagnostic.fromJson(diagnostic));
        }
      }
    }
    final result = CommandResult(
      command: 'gate',
      stage: 'gate',
      exitCode: failed ? 1 : 0,
      status: failed ? CommandStatus.failed : CommandStatus.passed,
      eligible: !failed,
      diagnostics: diagnostics,
      details: {'profiles': profileResults},
    );
    final encoded = encodeCommandResult(result);
    stdout.write(encoded);
    writeCommandSummaryBytes(args['summary-file'] as String?, encoded);
    _writeArtifactSummary(args['artifact-dir'] as String?, encoded);
    return failed ? 1 : 0;
  }

  List<String> _profilesFor(String root) {
    try {
      final profiles = requireCurrentWorkspace(root).config.lockProfiles;
      if (profiles.isNotEmpty) return profiles;
    } on Object {
      // The individual profile result reports the configuration failure.
    }
    return const ['pullRequest', 'merge', 'release', 'nightly'];
  }

  List<Diagnostic> _doctorDiagnostics(String root) {
    final diagnostics = [...const ConfigurationPreflight().diagnose(root)];
    if (diagnostics.any(
      (diagnostic) => diagnostic.severity == DiagnosticSeverity.error,
    )) {
      return diagnostics;
    }
    if (!Directory('$root/specs/features').existsSync()) {
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
    }
    return diagnostics;
  }

  bool _inputStable(String root) {
    try {
      final first = requireCurrentWorkspace(root).inputContents;
      final second = requireCurrentWorkspace(root).inputContents;
      if (first.length != second.length) return false;
      for (final entry in first.entries) {
        if (second[entry.key] != entry.value) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _writeArtifactSummary(String? directory, String encoded) {
    if (directory == null || directory.isEmpty) return;
    final dir = Directory(directory);
    final unsafe = _unsafeArtifactEntry(dir);
    if (unsafe != null) {
      throw FormatException(
        'ZK-ARTIFACT-UNSAFE: refusing to write an artifact bundle containing '
        'unexpected entry $unsafe',
      );
    }
    dir.createSync(recursive: true);
    writeCommandResult(File('${dir.path}/command-result.json'), encoded);
  }

  Diagnostic? _artifactSafetyDiagnostic(String? directory) {
    if (directory == null || directory.isEmpty) return null;
    final unsafe = _unsafeArtifactEntry(Directory(directory));
    if (unsafe == null) return null;
    return Diagnostic(
      code: 'ZK-ARTIFACT-UNSAFE',
      stage: 'artifact',
      severity: DiagnosticSeverity.error,
      owner: DiagnosticOwner.zuke,
      message: 'Artifact directory contains an unexpected entry: $unsafe',
      remediation:
          'Remove the unexpected artifact entry and rerun the gate; raw logs, '
          'source, tokens, headers, and payloads are not allowed in the safe bundle.',
    );
  }

  String? _unsafeArtifactEntry(Directory directory) {
    if (!directory.existsSync()) return null;
    final root = directory.absolute.path.endsWith(Platform.pathSeparator)
        ? directory.absolute.path
        : '${directory.absolute.path}${Platform.pathSeparator}';
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) return entity.path;
      if (entity is! File) continue;
      final relative = entity.absolute.path.startsWith(root)
          ? entity.absolute.path.substring(root.length).replaceAll('\\', '/')
          : entity.path;
      if (relative != 'command-result.json') return relative;
    }
    return null;
  }

  int _checkTrustEligibility(String root) {
    try {
      final workspace = requireCurrentWorkspace(root);
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
