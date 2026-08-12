import 'dart:io';
import 'package:glob/glob.dart';
import 'package:file/local.dart';
import 'package:yaml/yaml.dart';
import 'types.dart';
import 'gherkin_parser.dart';
import 'metadata_extractor.dart';

/// Workspace configuration loaded from `zuke.yaml`.
class ZukeConfig {
  /// Configuration schema. Current consumers should use schema 3.
  final int schemaVersion;

  /// Workspace root override.
  final String? root;

  /// Feature input glob patterns.
  final List<String> featurePatterns;

  /// Epic input glob patterns.
  final List<String> epicPatterns;

  /// Control input glob patterns.
  final List<String> controlPatterns;

  /// Registry input glob patterns.
  final List<String> registryPatterns;

  /// Project policy path.
  final String? projectPolicy;

  /// Named policy preset.
  final String? preset;

  /// Profile selection patterns.
  final List<String> profilePatterns;

  /// Target-specific configuration.
  final Map<String, dynamic> targetsConfig;

  /// Generated contract output path.
  final String? contractOutput;

  /// Generated contract export path.
  final String? contractExport;

  /// Specification lock path.
  final String? lockFile;

  /// Evidence output path.
  final String? evidenceOutput;

  /// Trust bundle path.
  final String? trustBundle;

  /// Runner execution configuration.
  final Map<String, dynamic> executionConfig;

  /// V3 stable package identities grouped by target.
  final Map<String, List<Map<String, dynamic>>> targetPackages;

  /// Current framework selection grouped by target.
  final Map<String, String> targetFrameworks;

  /// Current registered evidence types and their satisfaction modes.
  final Map<String, String> evidenceTypes;

  /// V3 lock directory and official profile names.
  final String? lockDirectory;
  final List<String> lockProfiles;

  /// Creates workspace configuration.
  const ZukeConfig({
    this.schemaVersion = 3,
    this.root,
    this.featurePatterns = const ['specs/features/**/*.feature'],
    this.epicPatterns = const ['specs/epics/**/*.yaml'],
    this.controlPatterns = const ['specs/controls/**/*.yaml'],
    this.registryPatterns = const ['specs/registry/**/*.yaml'],
    this.projectPolicy,
    this.preset,
    this.profilePatterns = const [],
    this.targetsConfig = const {},
    this.contractOutput,
    this.contractExport,
    this.lockFile,
    this.evidenceOutput,
    this.trustBundle,
    this.executionConfig = const {},
    this.targetPackages = const {},
    this.targetFrameworks = const {},
    this.evidenceTypes = const {},
    this.lockDirectory,
    this.lockProfiles = const [],
  });

