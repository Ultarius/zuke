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
import 'artifact_audit.dart';

final class _ArtifactAuditOutcome {
  const _ArtifactAuditOutcome({required this.report, this.diagnostic});

  final ArtifactAuditReport report;
  final Diagnostic? diagnostic;
}

typedef GateProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

class GateCommand {
  final ArgResults args;
  final Future<int> Function(ArgResults)? testRunner;
  final GateProcessRunner processRunner;
  GateCommand(this.args, {this.testRunner, GateProcessRunner? processRunner})
    : processRunner = processRunner ?? Process.run;

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
      final artifactDirectory = args['artifact-dir'] as String?;
      final artifactDiagnostic = _artifactSafetyDiagnostic(artifactDirectory);
      final auditRequested =
          args.options.contains('audit-artifacts') &&
          (args['audit-artifacts'] as bool? ?? false);
      Diagnostic? artifactAuditDiagnostic;
      ArtifactAuditReport? artifactAuditReport;
      if (auditRequested &&
          (artifactDirectory == null || artifactDirectory.isEmpty)) {
        artifactAuditDiagnostic = const Diagnostic(
          code: 'ZK-GATE-ARTIFACT-AUDIT-REQUIRES-DIRECTORY',
          stage: 'artifact',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.zuke,
          message: 'gate --audit-artifacts requires --artifact-dir.',
          remediation:
              'Provide the exact artifact directory that will be uploaded and rerun the gate.',
        );
      }

