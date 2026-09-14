/// The typed portion of workspace configuration used by execution and source
/// identity code. The broader specification model intentionally stays
/// unchanged; these values replace Map scraping on package/runner paths.
///
/// Recognized keys are validated strictly: malformed values throw
/// [FormatException] (surfaced as `ZK-CONFIG-INVALID`). Unrecognized keys are
/// never rejected; they are retained in `extensions` and reported as
/// [ConfigWarning] diagnostics so rolling upgrades stay compatible.
library;

final class WorkspacePackage {
  final String id;
  final String path;
  final List<String> roots;

  const WorkspacePackage({
    required this.id,
    required this.path,
    required this.roots,
  });

  factory WorkspacePackage.fromMap(Map<Object?, Object?> value) {
    return WorkspacePackage(
      id: _requiredString(value, 'id'),
      path: _requiredString(value, 'path'),
      roots: _requiredStrings(value, 'roots'),
    );
  }

  Map<String, Object?> toJson() => {'id': id, 'path': path, 'roots': roots};
}

final class WorkspaceTarget {
  final String id;
  final String language;
  final String framework;
  final List<WorkspacePackage> packages;

  const WorkspaceTarget({
    required this.id,
    required this.language,
    required this.framework,
    required this.packages,
  });

  factory WorkspaceTarget.fromMap(String id, Map<Object?, Object?> value) {
    final rawPackages = value['packages'];
    if (rawPackages is! List) {
      throw FormatException('target $id requires packages');
    }
    return WorkspaceTarget(
      id: id,
      language: _requiredString(value, 'language'),
      framework: _requiredString(value, 'framework'),
      packages: [
        for (final raw in rawPackages)
          if (raw is Map)
            WorkspacePackage.fromMap(Map<Object?, Object?>.from(raw))
          else
            throw FormatException('target $id package must be a mapping'),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'language': language,
    'framework': framework,
    'packages': packages.map((package) => package.toJson()).toList(),
  };
}

/// A non-fatal configuration observation for an unrecognized key.
///
/// Warnings are surfaced as structured `ZK-CONFIG-UNKNOWN-KEY` diagnostics by
/// the CLI preflight. They never throw and never appear on stdout in JSON
/// mode; JSON consumers read them from the command-result diagnostics array.
final class ConfigWarning {
  const ConfigWarning({
    required this.code,
    required this.message,
    required this.path,
  });

  final String code;
  final String message;
  final String path;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'path': path,
  };
}

/// Runner kinds supported by the execution engine. Absent `kind` defaults to
/// `test` to preserve the historical runtime behavior in `zuke test`.
const _runnerKinds = {'setup', 'test', 'gherkin'};

/// Runner modes supported by the tool supervisor. Absent `runnerMode`
/// defaults to `auto`; Flutter runners also support a CLI override.
const _runnerModes = {'auto', 'cli', 'directSnapshot'};

final class WorkspaceRunner {
  final String id;
  final String target;
  final String sourcePackage;
  final String sourceAdapter;
  final String sourceCompatibilityId;
  final String runnerCompatibilityId;
  final String? executable;
  final List<String> args;
  final List<String> evidenceTypes;

  /// Execution kind. Defaults to `test` when absent (historical behavior).
  final String kind;

  /// Workspace-relative working directory. Null means the workspace root.
  final String? workingDirectory;

  /// Configured runner mode. Defaults to `auto`; Flutter runners support
  /// overriding this value with CLI `--runner-mode` at launch time.
  final String runnerMode;

  /// Per-runner execution timeout. Defaults to 600 seconds (historical).
  final int timeoutSeconds;

  /// Optional per-runner profile restriction. An explicitly empty YAML list
  /// selects no profiles; an omitted restriction allows all profiles.
  final List<String> profiles;

  final bool hasProfileRestriction;

  /// Unrecognized runner keys retained verbatim for forward compatibility.
  final Map<String, Object?> extensions;

