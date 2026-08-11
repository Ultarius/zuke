enum DiagnosticSeverity { info, warning, error }

enum DiagnosticOwner { project, environment, zuke, unknown }

final class DiagnosticV2 {
  final String code;
  final String stage;
  final DiagnosticSeverity severity;
  final DiagnosticOwner owner;
  final String message;
  final String remediation;
  final String? profile;
  final String? runnerId;
  final Map<String, String> context;

  const DiagnosticV2({
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

  factory DiagnosticV2.fromJson(Map<Object?, Object?> json) {
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
          'project' => DiagnosticOwner.project,
          'environment' => DiagnosticOwner.environment,
          'zuke' => DiagnosticOwner.zuke,
          'unknown' || null => DiagnosticOwner.unknown,
          _ => throw FormatException('Unknown diagnostic owner: $value'),
        };

    final rawContext = json['context'];
    final context = <String, String>{};
    if (rawContext != null) {
      if (rawContext is! Map || rawContext.keys.any((key) => key is! String) ||
          rawContext.values.any((value) => value is! String)) {
        throw const FormatException('Diagnostic context must be string-to-string');
      }
      for (final entry in rawContext.entries) {
        context[entry.key as String] = entry.value as String;
      }
    }
    return DiagnosticV2(
      code: requiredString('code'),
      stage: requiredString('stage'),
      severity: parseSeverity(json['severity']),
      owner: parseOwner(json['owner']),
      message: requiredString('message'),
      remediation: (json['remediation'] as String?) ?? '',
      profile: json['profile'] as String?,
      runnerId: json['runnerId'] as String?,
      context: context,
    );
  }
}

final class CommandResultV2 {
  final String command;
  final String stage;
  final int exitCode;
  final String status;
  final bool eligible;
  final List<DiagnosticV2> diagnostics;

  const CommandResultV2({
    required this.command,
    required this.stage,
    required this.exitCode,
    required this.status,
    required this.eligible,
    this.diagnostics = const [],
  });

  bool get succeeded => exitCode == 0 && status == 'passed' && eligible;

  Map<String, Object?> toJson() => {
        'schemaVersion': 'zuke.command-result.v2',
        'command': command,
        'stage': stage,
        'exitCode': exitCode,
        'status': status,
        'eligible': eligible,
        'diagnostics': diagnostics.map((diagnostic) => diagnostic.toJson()).toList(),
      };

  factory CommandResultV2.fromJson(Map<Object?, Object?> json) {
    if (json['schemaVersion'] != 'zuke.command-result.v2') {
      throw const FormatException('Unsupported command result schema');
    }
    final exitCode = json['exitCode'];
    final eligible = json['eligible'];
    if (exitCode is! int || eligible is! bool) {
      throw const FormatException('Command result status fields are malformed');
    }
    final diagnostics = json['diagnostics'];
    if (diagnostics is! List || diagnostics.any((item) => item is! Map)) {
      throw const FormatException('Command result diagnostics are malformed');
    }
    return CommandResultV2(
      command: json['command'] as String? ?? 'unknown',
      stage: json['stage'] as String? ?? 'unknown',
      exitCode: exitCode,
      status: json['status'] as String? ?? 'unknown',
      eligible: eligible,
      diagnostics: diagnostics
          .cast<Map<Object?, Object?>>()
          .map(DiagnosticV2.fromJson)
          .toList(),
    );
  }
}
