import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';

import 'package:zuke_core/zuke_core.dart';

/// Builds a current package-owner handoff from a framework-produced gate
/// summary. Historical blocker entries remain an audit trail, not the source
/// of current ownership or release state.
int writeOwnerHandoff(ArgResults args) {
  final summaryPath =
      (args['summary-file'] as String?) ?? 'generated/zuke/gate-summary.json';
  final blockerPath =
      (args['blocker-file'] as String?) ?? 'docs/zuke-integration-blockers.txt';
  final outputPath =
      (args['output'] as String?) ?? 'generated/zuke/owner-handoff.txt';
  final releaseId = (args['release-id'] as String?) ?? 'unreleased';
  final commitSha = (args['commit-sha'] as String?) ?? 'unknown';
  final coveragePath = (args['coverage'] as String?) ?? 'coverage/report.json';

  final read = _readGate(File(summaryPath));
  final coverage = _readCoverage(File(coveragePath));
  final lines = <String>[
    'Zuke owner handoff',
    '==================',
    'Release scope: $releaseId',
    'Repository commit: $commitSha',
    'Generated from current gate summary: $summaryPath',
    'Append-only audit history: $blockerPath',
    '',
    'Current gate state',
    '------------------',
  ];

  if (read.result == null) {
    lines
      ..add('Status: BLOCKED')
      ..add('Eligibility: false')
      ..add('Exit code: 1')
      ..add('Current Zuke-owned diagnostics: none available')
      ..add('')
      ..add('Fail-closed reason: ${read.failure}')
      ..add(
        'Action: produce a valid current zuke.command-result summary before requesting package-owner action.',
      );
  } else {
    final result = read.result!;
    final details = result.details;
    lines
      ..add('Command: ${result.command}')
      ..add('Stage: ${result.stage}')
      ..add('Run ID: ${details['runId'] ?? 'unknown'}')
      ..add('Profile: ${details['profile'] ?? 'unknown'}')
      ..add('Status: ${result.status.name.toUpperCase()}')
      ..add('Eligibility: ${result.eligible}')
      ..add('Exit code: ${result.exitCode}')
      ..add('Classification: ${result.succeeded ? 'PASSED' : 'BLOCKED'}')
      ..add('')
      ..add('Current Zuke-owned diagnostics')
      ..add('------------------------------');

    final diagnostics = _currentZukeDiagnostics(result);
    if (diagnostics.isEmpty) {
      lines.add('None in the current gate result.');
    } else {
      for (final diagnostic in diagnostics) {
        lines
          ..add('- ${diagnostic.code} (${diagnostic.severity.name})')
          ..add('  Stage: ${diagnostic.stage}')
          ..add('  Message: ${diagnostic.message}')
          ..add(
            '  Remediation: ${diagnostic.remediation.isEmpty ? 'none supplied' : diagnostic.remediation}',
          );
        if (diagnostic.profile != null) {
          lines.add('  Profile: ${diagnostic.profile}');
        }
        if (diagnostic.runnerId != null) {
          lines.add('  Runner: ${diagnostic.runnerId}');
        }
      }
    }
  }

  lines
    ..add('')
    ..add('Coverage context')
    ..add('-----------------')
    ..add(coverage)
    ..add('')
    ..add('Ownership boundary')
    ..add('------------------')
    ..add(
      'Only structured diagnostics with owner=zuke are included above. '
      'Project, environment, and unknown diagnostics remain application-owned '
      'or unresolved and are intentionally excluded from this package-owner handoff.',
    )
    ..add(
      'The blocker history is retained separately for audit and is not treated '
      'as the current release state.',
    );

  final output = File(outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync('${lines.join('\n')}\n');
  return read.result == null ? 1 : 0;
}

final class _GateRead {
  const _GateRead({this.result, this.failure});

  final CommandResult? result;
  final String? failure;
}

_GateRead _readGate(File file) {
  try {
    if (!file.existsSync()) {
      return const _GateRead(failure: 'summary file does not exist');
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      return const _GateRead(failure: 'summary root is not an object');
    }
    return _GateRead(
      result: CommandResult.fromJson(Map<Object?, Object?>.from(decoded)),
    );
  } on Object catch (_) {
    return const _GateRead(failure: 'summary is malformed or not current');
  }
}

List<Diagnostic> _currentZukeDiagnostics(CommandResult result) {
  final found = <String, Diagnostic>{};
  void collect(Object? value) {
    if (value is List) {
      value.forEach(collect);
      return;
    }
    if (value is! Map) return;
    if (value['code'] is String &&
        value['stage'] is String &&
        value['severity'] is String &&
        value['message'] is String &&
        value.containsKey('owner')) {
      try {
        final diagnostic = Diagnostic.fromJson(
          Map<Object?, Object?>.from(value),
        );
        if (diagnostic.owner == DiagnosticOwner.zuke) {
          found['${diagnostic.code}|${diagnostic.stage}|${diagnostic.message}'] =
              diagnostic;
        }
      } on FormatException {
        // CommandResult.fromJson already validates known nested diagnostics.
      }
    }
    value.values.forEach(collect);
  }

  collect(result.diagnostics.map((diagnostic) => diagnostic.toJson()).toList());
  collect(result.details);
  return found.values.toList(growable: false);
}

String _readCoverage(File file) {
  if (!file.existsSync()) return 'Coverage report: unavailable (file missing).';
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      return 'Coverage report: unavailable (malformed root).';
    }
    final percent = decoded['percent'] ?? 'unavailable';
    final covered = decoded['covered'] ?? 'unavailable';
    final total = decoded['total'] ?? 'unavailable';
    return 'Coverage report: $percent% ($covered/$total).';
  } on Object catch (_) {
    return 'Coverage report: unavailable (malformed JSON).';
  }
}