  const WorkspaceRunner({
    required this.id,
    required this.target,
    required this.sourcePackage,
    required this.sourceAdapter,
    required this.sourceCompatibilityId,
    required this.runnerCompatibilityId,
    this.executable,
    this.args = const [],
    this.evidenceTypes = const [],
    this.kind = 'test',
    this.workingDirectory,
    this.runnerMode = 'auto',
    this.timeoutSeconds = 600,
    this.profiles = const [],
    this.hasProfileRestriction = false,
    this.extensions = const {},
  });

  static const _knownKeys = {
    'id',
    'target',
    'sourcePackage',
    'sourceAdapter',
    'sourceCompatibilityId',
    'runnerCompatibilityId',
    'executable',
    'args',
    'evidenceTypes',
    'kind',
    'workingDirectory',
    'runnerMode',
    'timeoutSeconds',
    'profiles',
  };

  factory WorkspaceRunner.fromMap(Map<Object?, Object?> value) {
    final rawArgs = value['args'];
    final rawEvidenceTypes = value['evidenceTypes'];
    if (rawArgs != null &&
        (rawArgs is! List || rawArgs.any((item) => item is! String))) {
      throw const FormatException('runner args must be string values');
    }
    if (rawEvidenceTypes != null &&
        (rawEvidenceTypes is! List ||
            rawEvidenceTypes.any((item) => item is! String || item.isEmpty))) {
      throw const FormatException('runner evidenceTypes must be string values');
    }
    final executable = value['executable'];
    if (executable != null &&
        (executable is! String || executable.trim().isEmpty)) {
      throw const FormatException(
        'runner executable must be a non-empty string',
      );
    }
    final rawKind = value['kind'];
    if (rawKind != null &&
        (rawKind is! String || !_runnerKinds.contains(rawKind))) {
      throw const FormatException(
        'runner kind must be one of gherkin, setup, test',
      );
    }
    final rawWorkingDirectory = value['workingDirectory'];
    if (rawWorkingDirectory != null &&
        (rawWorkingDirectory is! String ||
            rawWorkingDirectory.trim().isEmpty)) {
      throw const FormatException(
        'runner workingDirectory must be a non-empty string',
      );
    }
    final rawRunnerMode = value['runnerMode'];
    if (rawRunnerMode != null &&
        (rawRunnerMode is! String || !_runnerModes.contains(rawRunnerMode))) {
      throw const FormatException(
        'runner runnerMode must be one of auto, cli, directSnapshot',
      );
    }
    final rawTimeout = value['timeoutSeconds'];
    if (rawTimeout != null &&
        (rawTimeout is! num ||
            !rawTimeout.isFinite ||
            rawTimeout.toInt() <= 0)) {
      throw const FormatException(
        'runner timeoutSeconds must be a positive number',
      );
    }
    final rawProfiles = value['profiles'];
    if (rawProfiles != null &&
        (rawProfiles is! List ||
            rawProfiles.any(
              (item) => item is! String || item.trim().isEmpty,
            ))) {
      throw const FormatException('runner profiles must be non-empty strings');
    }
    return WorkspaceRunner(
      id: _requiredString(value, 'id'),
      target: _requiredString(value, 'target'),
      sourcePackage: _requiredString(value, 'sourcePackage'),
      sourceAdapter: _requiredString(value, 'sourceAdapter'),
      sourceCompatibilityId: _requiredString(value, 'sourceCompatibilityId'),
      runnerCompatibilityId: _requiredString(value, 'runnerCompatibilityId'),
      executable: executable as String?,
      args: rawArgs == null
          ? const []
          : List<String>.unmodifiable(rawArgs as List),
      evidenceTypes: rawEvidenceTypes == null
          ? const []
          : List<String>.unmodifiable(rawEvidenceTypes as List),
      kind: rawKind as String? ?? 'test',
      workingDirectory: rawWorkingDirectory as String?,
      runnerMode: rawRunnerMode as String? ?? 'auto',
      timeoutSeconds: rawTimeout == null ? 600 : (rawTimeout as num).toInt(),
      profiles: rawProfiles == null
          ? const []
          : List<String>.unmodifiable(rawProfiles as List),
      hasProfileRestriction: rawProfiles != null,
      extensions: Map.unmodifiable({
        for (final entry in value.entries)
          if (entry.key is String && !_knownKeys.contains(entry.key))
            entry.key as String: _freeze(entry.value),
      }),
    );
  }