  /// Parses [yamlContent] into workspace configuration.
  static ZukeConfig fromYaml(String yamlContent, {String? root}) {
    final doc = loadYaml(yamlContent) as Map?;
    if (doc == null) {
      throw const FormatException(
        'zuke.yaml must contain a mapping with schemaVersion: 3',
      );
    }

    final schemaVersion = doc['schemaVersion'] is int
        ? doc['schemaVersion'] as int
        : 2;
    if (schemaVersion != 3) {
      throw const FormatException(
        'Only current Zuke schemaVersion 3 configuration is supported; see docs/migration.md.',
      );
    }

    final specs = doc['specifications'] as Map? ?? {};
    final policies = doc['policies'] as Map? ?? {};

    List<String>? profiles;
    final profilesRaw = policies['profiles'];
    if (profilesRaw is List) profiles = profilesRaw.cast<String>();

    final rawTargetsValue = doc['targets'];
    if (rawTargetsValue != null && rawTargetsValue is! Map) {
      throw const FormatException('targets must be a mapping');
    }
    final rawTargets = rawTargetsValue as Map? ?? {};
    final targetsConfig = <String, dynamic>{};
    for (final key in rawTargets.keys) {
      targetsConfig[key.toString()] = rawTargets[key];
    }

    final lockSection = doc['lock'] as Map? ?? {};
    final evidenceSection = doc['evidence'] as Map? ?? {};
    final trustSection = doc['trust'] as Map? ?? {};
    final rawExecutionValue = doc['execution'];
    if (rawExecutionValue != null && rawExecutionValue is! Map) {
      throw const FormatException('execution must be a mapping');
    }
    final rawExecution = rawExecutionValue is Map
        ? Map<String, dynamic>.from(rawExecutionValue)
        : const <String, dynamic>{};
    final targetPackages = <String, List<Map<String, dynamic>>>{};
    final targetFrameworks = <String, String>{};
    for (final entry in targetsConfig.entries) {
      final value = entry.value;
      if (value is Map) {
        final framework = value['framework'];
        if (framework is String && framework.isNotEmpty) {
          targetFrameworks[entry.key] = framework;
        }
        final packages = value['packages'];
        if (packages is List) {
          targetPackages[entry.key] = packages
              .whereType<Map>()
              .map((package) => Map<String, dynamic>.from(package))
              .toList();
        }
      }
    }
    final evidenceTypes = <String, String>{};
    final rawEvidenceTypes = evidenceSection['types'];
    if (rawEvidenceTypes is Map) {
      for (final entry in rawEvidenceTypes.entries) {
        final value = entry.value;
        final mode = value is Map ? value['mode'] : null;
        if (entry.key is String && mode is String) {
          evidenceTypes[entry.key as String] = mode;
        }
      }
    }
    final lockProfiles = (lockSection['profiles'] is List)
        ? (lockSection['profiles'] as List).whereType<String>().toList()
        : const <String>[];

    _validateV3(
      rawTargets,
      rawExecution,
      evidenceSection,
      lockSection,
      targetPackages,
      targetFrameworks,
      lockProfiles,
    );

    return ZukeConfig(
      schemaVersion: schemaVersion,
      root: root,
      featurePatterns:
          _stringList(specs['features']) ?? ['specs/features/**/*.feature'],
      epicPatterns: _stringList(specs['epics']) ?? ['specs/epics/**/*.yaml'],
      controlPatterns:
          _stringList(specs['controls']) ?? ['specs/controls/**/*.yaml'],
      registryPatterns:
          _stringList(specs['registries']) ?? ['specs/registry/**/*.yaml'],
      projectPolicy: policies['project'] as String?,
      preset: policies['preset'] as String?,
      profilePatterns: profiles ?? [],
      targetsConfig: targetsConfig,
      contractOutput: rawTargets['flutter'] is Map
          ? (rawTargets['flutter'] as Map)['contractOutput'] as String?
          : null,
      contractExport: rawTargets['flutter'] is Map
          ? (rawTargets['flutter'] as Map)['contractExport'] as String?
          : null,
      lockFile: lockSection['file'] as String?,
      evidenceOutput: evidenceSection['output'] as String?,
      trustBundle: trustSection['bundle'] as String?,
      executionConfig: rawExecution,
      targetPackages: targetPackages,
      targetFrameworks: targetFrameworks,
      evidenceTypes: evidenceTypes,
      lockDirectory: lockSection['directory'] as String?,
      lockProfiles: lockProfiles,
    );
  }

