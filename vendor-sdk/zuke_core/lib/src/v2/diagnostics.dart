enum DiagnosticSeverity { info, warning, error }

enum DiagnosticOwner { project, environment, zuke, unknown }

enum CommandStatus { passed, failed }

final class Diagnostic {
  final String code;
  final String stage;
  final DiagnosticSeverity severity;
  final DiagnosticOwner owner;
  final String message;
  final String remediation;
  final String? profile;
  final String? runnerId;
  final Map<String, String> context;

  const Diagnostic({
    required this.code,
    required this.stage,
    required this.severity,
    this.owner = DiagnosticOwner.unknown,
    required this.message,
    this.remediation = '',
    this.profile,
    this.runnerId,
    this.context = const {},
  });

  Map<String, Object?> toJson() => {
        'code': code,
        'stage': stage,
        'severity': severity.name,
        'owner': owner.name,
        'message': message,
        if (remediation.isNotEmpty) 'remediation': remediation,
        if (profile != null) 'profile': profile,
        if (runnerId != null) 'runnerId': runnerId,
        if (context.isNotEmpty) 'context': Map<String, String>.from(context),
      };

  factory Diagnostic.fromJson(Map<Object?, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Diagnostic requires non-empty $key');
      }
      return value;
    }

    DiagnosticSeverity parseSeverity(Object? value) => switch (value) {
          'info' => DiagnosticSeverity.info,
          'warning' => DiagnosticSeverity.warning,
          'error' => DiagnosticSeverity.error,
          _ => throw FormatException('Unknown diagnostic severity: $value'),
        };

    DiagnosticOwner parseOwner(Object? value) => switch (value) {
          null || 'unknown' => DiagnosticOwner.unknown,
          'project' => DiagnosticOwner.project,
          'environment' => DiagnosticOwner.environment,
          'zuke' => DiagnosticOwner.zuke,
          _ => throw FormatException('Unknown diagnostic owner: $value'),
        };

    String? optionalString(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.isEmpty) {
        throw FormatException('Diagnostic $key must be non-empty');
      }
      return value;
    }

    final rawContext = json['context'];
    final context = <String, String>{};
    if (rawContext != null) {
      if (rawContext is! Map ||
          rawContext.keys.any((key) => key is! String) ||
          rawContext.values.any((value) => value is! String)) {
        throw const FormatException('Diagnostic context must be string-to-string');
      }
      for (final entry in rawContext.entries) {
        context[entry.key as String] = entry.value as String;
      }
    }
    return Diagnostic(
      code: requiredString('code'),
      stage: requiredString('stage'),
      severity: parseSeverity(json['severity']),
      owner: parseOwner(json['owner']),
      message: requiredString('message'),
      remediation: (json['remediation'] as String?) ?? '',
      profile: optionalString('profile'),
      runnerId: optionalString('runnerId'),
      context: context,
    );
  }
}

final class CommandResult {
  final String command;
  final String stage;
  final int exitCode;
  final CommandStatus status;
  final bool eligible;
  final List<Diagnostic> diagnostics;

  const CommandResult({
    required this.command,
    required this.stage,
    required this.exitCode,
    required this.status,
    required this.eligible,
    this.diagnostics = const [],
  });

  bool get succeeded =>
      exitCode == 0 && status == CommandStatus.passed && eligible;

  Map<String, Object?> toJson() => {
        'kind': 'zuke.command-result',
        'command': command,
        'stage': stage,
        'exitCode': exitCode,
        'status': status.name,
        'eligible': eligible,
        'diagnostics': diagnostics.map((diagnostic) => diagnostic.toJson()).toList(),
      };

  factory CommandResult.fromJson(Map<Object?, Object?> json) {
    if (json['kind'] != 'zuke.command-result') {
      throw const FormatException(
        'Unsupported command result format; regenerate with the current Zuke CLI',
      );
    }
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Command result requires non-empty $key');
      }
      return value;
    }

    final exitCode = json['exitCode'];
    final eligible = json['eligible'];
    if (exitCode is! int || eligible is! bool) {
      throw const FormatException('Command result status fields are malformed');
    }
    final status = switch (requiredString('status')) {
      'passed' => CommandStatus.passed,
      'failed' => CommandStatus.failed,
      final value => throw FormatException('Unknown command status: $value'),
    };
    if ((status == CommandStatus.passed) != (exitCode == 0 && eligible)) {
      throw const FormatException('Command result status disagrees with exit code or eligibility');
    }
    final diagnostics = json['diagnostics'];
    if (diagnostics is! List || diagnostics.any((item) => item is! Map)) {
      throw const FormatException('Command result diagnostics are malformed');
    }
    return CommandResult(
      command: requiredString('command'),
      stage: requiredString('stage'),
      exitCode: exitCode,
      status: status,
      eligible: eligible,
      diagnostics: diagnostics
          .cast<Map<Object?, Object?>>()
          .map(Diagnostic.fromJson)
          .toList(),
    );
  }
}