  Map<String, Object?> toJson() => {
    ...extensions,
    'id': id,
    'target': target,
    'sourcePackage': sourcePackage,
    'sourceAdapter': sourceAdapter,
    'sourceCompatibilityId': sourceCompatibilityId,
    'runnerCompatibilityId': runnerCompatibilityId,
    if (executable != null) 'executable': executable,
    if (args.isNotEmpty) 'args': args,
    if (evidenceTypes.isNotEmpty) 'evidenceTypes': evidenceTypes,
    'kind': kind,
    if (workingDirectory != null) 'workingDirectory': workingDirectory,
    'runnerMode': runnerMode,
    'timeoutSeconds': timeoutSeconds,
    if (hasProfileRestriction || profiles.isNotEmpty) 'profiles': profiles,
  };
}

/// A named execution profile's scenario selection and extension fields.
final class ExecutionProfile {
  const ExecutionProfile({
    required this.tagExpression,
    this.extensions = const {},
  });

  final String tagExpression;
  final Map<String, Object?> extensions;

  factory ExecutionProfile.fromMap(Map<Object?, Object?> value) =>
      ExecutionProfile(
        tagExpression: _requiredString(value, 'tagExpression'),
        extensions: Map.unmodifiable({
          for (final entry in value.entries)
            if (entry.key is String && entry.key != 'tagExpression')
              entry.key as String: _freeze(entry.value),
        }),
      );
}

/// Typed lock configuration. No default profiles are introduced here:
/// when a `lock:` section is present, `profiles` must be explicit and
/// non-empty (enforced in discovery validation). The four-profile
/// `[pullRequest, merge, release, nightly]` default lives only in onboarding
/// presets (`init_preset.dart`), never in parsing.
final class WorkspaceLockConfig {
  final String? directory;
  final List<String> profiles;
  final bool? requireCleanGeneration;
  final Map<String, Object?> extensions;

  const WorkspaceLockConfig({
    this.directory,
    this.profiles = const [],
    this.requireCleanGeneration,
    this.extensions = const {},
  });

  static const _knownKeys = {'directory', 'profiles', 'requireCleanGeneration'};

  factory WorkspaceLockConfig.fromMap(Map<Object?, Object?> value) {
    final rawDirectory = value['directory'];
    if (rawDirectory != null &&
        (rawDirectory is! String || rawDirectory.trim().isEmpty)) {
      throw const FormatException('lock.directory must be a non-empty string');
    }
    final rawProfiles = value['profiles'];
    if (rawProfiles != null &&
        (rawProfiles is! List ||
            rawProfiles.any(
              (item) => item is! String || item.trim().isEmpty,
            ))) {
      throw const FormatException('lock.profiles must be non-empty strings');
    }
    final rawClean = value['requireCleanGeneration'];
    if (rawClean != null && rawClean is! bool) {
      throw const FormatException(
        'lock.requireCleanGeneration must be boolean',
      );
    }
    return WorkspaceLockConfig(
      directory: rawDirectory as String?,
      profiles: rawProfiles == null
          ? const []
          : List<String>.unmodifiable(rawProfiles as List),
      requireCleanGeneration: rawClean as bool?,
      extensions: Map.unmodifiable({
        for (final entry in value.entries)
          if (entry.key is String && !_knownKeys.contains(entry.key))
            entry.key as String: _freeze(entry.value),
      }),
    );
  }

