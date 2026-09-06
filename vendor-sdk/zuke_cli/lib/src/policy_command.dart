import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:yaml/yaml.dart';
import 'package:zuke_core/zuke_core.dart';

import 'command_result.dart';
import 'consumer_policy.dart';

/// Runs the reusable risk-acceptance verifier against a consumer-owned record.
final class PolicyCommand {
  const PolicyCommand(this.args);

  final ArgResults args;

  Future<int> execute() async {
    final root = Directory(args['root'] as String? ?? Directory.current.path);
    final input = _resolve(
      root,
      args['input'] as String? ?? 'assurance/risk-acceptance.yaml',
    );
    final policy = _resolve(
      root,
      args['policy'] as String? ?? 'policies/project-policy.yaml',
    );
    final jsonMode = (args['format'] as String? ?? 'text') == 'json';
    final diagnostics = <Diagnostic>[];
    Map<Object?, Object?>? record;
    if (!input.existsSync()) {
      diagnostics.add(
        Diagnostic(
          code: 'ZK-POLICY-MISSING',
          stage: 'policy',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.project,
          message: 'Risk-acceptance record is missing: ${input.path}',
          remediation:
              'Provide a current consumer-owned risk-acceptance record or do not invoke policy check.',
        ),
      );
    } else {
      try {
        final value = loadYaml(input.readAsStringSync());
        if (value is! Map) {
          throw const FormatException(
            'Risk-acceptance record must be a mapping.',
          );
        }
        record = Map<Object?, Object?>.from(value);
      } on Object catch (_) {
        diagnostics.add(
          Diagnostic(
            code: 'ZK-POLICY-MALFORMED',
            stage: 'policy',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.project,
            message: 'Risk-acceptance record could not be parsed.',
            remediation: 'Correct the YAML record and rerun policy check.',
            context: {'path': input.path},
          ),
        );
      }
    }

    final requirements = _requirements(policy, diagnostics);
    if (record != null) {
      final result = const RiskAcceptanceVerifier().verify(
        record,
        requirements: requirements,
        expectedCommit: args['commit'] as String? ?? _gitHead(root),
        expectedRelease: args['release'] as String?,
        now: _parseNow(args['now'] as String?),
      );
      diagnostics.addAll(
        result.diagnostics.map(
          (diagnostic) => Diagnostic(
            code: diagnostic.code,
            stage: 'policy',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.project,
            message: diagnostic.message,
            remediation:
                'Update the risk-acceptance record or consumer policy.',
            context: {'path': input.path},
          ),
        ),
      );
    }

    final failed = diagnostics.any(
      (diagnostic) => diagnostic.severity == DiagnosticSeverity.error,
    );
    final commandResult = CommandResult(
      command: 'policy check',
      stage: 'policy',
      exitCode: failed ? 1 : 0,
      status: failed ? CommandStatus.failed : CommandStatus.passed,
      eligible: !failed,
      diagnostics: diagnostics,
      details: {
        'root': root.path,
        'input': input.path,
        'policy': policy.path,
        'requirements': {
          'requiredApprovalCount': requirements.requiredApprovalCount,
          'requiredRoles': requirements.requiredRoles.toList()..sort(),
          'requiredCompensatingRuns':
              requirements.requiredCompensatingRuns.toList()..sort(),
        },
        'authenticatedApprovalRequired': true,
      },
    );
    final encoded = encodeCommandResult(commandResult);
    if (jsonMode) {
      stdout.write(encoded);
    } else {
      stdout.writeln(
        failed ? 'Risk acceptance is invalid.' : 'Risk acceptance is valid.',
      );
    }
    writeCommandSummaryBytes(args['summary-file'] as String?, encoded);
    return commandResult.exitCode;
  }

  RiskAcceptanceRequirements _requirements(
    File policy,
    List<Diagnostic> diagnostics,
  ) {
    if (!policy.existsSync()) {
      diagnostics.add(
        Diagnostic(
          code: 'ZK-POLICY-CONFIG-MISSING',
          stage: 'policy',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.project,
          message: 'Consumer risk-acceptance policy is missing.',
          remediation:
              'Provide the consumer policy before running policy check.',
          context: {'path': policy.path},
        ),
      );
      return const RiskAcceptanceRequirements();
    }
    try {
      final value = loadYaml(policy.readAsStringSync());
      if (value is! Map) {
        throw const FormatException('policy must be a mapping');
      }
      final document = ConsumerPolicyDocument.fromMap(
        Map<Object?, Object?>.from(value),
      );
      return document.toRequirements();
    } on Object catch (_) {
      diagnostics.add(
        Diagnostic(
          code: 'ZK-POLICY-CONFIG-MALFORMED',
          stage: 'policy',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.project,
          message: 'Consumer risk-acceptance policy could not be parsed.',
          remediation: 'Correct the policy file and rerun policy check.',
          context: {'path': policy.path},
        ),
      );
      return const RiskAcceptanceRequirements();
    }
  }

  File _resolve(Directory root, String value) {
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
        value.startsWith(Platform.pathSeparator)) {
      return File(value);
    }
    return File(
      '${root.path}${Platform.pathSeparator}${value.replaceAll('/', Platform.pathSeparator)}',
    );
  }

  DateTime? _parseNow(String? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('--now must be an ISO-8601 date: $value');
    }
    return parsed.toUtc();
  }

  String? _gitHead(Directory root) {
    try {
      final result = Process.runSync(
        'git',
        const ['rev-parse', 'HEAD'],
        workingDirectory: root.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode == 0) {
        final value = (result.stdout as String).trim();
        if (value.isNotEmpty) return value;
      }
    } on Object {
      // A source archive may have no Git metadata; local structural validation
      // remains useful in that environment.
    }
    return null;
  }
}