  static void _validateV3(
    Map targets,
    Map<String, dynamic> execution,
    Map evidence,
    Map lock,
    Map<String, List<Map<String, dynamic>>> targetPackages,
    Map<String, String> targetFrameworks,
    List<String> lockProfiles,
  ) {
    for (final entry in targets.entries) {
      final targetId = entry.key.toString();
      final target = entry.value;
      if (target is! Map) {
        throw FormatException('target $targetId must be a mapping');
      }
      String requiredTargetString(String key) {
        final value = target[key];
        if (value is! String || value.trim().isEmpty) {
          throw FormatException('target $targetId requires non-empty $key');
        }
        return value;
      }

      requiredTargetString('language');
      requiredTargetString('framework');
      final packages = target['packages'];
      if (packages is! List || packages.isEmpty) {
        throw FormatException(
          'target $targetId requires a non-empty packages list',
        );
      }
      final ids = <String>{};
      for (final item in packages) {
        if (item is! Map) {
          throw FormatException('target $targetId package must be a mapping');
        }
        final id = item['id'];
        final path = item['path'];
        final roots = item['roots'];
        if (id is! String || id.trim().isEmpty || !ids.add(id)) {
          throw FormatException(
            'target $targetId packages require unique non-empty id values',
          );
        }
        if (path is! String || path.trim().isEmpty) {
          throw FormatException(
            'target $targetId package $id requires a non-empty path',
          );
        }
        if (roots is! List ||
            roots.any((root) => root is! String || root.isEmpty)) {
          throw FormatException(
            'target $targetId package $id requires string roots',
          );
        }
      }
    }
    if (targetPackages.length != targets.length ||
        targetFrameworks.length != targets.length) {
      throw const FormatException(
        'Current targets must declare stable package and framework identities',
      );
    }

    final runners = execution['runners'];
    if (runners != null) {
      if (runners is! List) {
        throw const FormatException('execution.runners must be a list');
      }
      for (final item in runners) {
        if (item is! Map) {
          throw const FormatException('execution runner must be a mapping');
        }
        final id = item['id'];
        if (id is! String || id.trim().isEmpty) {
          throw const FormatException(
            'execution runner requires a non-empty id',
          );
        }
        for (final key in [
          'target',
          'sourcePackage',
          'sourceAdapter',
          'sourceCompatibilityId',
        ]) {
          final value = item[key];
          if (value is! String || value.trim().isEmpty) {
            throw FormatException('runner $id requires non-empty $key');
          }
        }
        final target = item['target'] as String;
        final sourcePackage = item['sourcePackage'] as String;
        final packages = targetPackages[target];
        if (packages == null ||
            !packages.any((package) => package['id'] == sourcePackage)) {
          throw FormatException(
            'runner $id sourcePackage $sourcePackage is not in target $target',
          );
        }
        final evidenceTypes = item['evidenceTypes'];
        if (evidenceTypes != null &&
            (evidenceTypes is! List ||
                evidenceTypes.any((type) => type is! String || type.isEmpty))) {
          throw FormatException(
            'runner $id evidenceTypes must be string values',
          );
        }
      }
    }

    final rawEvidenceTypes = evidence['types'];
    if (rawEvidenceTypes != null) {
      if (rawEvidenceTypes is! Map) {
        throw const FormatException('evidence.types must be a mapping');
      }
      for (final entry in rawEvidenceTypes.entries) {
        final value = entry.value;
        if (value is! Map ||
            value['mode'] is! String ||
            !const {
              'record',
              'scenario-record',
              'control-backed',
              'attestation',
            }.contains(value['mode'])) {
          throw FormatException(
            'evidence type ${entry.key} has an unsupported mode',
          );
        }
      }
    }

    // Minimal programmatic/configuration fixtures are useful to commands that
    // do not read or write locks. Enforce the current lock shape when a lock
    // section is present.
    if (lock.isEmpty) return;
    if (lock.containsKey('file')) {
      throw const FormatException(
        'Current lock configuration must not use lock.file; use the official profile lock directory',
      );
    }
    final directory = lock['directory'];
    if (directory is! String ||
        directory.replaceAll('\\', '/') != 'assurance/locks' ||
        lockProfiles.isEmpty) {
      throw const FormatException(
        'Current lock configuration requires directory assurance/locks and non-empty profiles',
      );
    }
    if (lockProfiles.toSet().length != lockProfiles.length ||
        lockProfiles.any((profile) => profile.trim().isEmpty)) {
      throw const FormatException(
        'Current lock profiles must be unique non-empty strings',
      );
    }
  }

  static List<String>? _stringList(dynamic value) {
    if (value is List) return value.cast<String>();
    return null;
  }
}