  Map<String, Object?> toJson() => {
    ...extensions,
    if (directory != null) 'directory': directory,
    if (profiles.isNotEmpty) 'profiles': profiles,
    if (requireCleanGeneration != null)
      'requireCleanGeneration': requireCleanGeneration,
  };
}

/// Typed coverage configuration. Numeric thresholds keep their historical
/// fallbacks (100) at the command layer; this model only validates shape.
final class WorkspaceCoverageConfig {
  final String? input;
  final String? baseline;
  final String? changedSince;
  final double? minimumTotal;
  final double? changedLineMinimum;
  final List<String> includedRoots;
  final Map<String, List<String>> layers;
  final Map<String, Object?> extensions;

  const WorkspaceCoverageConfig({
    this.input,
    this.baseline,
    this.changedSince,
    this.minimumTotal,
    this.changedLineMinimum,
    this.includedRoots = const [],
    this.layers = const {},
    this.extensions = const {},
  });

  static const _knownKeys = {
    'input',
    'baseline',
    'changedSince',
    'includedRoots',
    'minimumTotal',
    'changedLineMinimum',
    'layers',
    'exclusions',
  };

  factory WorkspaceCoverageConfig.fromMap(Map<Object?, Object?> value) {
    for (final key in ['input', 'baseline', 'changedSince']) {
      final raw = value[key];
      if (raw != null && (raw is! String || raw.trim().isEmpty)) {
        throw FormatException('coverage.$key must be a non-empty string');
      }
    }
    double? threshold(String key) {
      final raw = value[key];
      if (raw == null) return null;
      final parsed = raw is num
          ? raw.toDouble()
          : raw is String
          ? double.tryParse(raw)
          : null;
      if (parsed == null || !parsed.isFinite || parsed < 0 || parsed > 100) {
        throw FormatException('coverage.$key must be between 0 and 100');
      }
      return parsed;
    }

    final rawRoots = value['includedRoots'];
    if (rawRoots != null &&
        (rawRoots is! List ||
            rawRoots.any((item) => item is! String || item.isEmpty))) {
      throw const FormatException(
        'coverage.includedRoots must be string values',
      );
    }
    final rawLayers = value['layers'];
    if (rawLayers != null && rawLayers is! Map) {
      throw const FormatException('coverage.layers must be a mapping');
    }
    if (rawLayers is Map) {
      for (final entry in rawLayers.entries) {
        if (entry.key is! String ||
            (entry.key as String).trim().isEmpty ||
            entry.value is! List ||
            (entry.value as List).any(
              (item) => item is! String || item.trim().isEmpty,
            )) {
          throw const FormatException(
            'coverage.layers must map non-empty names to string lists',
          );
        }
      }
    }
    return WorkspaceCoverageConfig(
      input: value['input'] as String?,
      baseline: value['baseline'] as String?,
      changedSince: value['changedSince'] as String?,
      minimumTotal: threshold('minimumTotal'),
      changedLineMinimum: threshold('changedLineMinimum'),
      includedRoots: rawRoots == null
          ? const []
          : List<String>.unmodifiable(rawRoots as List),
      layers: rawLayers == null
          ? const {}
          : Map.unmodifiable({
              for (final entry in (rawLayers as Map).entries)
                entry.key as String: List<String>.unmodifiable(
                  entry.value as List,
                ),
            }),
      extensions: Map.unmodifiable({
        for (final entry in value.entries)
          if (entry.key is String && !_knownKeys.contains(entry.key))
            entry.key as String: _freeze(entry.value),
      }),
    );
  }
}

/// Typed evidence configuration.
final class WorkspaceEvidenceConfig {
  final String? output;
  final String? records;
  final String? observations;
  final bool? includeSourceCode;
  final Map<String, String> types;
  final Map<String, Object?> extensions;

  const WorkspaceEvidenceConfig({
    this.output,
    this.records,
    this.observations,
    this.includeSourceCode,
    this.types = const {},
    this.extensions = const {},
  });

  static const _knownKeys = {
    'output',
    'records',
    'observations',
    'includeSourceCode',
    'types',
  };