      CommandResult buildResult(int resultExitCode) {
        final diagnostics = [
          for (final entry in stages.entries)
            if (entry.value == 'failed') ...[...diagnosticsFor(entry.key)],
          if (artifactDiagnostic != null) artifactDiagnostic,
          if (artifactAuditDiagnostic != null) artifactAuditDiagnostic,
        ];
        return CommandResult(
          command: 'gate',
          stage: 'gate',
          exitCode: resultExitCode,
          status: resultExitCode == 0
              ? CommandStatus.passed
              : CommandStatus.failed,
          eligible: resultExitCode == 0,
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
            if (artifactAuditReport != null)
              'artifactAudit': artifactAuditReport!.toJson(),
          },
        );
      }

      final initialExitCode = artifactDiagnostic == null ? exitCode : 1;
      if (auditRequested &&
          artifactDirectory != null &&
          artifactDiagnostic == null &&
          artifactAuditDiagnostic == null) {
        final outcome = _auditFinalArtifactBundle(artifactDirectory, (report) {
          artifactAuditReport = report;
          return encodeCommandResult(buildResult(initialExitCode));
        });
        artifactAuditReport = outcome.report;
        artifactAuditDiagnostic = outcome.diagnostic;
      }
      var finalExitCode = artifactAuditDiagnostic == null ? initialExitCode : 1;
      var result = buildResult(finalExitCode);
      var encoded = encodeCommandResult(result);
      if (artifactDiagnostic == null && artifactAuditDiagnostic == null) {
        if (!auditRequested) _writeArtifactSummary(artifactDirectory, encoded);
      } else if (artifactDirectory != null) {
        _deleteArtifactSummary(artifactDirectory);
      }
      if (jsonMode) stdout.write(encoded);
      writeCommandSummaryBytes(args['summary-file'] as String?, encoded);
      _writeAuxiliaryResults(result);
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
    final validateCommand = ValidateCommand(
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
    );
    final validateResult = await validateCommand.execute();
    stageDiagnostics['validate'] = validateCommand.diagnostics;
    stages['validate'] = validateResult == 0 ? 'passed' : 'failed';
    reportStage('validate', stages['validate']!);
    reportStage('lock', 'running');
    final lockCommand = LockCommand(
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
    );
    final lockResult = await lockCommand.execute();
    stageDiagnostics['lock'] = lockCommand.diagnostics;
    stages['lock'] = lockResult == 0 ? 'passed' : 'failed';
    reportStage('lock', stages['lock']!);
    if (profile == 'release') {
      reportStage('trust', 'running');
      final trustResult = _checkTrustEligibility(root);
      stageDiagnostics['trust'] = trustResult;
      if (!jsonMode) {
        for (final diagnostic in trustResult) {
          stderr.writeln('${diagnostic.code}: ${diagnostic.message}');
          stderr.writeln('  ${diagnostic.remediation}');
        }
      }
      stages['trust'] = trustResult.isEmpty ? 'passed' : 'failed';
      reportStage('trust', stages['trust']!);
    }
    final failed = stages.values.any((status) => status == 'failed');
    return finish(failed ? 1 : 0);
  }

  Future<int> _executeAllProfiles(String root) async {
    final artifactDirectory = args['artifact-dir'] as String?;
    final auditRequested =
        args.options.contains('audit-artifacts') &&
        (args['audit-artifacts'] as bool? ?? false);
    if (auditRequested &&
        (artifactDirectory == null || artifactDirectory.isEmpty)) {
      final result = CommandResult(
        command: 'gate',
        stage: 'artifact',
        exitCode: 1,
        status: CommandStatus.failed,
        eligible: false,
        diagnostics: [
          const Diagnostic(
            code: 'ZK-GATE-ARTIFACT-AUDIT-REQUIRES-DIRECTORY',
            stage: 'artifact',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.zuke,
            message: 'gate --audit-artifacts requires --artifact-dir.',
            remediation:
                'Provide the exact artifact directory that will be uploaded and rerun the gate.',
          ),
        ],
        details: const {'profiles': <Object?>[]},
      );
      final encoded = encodeCommandResult(result);
      stdout.write(encoded);
      writeCommandSummaryBytes(args['summary-file'] as String?, encoded);
      return 1;
    }
    final artifactDiagnostic = _artifactSafetyDiagnostic(artifactDirectory);
    if (artifactDiagnostic != null) {
      var result = CommandResult(
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
        final process = await processRunner(
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
            if (args['runner-mode'] != null) ...[
              '--runner-mode',
              args['runner-mode'] as String,
            ],
            if (auditRequested) '--audit-artifacts',
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
    ArtifactAuditReport? artifactAuditReport;
    Diagnostic? artifactAuditDiagnostic;
    CommandResult buildResult(ArtifactAuditReport? report) {
      final resultExitCode = artifactAuditDiagnostic == null && !failed ? 0 : 1;
      return CommandResult(
        command: 'gate',
        stage: 'gate',
        exitCode: resultExitCode,
        status: resultExitCode == 0
            ? CommandStatus.passed
            : CommandStatus.failed,
        eligible: resultExitCode == 0,
        diagnostics: [
          ...diagnostics,
          if (artifactAuditDiagnostic != null) artifactAuditDiagnostic,
        ],
        details: {
          'profiles': profileResults,
          if (report != null) 'artifactAudit': report.toJson(),
        },
      );
    }

    if (auditRequested && artifactDirectory != null) {
      final outcome = _auditFinalArtifactBundle(
        artifactDirectory,
        (report) => encodeCommandResult(buildResult(report)),
      );
      artifactAuditReport = outcome.report;
      artifactAuditDiagnostic = outcome.diagnostic;
    }

    final result = buildResult(artifactAuditReport);
    final encoded = encodeCommandResult(result);
    if (!auditRequested && artifactAuditDiagnostic == null) {
      _writeArtifactSummary(artifactDirectory, encoded);
    }
    stdout.write(encoded);
    writeCommandSummaryBytes(args['summary-file'] as String?, encoded);
    _writeAuxiliaryResults(result);
    return result.exitCode;
  }

  void _writeAuxiliaryResults(CommandResult result) {
    final blocker = args['blocker-file'] as String?;
    final handoff = args['handoff-file'] as String?;
    if ((blocker == null || blocker.isEmpty) &&
        (handoff == null || handoff.isEmpty)) {
      return;
    }
    final diagnostics = result.diagnostics
        .map(
          (diagnostic) => {
            'code': diagnostic.code,
            'stage': diagnostic.stage,
            'owner': diagnostic.owner.name,
            if (diagnostic.profile != null) 'profile': diagnostic.profile,
            'remediation': diagnostic.remediation,
          },
        )
        .toList(growable: false);
    final payload =
        '${canonicalJson({'kind': 'zuke.gate-auxiliary', 'status': result.status.name, 'eligible': result.eligible, 'blocked': !result.eligible, 'ownerDiagnostics': diagnostics})}\n';
    for (final path in [blocker, handoff]) {
      if (path == null || path.isEmpty) continue;
      final file = File(path);
      file.parent.createSync(recursive: true);
      writeCommandResult(file, payload);
    }
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

  _ArtifactAuditOutcome _auditFinalArtifactBundle(
    String directory,
    String Function(ArtifactAuditReport report) encode,
  ) {
    // The summary is part of the bundle. The gate rejects every pre-existing
    // file except command-result.json, so the staged bundle has one file and
    // can be assembled with the deterministic safe report before auditing.
    // No bytes are written after the final read-only audit.
    final stagedReport = ArtifactAuditReport(
      input: directory,
      filesScanned: 1,
      findings: const [],
    );
    _writeArtifactSummary(directory, encode(stagedReport));
    final audit = const ArtifactAudit().inspect(Directory(directory));
    final finalReport = ArtifactAuditReport(
      input: directory,
      filesScanned: audit.filesScanned,
      findings: audit.findings,
    );
    if (!audit.safe ||
        canonicalJson(stagedReport.toJson()) !=
            canonicalJson(finalReport.toJson())) {
      _deleteArtifactSummary(directory);
      final report = audit.safe
          ? ArtifactAuditReport(
              input: directory,
              filesScanned: finalReport.filesScanned,
              findings: const [
                ArtifactAuditFinding(
                  category: 'unstable-input',
                  path: 'command-result.json',
                  message:
                      'The staged artifact report did not match the final bundle.',
                ),
              ],
            )
          : finalReport;
      return _ArtifactAuditOutcome(
        report: report,
        diagnostic: _artifactAuditDiagnostic(report),
      );
    }
    return _ArtifactAuditOutcome(report: finalReport);
  }

  void _deleteArtifactSummary(String directory) {
    final file = File(
      '${Directory(directory).path}${Platform.pathSeparator}command-result.json',
    );
    if (file.existsSync()) file.deleteSync();
  }

  Diagnostic _artifactAuditDiagnostic(ArtifactAuditReport report) {
    final locations = report.findings
        .map((finding) => '${finding.category} at ${finding.path}')
        .join(', ');
    return Diagnostic(
      code: 'ZK-GATE-ARTIFACT-AUDIT-FAILED',
      stage: 'artifact',
      severity: DiagnosticSeverity.error,
      owner: DiagnosticOwner.zuke,
      message:
          'Artifact audit rejected ${report.findings.length} finding(s): $locations.',
      remediation:
          'Run `zuke artifacts audit --input <exact-bundle>` and remove every reported finding before upload.',
    );
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

  List<Diagnostic> _checkTrustEligibility(String root) {
    List<Diagnostic> failure(String message) => [
      Diagnostic(
        code: 'ZUKE-TRUST-001',
        stage: 'trust',
        severity: DiagnosticSeverity.error,
        owner: DiagnosticOwner.project,
        message: message,
        remediation:
            'Configure the trust bundle with an authorized public signing key '
            'whose status is active and whose usages include release.',
        profile: 'release',
      ),
    ];
    try {
      final workspace = requireCurrentWorkspace(root);
      final trustFile = configuredTrustBundle(
        root,
        configuredPath: workspace.config.trustBundle,
      );
      if (!trustFile.existsSync()) {
        return failure(
          'Ed25519 attestation trust bundle is missing at ${trustFile.path}',
        );
      }
      final trust = loadTrustBundle(
        root,
        configuredPath: workspace.config.trustBundle,
      );
      final activeReleaseKeys = trust.keys
          .where((k) => k.active && k.usages.contains('release'))
          .toList();
      if (activeReleaseKeys.isEmpty) {
        return failure('No active release signers in ${trustFile.path}');
      }
    } on FormatException catch (e) {
      return failure(e.message);
    } on StateError catch (e) {
      return failure('${e.message}');
    }
    return const [];
  }
}