/// Parsed workspace data and the inputs used to produce it.
class WorkspaceDiscoveryResult {
  /// Effective workspace configuration.
  final ZukeConfig config;

  /// Extracted metadata and registry data.
  final MetadataExtractorResult data;

  /// Original contents of discovered input files.
  final Map<String, String> inputContents;

  /// Configured workspace-relative patterns that define specification inputs.
  final List<String> inputPatterns;

  /// Files matched from [inputPatterns], excluding `zuke.yaml` itself.
  final Set<String> patternInputPaths;

  const WorkspaceDiscoveryResult({
    required this.config,
    required this.data,
    this.inputContents = const {},
    this.inputPatterns = const [],
    this.patternInputPaths = const {},
  });
}

/// Discovers and parses a Zuke workspace from disk.
class WorkspaceDiscovery {
  /// Discovers the workspace rooted at [rootPath].
  WorkspaceDiscoveryResult discover(String? rootPath) {
    T measureGlob<T>(T Function() action) {
      return action();
    }

    T measureParse<T>(T Function() action) {
      return action();
    }

    final requestedRoot = rootPath ?? Directory.current.path;
    late final String root;
    try {
      root = Directory(requestedRoot).resolveSymbolicLinksSync();
    } catch (_) {
      root = Directory(requestedRoot).absolute.path;
    }
    final workspacePrefix = root.replaceAll('\\', '/').toLowerCase();

    final configPath = '$root/zuke.yaml';
    final inputContents = <String, String>{};
    final configFile = File(configPath);
    ZukeConfig config;
    String? configurationError;
    try {
      final configContent = configFile.readAsStringSync();
      inputContents[configFile.path] = configContent;
      config = ZukeConfig.fromYaml(configContent, root: root);
    } catch (error) {
      config = ZukeConfig(root: root);
      configurationError = '$error';
      // Never bypass current-schema validation after a configuration error.
    }

    final errors = <String>[];
    if (configurationError != null) {
      errors.add('${configFile.path}: $configurationError');
    }
    final seenPhysicalPaths = <String, List<String>>{};

    // Parse features
    final parser = GherkinParser();
    final features = <ParsedFeature>[];
    for (final pattern in config.featurePatterns) {
      _checkPatternSafety(pattern, errors);
      final files = measureGlob(
        () => _matchGlob(pattern, root, workspacePrefix: workspacePrefix),
      );
      if (files.isEmpty) {
        errors.add('Feature pattern "$pattern" matched no files');
      }
      for (final f in files) {
        _trackOverlap(f, pattern, seenPhysicalPaths, errors);
        try {
          final (content, result) = measureParse(() {
            final fileContent = File(f).readAsStringSync();
            final parseRes = parser.parseFile(fileContent, f);
            return (fileContent, parseRes);
          });
          inputContents[File(f).path] = content;
          features.addAll(result.features);
          for (final e in result.errors) {
            errors.add('${e.source.file}:${e.source.line}: ${e.message}');
          }
        } catch (e) {
          errors.add('$f: parse failed: $e');
        }
      }
    }

    // Load YAML data
    final epics = <String, Map<String, dynamic>>{};
    for (final pattern in config.epicPatterns) {
      _checkPatternSafety(pattern, errors);
      _loadYamlMap(
        pattern,
        root,
        epics,
        errors,
        seenPhysicalPaths,
        measureGlob: measureGlob,
        measureParse: measureParse,
        workspacePrefix: workspacePrefix,
        inputContents: inputContents,
      );
    }
    final controls = <String, Map<String, dynamic>>{};
    for (final pattern in config.controlPatterns) {
      _checkPatternSafety(pattern, errors);
      _loadYamlListItems(
        pattern,
        root,
        'controls',
        controls,
        errors,
        seenPhysicalPaths,
        measureGlob: measureGlob,
        measureParse: measureParse,
        workspacePrefix: workspacePrefix,
        inputContents: inputContents,
      );
    }
    final registries = <String, Map<String, dynamic>>{};
    for (final pattern in config.registryPatterns) {
      _checkPatternSafety(pattern, errors);
      _loadRegistries(
        pattern,
        root,
        registries,
        errors,
        seenPhysicalPaths,
        measureGlob: measureGlob,
        measureParse: measureParse,
        workspacePrefix: workspacePrefix,
        inputContents: inputContents,
      );
    }
    final policies = <String, Map<String, dynamic>>{};
    if (config.projectPolicy != null) {
      _checkPatternSafety(config.projectPolicy!, errors);
      final files = measureGlob(
        () => _matchGlob(
          config.projectPolicy!,
          root,
          workspacePrefix: workspacePrefix,
        ),
      );
      for (final f in files) {
        _trackOverlap(f, config.projectPolicy!, seenPhysicalPaths, errors);
        measureParse(() {
          _loadPolicyFile(f, policies, errors, inputContents: inputContents);
        });
      }
      if (files.isEmpty) {
        errors.add('Project policy "${config.projectPolicy}" matched no files');
      }
    }
    for (final pattern in config.profilePatterns) {
      _checkPatternSafety(pattern, errors);
      final files = measureGlob(
        () => _matchGlob(pattern, root, workspacePrefix: workspacePrefix),
      );
      for (final f in files) {
        _trackOverlap(f, pattern, seenPhysicalPaths, errors);
        measureParse(() {
          _loadPolicyFile(f, policies, errors, inputContents: inputContents);
        });
      }
    }

    _validateEvidenceRequirements(config, features, errors);

    final inputPatterns = <String>{
      ...config.featurePatterns,
      ...config.epicPatterns,
      ...config.controlPatterns,
      ...config.registryPatterns,
      if (config.projectPolicy != null) config.projectPolicy!,
      ...config.profilePatterns,
    }.toList()..sort();
    final patternInputPaths = inputContents.keys
        .where((path) => path != configFile.path)
        .toSet();

    return WorkspaceDiscoveryResult(
      config: config,
      data: MetadataExtractorResult(
        features: features,
        epics: epics,
        controls: controls,
        registries: registries,
        policies: policies,
        errors: errors,
      ),
      inputContents: Map.unmodifiable(inputContents),
      inputPatterns: List.unmodifiable(inputPatterns),
      patternInputPaths: Set.unmodifiable(patternInputPaths),
    );
  }

