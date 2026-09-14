import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';

import 'package:zuke_core/zuke_core.dart';

/// Records a framework-produced gate result in the application's blocker
/// history. This tool deliberately consumes only the summary file; it does
/// not launch Zuke, inspect stdout/stderr, infer ownership, or redact output.
int recordGate(ArgResults args) {
  final summaryPath = (args['summary-file'] as String?);
  if (summaryPath == null) {
    stderr.writeln(
      'Usage: zuke gate record '
      '--summary-file <path> [--blocker-file <path>] [--output <path>]',
    );
    return 2;
  }

  final blockerPath =
      (args['blocker-file'] as String?) ?? 'generated/zuke/ci-blockers.txt';
  final outputPath = (args['output'] as String?);
  final releaseId = (args['release-id'] as String?) ?? 'unreleased';
  final commitSha = (args['commit-sha'] as String?) ?? 'unknown';
  final recordedAt = DateTime.now().toUtc();

  final recording = _readRecording(
    File(summaryPath),
    recordedAt: recordedAt,
    releaseId: releaseId,
    commitSha: commitSha,
  );
  final encoded = const JsonEncoder.withIndent('  ').convert(recording.json);

  final output = File(outputPath ?? '$blockerPath.json');
  output.parent.createSync(recursive: true);
  output.writeAsStringSync('$encoded\n');

  final blocker = File(blockerPath);
  blocker.parent.createSync(recursive: true);
  blocker.writeAsStringSync('${recording.text}\n', mode: FileMode.append);

  stdout.write('$encoded\n');
  return recording.passed ? 0 : 1;
}

final class _Recording {
  const _Recording({
    required this.passed,
    required this.json,
    required this.text,
  });

  final bool passed;
  final Map<String, Object?> json;
  final String text;
}

_Recording _readRecording(
  File summaryFile, {
  required DateTime recordedAt,
  required String releaseId,
  required String commitSha,
}) {
  try {
    if (!summaryFile.existsSync()) {
      return _missingRecording(
        recordedAt: recordedAt,
        releaseId: releaseId,
        commitSha: commitSha,
        reason: 'Summary file does not exist.',
      );
    }
    final decoded = jsonDecode(summaryFile.readAsStringSync());
    if (decoded is! Map) {
      throw const FormatException('Summary root must be an object');
    }
    final result = CommandResult.fromJson(Map<Object?, Object?>.from(decoded));
    final details = result.details;
    final runId = details['runId']?.toString() ?? 'unknown';
    final profile = details['profile']?.toString() ?? 'unknown';
    final passed = result.succeeded;
    final diagnostics = result.diagnostics
        .map(
          (diagnostic) => {
            'code': diagnostic.code,
            'stage': diagnostic.stage,
            'severity': diagnostic.severity.name,
            'owner': diagnostic.owner.name,
            'message': diagnostic.message,
            'remediation': diagnostic.remediation,
            if (diagnostic.profile != null) 'profile': diagnostic.profile,
            if (diagnostic.runnerId != null) 'runnerId': diagnostic.runnerId,
            if (diagnostic.context.isNotEmpty) 'context': diagnostic.context,
          },
        )
        .toList(growable: false);
    final json = <String, Object?>{
      'kind': 'zuke.application-gate-record',
      'recordedAt': recordedAt.toIso8601String(),
      'releaseId': releaseId,
      'commitSha': commitSha,
      'runId': runId,
      'profile': profile,
      'command': result.command,
      'stage': result.stage,
      'exitCode': result.exitCode,
      'status': result.status.name,
      'eligible': result.eligible,
      'passed': passed,
      'diagnostics': diagnostics,
    };
    return _Recording(
      passed: passed,
      json: json,
      text: _renderText(
        recordedAt: recordedAt,
        releaseId: releaseId,
        commitSha: commitSha,
        runId: runId,
        profile: profile,
        command: result.command,
        exitCode: result.exitCode,
        status: result.status.name,
        eligible: result.eligible,
        passed: passed,
        diagnostics: result.diagnostics,
      ),
    );
  } on Object catch (_) {
    return _missingRecording(
      recordedAt: recordedAt,
      releaseId: releaseId,
      commitSha: commitSha,
      reason: 'Summary file is missing or malformed.',
    );
  }
}

_Recording _missingRecording({
  required DateTime recordedAt,
  required String releaseId,
  required String commitSha,
  required String reason,
}) {
  const code = 'ZK-RESULT-MISSING';
  final diagnostic = {
    'code': code,
    'stage': 'gate',
    'severity': 'error',
    'owner': 'unknown',
    'message': reason,
    'remediation':
        'Produce a valid current Zuke command-result summary before recording the gate.',
  };
  final json = <String, Object?>{
    'kind': 'zuke.application-gate-record',
    'recordedAt': recordedAt.toIso8601String(),
    'releaseId': releaseId,
    'commitSha': commitSha,
    'runId': 'unknown',
    'profile': 'unknown',
    'command': 'gate',
    'stage': 'gate',
    'exitCode': 1,
    'status': 'failed',
    'eligible': false,
    'passed': false,
    'diagnostics': [diagnostic],
  };
  return _Recording(
    passed: false,
    json: json,
    text: _renderText(
      recordedAt: recordedAt,
      releaseId: releaseId,
      commitSha: commitSha,
      runId: 'unknown',
      profile: 'unknown',
      command: 'gate',
      exitCode: 1,
      status: 'failed',
      eligible: false,
      passed: false,
      diagnostics: const [
        Diagnostic(
          code: code,
          stage: 'gate',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.unknown,
          message: 'Summary file is missing or malformed.',
          remediation:
              'Produce a valid current Zuke command-result summary before recording the gate.',
        ),
      ],
    ),
  );
}

String _renderText({
  required DateTime recordedAt,
  required String releaseId,
  required String commitSha,
  required String runId,
  required String profile,
  required String command,
  required int exitCode,
  required String status,
  required bool eligible,
  required bool passed,
  required List<Diagnostic> diagnostics,
}) {
  final lines = <String>[
    '',
    'AUTOMATED ZUKE GATE RECORD: $runId',
    'Timestamp (UTC): ${recordedAt.toIso8601String()}',
    'Release: $releaseId',
    'Commit: $commitSha',
    'Stage: gate',
    'Profile: $profile',
    'Command: $command',
    'Process exit code: $exitCode',
    'Reported status: $status',
    'Eligible: $eligible',
    'Classification: ${passed ? 'PASSED' : 'BLOCKED'}',
  ];
  if (diagnostics.isEmpty) {
    lines.add('Diagnostics: none');
  } else {
    lines.add('Diagnostics:');
    for (final diagnostic in diagnostics) {
      lines.add(
        '- OWNER=${diagnostic.owner.name.toUpperCase()} '
        '${diagnostic.code}: ${diagnostic.message}'
        '${diagnostic.remediation.isEmpty ? '' : ' Remediation: ${diagnostic.remediation}'}',
      );
    }
  }
  return lines.join('\n');
}