  factory WorkspaceEvidenceConfig.fromMap(Map<Object?, Object?> value) {
    for (final key in ['output', 'records', 'observations']) {
      final raw = value[key];
      if (raw != null && (raw is! String || raw.trim().isEmpty)) {
        throw FormatException('evidence.$key must be a non-empty string');
      }
    }
    final rawInclude = value['includeSourceCode'];
    if (rawInclude != null && rawInclude is! bool) {
      throw const FormatException('evidence.includeSourceCode must be boolean');
    }
    const allowedModes = {
      'record',
      'scenario-record',
      'control-backed',
      'attestation',
    };
    final types = <String, String>{};
    final rawTypes = value['types'];
    if (rawTypes != null) {
      if (rawTypes is! Map) {
        throw const FormatException('evidence.types must be a mapping');
      }
      for (final entry in rawTypes.entries) {
        final mode = entry.value is Map ? (entry.value as Map)['mode'] : null;
        if (entry.key is! String ||
            mode is! String ||
            !allowedModes.contains(mode)) {
          throw FormatException(
            'evidence type ${entry.key} has an unsupported mode',
          );
        }
        types[entry.key as String] = mode;
      }
    }
    return WorkspaceEvidenceConfig(
      output: value['output'] as String?,
      records: value['records'] as String?,
      observations: value['observations'] as String?,
      includeSourceCode: rawInclude as bool?,
      types: Map.unmodifiable(types),
      extensions: Map.unmodifiable({
        for (final entry in value.entries)
          if (entry.key is String && !_knownKeys.contains(entry.key))
            entry.key as String: _freeze(entry.value),
      }),
    );
  }
}

/// Typed Dart tooling configuration. Shape validation for nested sections
/// stays in discovery; this model retains the validated maps plus unknown
/// fields for forward compatibility.
final class WorkspaceDartToolingConfig {
  final Map<String, Object?> extraction;
  final Map<String, Object?> analyzerPlugin;
  final Map<String, Object?> buildHooks;
  final Map<String, Object?> generation;
  final Map<String, Object?> extensions;

  const WorkspaceDartToolingConfig({
    this.extraction = const {},
    this.analyzerPlugin = const {},
    this.buildHooks = const {},
    this.generation = const {},
    this.extensions = const {},
  });

  static const _knownKeys = {
    'extraction',
    'analyzerPlugin',
    'buildHooks',
    'generation',
  };

  factory WorkspaceDartToolingConfig.fromMap(Map<Object?, Object?> value) {
    Map<String, Object?> section(String key) {
      final raw = value[key];
      if (raw == null) return const {};
      if (raw is! Map) {
        throw FormatException('dartTooling.$key must be a mapping');
      }
      return Map.unmodifiable({
        for (final e in raw.entries) '${e.key}': _freeze(e.value),
      });
    }

    return WorkspaceDartToolingConfig(
      extraction: section('extraction'),
      analyzerPlugin: section('analyzerPlugin'),
      buildHooks: section('buildHooks'),
      generation: section('generation'),
      extensions: Map.unmodifiable({
        for (final entry in value.entries)
          if (entry.key is String && !_knownKeys.contains(entry.key))
            entry.key as String: _freeze(entry.value),
      }),
    );
  }
}

String _requiredString(Map<Object?, Object?> value, String key) {
  final candidate = value[key];
  if (candidate is! String || candidate.trim().isEmpty) {
    throw FormatException('requires non-empty $key');
  }
  return candidate;
}

List<String> _requiredStrings(Map<Object?, Object?> value, String key) {
  final candidate = value[key];
  if (candidate is! List ||
      candidate.any((item) => item is! String || item.trim().isEmpty)) {
    throw FormatException('requires non-empty string $key');
  }
  return List<String>.unmodifiable(candidate);
}

Object? _freeze(Object? value) => switch (value) {
  Map value => Map.unmodifiable(
    value.map((key, item) => MapEntry(key, _freeze(item))),
  ),
  List value => List.unmodifiable(value.map(_freeze)),
  _ => value,
};