  void _validateEvidenceRequirements(
    ZukeConfig config,
    List<ParsedFeature> features,
    List<String> errors,
  ) {
    final runners = (config.executionConfig['runners'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    for (final feature in features) {
      for (final rule in feature.rules) {
        final declared = rule.metadata.requiredEvidence ?? const <String>[];
        final slots = rule.metadata.evidenceRequirements ?? const [];
        if (declared.length != slots.length) {
          errors.add(
            '${rule.metadata.id ?? rule.ruleElement.title}: V3 requiredEvidence entries '
            'must be typed maps with target, sourcePackage, sourceAdapter, '
            'and variant',
          );
          continue;
        }
        for (final slot in slots) {
          final type = slot['type'] ?? slot['evidenceType'];
          final target = slot['target'];
          final sourcePackage = slot['sourcePackage'];
          final sourceAdapter = slot['sourceAdapter'];
          final variant = slot['variant'];
          if ([
            type,
            target,
            sourcePackage,
            sourceAdapter,
            variant,
          ].any((value) => value == null || value.isEmpty)) {
            errors.add(
              '${rule.metadata.id ?? rule.ruleElement.title}: incomplete V3 evidence slot',
            );
            continue;
          }
          if (!config.evidenceTypes.containsKey(type)) {
            errors.add(
              '${rule.metadata.id ?? rule.ruleElement.title}: unknown evidence type $type',
            );
          }
          final packageConfigured =
              config.targetPackages[target]?.any(
                (package) => package['id'] == sourcePackage,
              ) ??
              false;
          if (!packageConfigured) {
            errors.add(
              '${rule.metadata.id ?? rule.ruleElement.title}: source package '
              '$sourcePackage is not configured for target $target',
            );
          }
          final runnerConfigured = runners.any((runner) {
            final types = (runner['evidenceTypes'] as List? ?? const [])
                .whereType<String>();
            return runner['target'] == target &&
                runner['sourcePackage'] == sourcePackage &&
                runner['sourceAdapter'] == sourceAdapter &&
                types.contains(type);
          });
          if (!runnerConfigured) {
            errors.add(
              '${rule.metadata.id ?? rule.ruleElement.title}: no runner is configured '
              'for evidence slot $type/$target/$sourcePackage/$sourceAdapter',
            );
          }
        }
      }
    }
  }

  /// Reject patterns that can escape the workspace root.
  void _checkPatternSafety(String pattern, List<String> errors) {
    final normalized = pattern.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        normalized.startsWith('//') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
        normalized.startsWith('../') ||
        normalized.contains('/../') ||
        normalized.startsWith('..\\') ||
        normalized.contains('\\..\\')) {
      errors.add('Path escapes workspace root: "$pattern"');
    }
  }

  /// Track which pattern matched a file; report overlaps.
  void _trackOverlap(
    String filePath,
    String pattern,
    Map<String, List<String>> seen,
    List<String> errors,
  ) {
    try {
      final isLink = FileSystemEntity.isLinkSync(filePath);
      final resolved = isLink
          ? File(filePath).resolveSymbolicLinksSync()
          : filePath;
      final existing = seen[resolved];
      if (existing != null && !existing.contains(pattern)) {
        existing.add(pattern);
        errors.add(
          'File "$filePath" matched by multiple patterns: ${existing.join(", ")}',
        );
      } else if (existing == null) {
        seen[resolved] = [pattern];
      }
    } catch (_) {
      final existing = seen[filePath];
      if (existing != null && !existing.contains(pattern)) {
        existing.add(pattern);
      } else if (existing == null) {
        seen[filePath] = [pattern];
      }
    }
  }

  /// Match files using glob-like semantics. Supports:
  /// - Exact file paths (no wildcards)
  /// - `specs/**/*.ext` (recursive extension match under a base)
  /// - `specs/*/file.ext` (single-level wildcard)
  List<String> _matchGlob(
    String pattern,
    String root, {
    String? resolvedWorkspace,
    String? workspacePrefix,
  }) {
    final normalized = pattern.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        normalized.startsWith('//') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
        normalized.startsWith('../') ||
        normalized.contains('/../')) {
      return const [];
    }
    final workspace =
        resolvedWorkspace ?? Directory(root).resolveSymbolicLinksSync();
    final prefix =
        workspacePrefix ?? workspace.replaceAll('\\', '/').toLowerCase();
    final globPatterns = [normalized];
    if (normalized.contains('/**/')) {
      globPatterns.add(normalized.replaceAll('/**/', '/'));
    }
    final resultsSet = <String>{};
    for (final globPattern in globPatterns) {
      for (final entity in Glob(globPattern).listFileSystemSync(
        const LocalFileSystem(),
        root: root,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        try {
          final isLink = FileSystemEntity.isLinkSync(entity.path);
          final physical = isLink
              ? entity.resolveSymbolicLinksSync()
              : entity.path;
          final canonical = physical.replaceAll('\\', '/').toLowerCase();
          if (canonical != prefix && !canonical.startsWith('$prefix/')) {
            // A symlink that escapes the workspace is never a specification
            // input, even if its lexical path appeared below the workspace.
            continue;
          }
          resultsSet.add(entity.path);
        } on FileSystemException {
          // Broken links and unresolvable files are not valid inputs.
        }
      }
    }
    final results = resultsSet.toList();
    results.sort(
      (a, b) => a.replaceAll('\\', '/').compareTo(b.replaceAll('\\', '/')),
    );
    return results;
  }

  void _loadYamlMap(
    String pattern,
    String root,
    Map<String, Map<String, dynamic>> out,
    List<String> errors,
    Map<String, List<String>> seen, {
    T Function<T>(T Function() action)? measureGlob,
    T Function<T>(T Function() action)? measureParse,
    String? workspacePrefix,
    Map<String, String>? inputContents,
  }) {
    final files = measureGlob != null
        ? measureGlob(
            () => _matchGlob(pattern, root, workspacePrefix: workspacePrefix),
          )
        : _matchGlob(pattern, root, workspacePrefix: workspacePrefix);
    for (final f in files) {
      _trackOverlap(f, pattern, seen, errors);
      try {
        final (content, data) = measureParse != null
            ? measureParse(() {
                final fileContent = File(f).readAsStringSync();
                final yamlData = loadYaml(fileContent);
                return (fileContent, yamlData);
              })
            : (() {
                final fileContent = File(f).readAsStringSync();
                return (fileContent, loadYaml(fileContent));
              })();
        inputContents?[f] = content;
        if (data is Map && data['id'] is String) {
          final id = data['id'] as String;
          if (out.containsKey(id)) {
            errors.add(
              'Duplicate ${_kindForId(id)} ID "$id" (${out[id]!['_file'] ?? "?"}, $f)',
            );
          }
          final entry = Map<String, dynamic>.from(data);
          entry['_file'] = f;
          out[id] = entry;
        }
      } catch (e) {
        errors.add('$f: Failed to parse YAML: $e');
      }
    }
  }

  void _loadYamlListItems(
    String pattern,
    String root,
    String listKey,
    Map<String, Map<String, dynamic>> out,
    List<String> errors,
    Map<String, List<String>> seen, {
    T Function<T>(T Function() action)? measureGlob,
    T Function<T>(T Function() action)? measureParse,
    String? workspacePrefix,
    Map<String, String>? inputContents,
  }) {
    final files = measureGlob != null
        ? measureGlob(
            () => _matchGlob(pattern, root, workspacePrefix: workspacePrefix),
          )
        : _matchGlob(pattern, root, workspacePrefix: workspacePrefix);
    for (final f in files) {
      _trackOverlap(f, pattern, seen, errors);
      try {
        final (content, data) = measureParse != null
            ? measureParse(() {
                final fileContent = File(f).readAsStringSync();
                final yamlData = loadYaml(fileContent);
                return (fileContent, yamlData);
              })
            : (() {
                final fileContent = File(f).readAsStringSync();
                return (fileContent, loadYaml(fileContent));
              })();
        inputContents?[f] = content;
        if (data is Map) {
          final items = data[listKey];
          if (items is List) {
            for (final item in items) {
              if (item is Map && item['id'] is String) {
                final id = item['id'] as String;
                if (out.containsKey(id)) {
                  errors.add('Duplicate ${_kindForId(id)} ID "$id"');
                }
                final entry = Map<String, dynamic>.from(item);
                entry['_file'] = f;
                entry['_sourceList'] = listKey;
                out[id] = entry;
              }
            }
          }
        }
      } catch (e) {
        errors.add('$f: Failed to parse YAML: $e');
      }
    }
  }

  void _loadRegistries(
    String pattern,
    String root,
    Map<String, Map<String, dynamic>> out,
    List<String> errors,
    Map<String, List<String>> seen, {
    T Function<T>(T Function() action)? measureGlob,
    T Function<T>(T Function() action)? measureParse,
    String? workspacePrefix,
    Map<String, String>? inputContents,
  }) {
    final files = measureGlob != null
        ? measureGlob(
            () => _matchGlob(pattern, root, workspacePrefix: workspacePrefix),
          )
        : _matchGlob(pattern, root, workspacePrefix: workspacePrefix);
    for (final f in files) {
      _trackOverlap(f, pattern, seen, errors);
      try {
        final (content, data) = measureParse != null
            ? measureParse(() {
                final fileContent = File(f).readAsStringSync();
                final yamlData = loadYaml(fileContent);
                return (fileContent, yamlData);
              })
            : (() {
                final fileContent = File(f).readAsStringSync();
                return (fileContent, loadYaml(fileContent));
              })();
        inputContents?[f] = content;
        if (data is Map) {
          if (data.containsKey('version')) {
            errors.add(
              '$f: Legacy "version:" key is unsupported in registry YAML; use "schemaVersion: 1"',
            );
            continue;
          }
          final schemaVer = data['schemaVersion'];
          if (schemaVer != 1 && schemaVer != '1') {
            errors.add('$f: Registry YAML must specify "schemaVersion: 1"');
            continue;
          }
          for (final key in [
            'endpoints',
            'events',
            'featureFlags',
            'pbis',
            'performanceProfiles',
            'retiredIds',
          ]) {
            final items = data[key];
            if (items == null) continue;
            if (items is! List) {
              errors.add('$f: Registry "$key" must be a list');
              continue;
            }
            if (key == 'retiredIds') {
              for (var index = 0; index < items.length; index++) {
                final item = items[index];
                if (item is! String ||
                    item.trim().isEmpty ||
                    item != item.trim()) {
                  errors.add(
                    '$f: retiredIds entry at index $index must be a non-empty string without surrounding whitespace',
                  );
                  continue;
                }
                out['retired:$item'] = {
                  'id': item,
                  '_file': f,
                  '_kind': 'retired',
                };
              }
              continue;
            }
            final requiredFields = _registryRequiredFields[key] ?? const [];
            for (var index = 0; index < items.length; index++) {
              final item = items[index];
              if (item is! Map) {
                errors.add('$f: $key entry at index $index must be a mapping');
                continue;
              }
              final id = item['id'];
              if (id is! String || id.trim().isEmpty || id != id.trim()) {
                errors.add(
                  '$f: $key entry at index $index is missing required field "id" (must be non-empty and trimmed)',
                );
                continue;
              }
              var valid = true;
              for (final reqField in requiredFields) {
                final value = item[reqField];
                if (value is! String || value.trim().isEmpty) {
                  errors.add(
                    '$f: $key entry "$id" is missing required field "$reqField"',
                  );
                  valid = false;
                }
              }
              if (!valid) continue;
              if (out.containsKey(id)) {
                errors.add('Duplicate registry entry "$id"');
                continue;
              }
              final entry = Map<String, dynamic>.from(item);
              entry['_file'] = f;
              entry['_sourceList'] = key;
              out[id] = entry;
            }
          }
        }
      } catch (e) {
        errors.add('$f: Failed to parse YAML: $e');
      }
    }
  }

  void _loadPolicyFile(
    String f,
    Map<String, Map<String, dynamic>> out,
    List<String> errors, {
    Map<String, String>? inputContents,
  }) {
    try {
      final content = File(f).readAsStringSync();
      inputContents?[f] = content;
      final data = loadYaml(content);
      if (data is Map) {
        out[f] = Map<String, dynamic>.from(data);
      }
    } catch (e) {
      errors.add('$f: Failed to parse YAML: $e');
    }
  }

  static const _registryRequiredFields = <String, List<String>>{
    'endpoints': ['id', 'target', 'method'],
    'events': ['id'],
    'featureFlags': ['id'],
    'pbis': ['id', 'title', 'owner', 'feature', 'status'],
    'performanceProfiles': ['id'],
  };

  String _kindForId(String id) {
    if (id.startsWith('EPIC-')) return 'Epic';
    if (id.startsWith('FEAT-')) return 'Feature';
    if (id.startsWith('PBI-')) return 'PBI';
    if (id.startsWith('RULE-')) return 'Rule';
    if (id.startsWith('SCN-')) return 'Scenario';
    if (id.startsWith('CTRL-')) return 'Control';
    if (id.startsWith('PERF-')) return 'Performance';
    return 'ID';
  }
}
