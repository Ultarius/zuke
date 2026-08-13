/// The typed portion of workspace configuration used by execution and source
/// identity code. The broader specification model intentionally stays
/// unchanged; these values replace Map scraping on package/runner paths.
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
  });

  factory WorkspaceRunner.fromMap(Map<Object?, Object?> value) {
    final rawArgs = value['args'];
    final rawEvidenceTypes = value['evidenceTypes'];
    if (rawArgs != null &&
        (rawArgs is! List || rawArgs.any((item) => item is! String))) {
      throw const FormatException('runner args must be string values');
    }
    if (rawEvidenceTypes != null &&
        (rawEvidenceTypes is! List ||
            rawEvidenceTypes.any((item) => item is! String))) {
      throw const FormatException('runner evidenceTypes must be string values');
    }
    final executable = value['executable'];
    if (executable != null && executable is! String) {
      throw const FormatException('runner executable must be a string');
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
          : (rawArgs as List).whereType<String>().toList(),
      evidenceTypes: rawEvidenceTypes == null
          ? const []
          : (rawEvidenceTypes as List).whereType<String>().toList(),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'target': target,
    'sourcePackage': sourcePackage,
    'sourceAdapter': sourceAdapter,
    'sourceCompatibilityId': sourceCompatibilityId,
    'runnerCompatibilityId': runnerCompatibilityId,
    if (executable != null) 'executable': executable,
    if (args.isNotEmpty) 'args': args,
    if (evidenceTypes.isNotEmpty) 'evidenceTypes': evidenceTypes,
  };
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
  return candidate.cast<String>();
}
