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

    final rawRemediation = json['remediation'];
    if (rawRemediation != null && rawRemediation is! String) {
      throw const FormatException('Diagnostic remediation must be a string');
    }

    final rawContext = json['context'];
    final context = <String, String>{};
    if (rawContext != null) {
      if (rawContext is! Map ||
          rawContext.keys.any((key) => key is! String) ||
          rawContext.values.any((value) => value is! String)) {
        throw const FormatException(
          'Diagnostic context must be string-to-string',
        );
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
      remediation: rawRemediation as String? ?? '',
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
  /// Additional structured command details, such as profile, stage results,
  /// workspace results, and run identity. Raw process output is never stored.
  final Map<String, Object?> details;

  const CommandResult({
    required this.command,
    required this.stage,
    required this.exitCode,
    required this.status,
    required this.eligible,
    this.diagnostics = const [],
    this.details = const {},
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
    'diagnostics': diagnostics
        .map((diagnostic) => diagnostic.toJson())
        .toList(),
    ..._serializableDetails(),
  };

  Map<String, Object?> _serializableDetails() {
    const reserved = {
      'kind',
      'command',
      'stage',
      'exitCode',
      'status',
      'eligible',
      'diagnostics',
    };
    if (details.keys.any(reserved.contains)) {
      throw StateError(
        'Command result details cannot overwrite envelope fields',
      );
    }
    return Map<String, Object?>.from(details);
  }

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
    final consistent = switch (status) {
      CommandStatus.passed => exitCode == 0 && eligible,
      CommandStatus.failed => exitCode != 0 && !eligible,
    };
    if (!consistent) {
      throw const FormatException(
        'Command result status disagrees with exit code or eligibility',
      );
    }
    final diagnostics = json['diagnostics'];
    if (diagnostics is! List || diagnostics.any((item) => item is! Map)) {
      throw const FormatException('Command result diagnostics are malformed');
    }
    final details = <String, Object?>{};
    for (final entry in json.entries) {
      if (!const {
        'kind',
        'command',
        'stage',
        'exitCode',
        'status',
        'eligible',
        'diagnostics',
      }.contains(entry.key)) {
        details[entry.key.toString()] = entry.value;
      }
    }
    _validateNestedDetails(details);
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
      details: details,
    );
  }

  static void _validateNestedDetails(Map<String, Object?> details) {
    final rawStages = details['stages'];
    if (rawStages != null) {
      _validateStages(rawStages);
    }
    final rawWorkspaces = details['workspaces'];
    if (rawWorkspaces != null) {
      if (rawWorkspaces is! List ||
          rawWorkspaces.any((workspace) => workspace is! Map)) {
        throw const FormatException(
          'Command result workspaces are malformed',
        );
      }
      for (final raw in rawWorkspaces) {
        final workspace = Map<Object?, Object?>.from(raw as Map);
        if (workspace['root'] is! String ||
            (workspace['root'] as String).isEmpty ||
            workspace['status'] is! String ||
            !const {'passed', 'failed'}.contains(workspace['status']) ||
            workspace['stages'] is! List) {
          throw const FormatException(
            'Command result workspace is malformed',
          );
        }
      }
    }
    final rawProfiles = details['profiles'];
    if (rawProfiles != null) {
      if (rawProfiles is! List || rawProfiles.any((profile) => profile is! Map)) {
        throw const FormatException('Command result profiles are malformed');
      }
      for (final raw in rawProfiles) {
        final profile = Map<Object?, Object?>.from(raw as Map);
        if (profile['profile'] is! String ||
            (profile['profile'] as String).isEmpty) {
          throw const FormatException('Command result profile is malformed');
        }
        final profileExitCode = profile['exitCode'];
        final profileStatus = profile['status'];
        final profileEligible = profile['eligible'];
        if (profileExitCode is! int ||
            profileEligible is! bool ||
            profileStatus is! String ||
            !const {'passed', 'failed'}.contains(profileStatus)) {
          throw const FormatException(
            'Command result profile status fields are malformed',
          );
        }
        final profileConsistent = profileStatus == 'passed'
            ? profileExitCode == 0 && profileEligible
            : profileExitCode != 0 && !profileEligible;
        if (!profileConsistent) {
          throw const FormatException(
            'Command result profile disagrees with status fields',
          );
        }
        final stages = profile['stages'];
        if (stages != null) _validateStages(stages);
        final diagnostics = profile['diagnostics'];
        if (diagnostics is! List || diagnostics.any((item) => item is! Map)) {
          throw const FormatException(
            'Command result profile diagnostics are malformed',
          );
        }
        for (final diagnostic in diagnostics) {
          Diagnostic.fromJson(Map<Object?, Object?>.from(diagnostic as Map));
        }
      }
    }
  }

  static void _validateStages(Object? rawStages) {
    if (rawStages is! List || rawStages.any((stage) => stage is! Map)) {
      throw const FormatException('Command result stages are malformed');
    }
    for (final raw in rawStages) {
      final stage = Map<Object?, Object?>.from(raw as Map);
      final name = stage['name'];
      final status = stage['status'];
      final exitCode = stage['exitCode'];
      final eligible = stage['eligible'];
      if (name is! String || name.isEmpty ||
          status is! String ||
          !const {'passed', 'failed', 'skipped'}.contains(status) ||
          exitCode is! int || eligible is! bool) {
        throw const FormatException(
          'Command result stage identity or status is malformed',
        );
      }
      final consistent = switch (status) {
        'passed' => exitCode == 0 && eligible,
        'failed' => exitCode != 0 && !eligible,
        'skipped' => exitCode == 0 && !eligible,
        _ => false,
      };
      if (!consistent) {
        throw const FormatException(
          'Command result stage disagrees with status fields',
        );
      }
      final stageDiagnostics = stage['diagnostics'];
      if (stageDiagnostics is! List ||
          stageDiagnostics.any((item) => item is! Map)) {
        throw const FormatException(
          'Command result stage diagnostics are malformed',
        );
      }
      final remediation = stage['remediation'];
      if (remediation != null && remediation is! String) {
        throw const FormatException(
          'Command result stage remediation is malformed',
        );
      }
      for (final diagnostic in stageDiagnostics) {
        Diagnostic.fromJson(Map<Object?, Object?>.from(diagnostic as Map));
      }
    }
  }
}
