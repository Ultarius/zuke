import 'dart:io';

import 'package:yaml/yaml.dart';

/// Checks public documentation, active SDK manifests, and retired identities.
void main() {
  final failures = DocumentationChecker(Directory.current).check();
  if (failures.isEmpty) return;
  stderr.writeln('Documentation and release-surface checks failed:');
  for (final failure in failures) {
    stderr.writeln('- $failure');
  }
  exitCode = 1;
}

class DocumentationChecker {
  DocumentationChecker(Directory root) : root = root.absolute;

  final Directory root;

  static const _retiredDirectories = {
    'vendor-sdk/spec_runtime/',
    'vendor-sdk/spec_runner_http/',
    'vendor-sdk/dart_inspection/',
    'vendor-sdk/spec_cli/',
  };
  static const _retiredPatterns = [
    'spec_cli',
    'dart_inspection',
    'spec_runtime',
    'spec_runner_http',
    'vendor-sdk/spec_cli/bin',
    '--root calculator-product',
  ];
  List<String> check() {
    final failures = <String>[];
    final activePackages = _activePackages(failures);
    final matrix = _releaseMatrix(failures);
    _checkLinks(failures);
    _checkRetiredIdentities(failures);
    _checkRawScenarioIds(failures);
    _checkGuideFences(failures);
    _checkActivePubspecs(activePackages, matrix, failures);
    _checkPackageImportsAndCycles(activePackages, matrix, failures);
    _checkReadmeTiers(activePackages, matrix, failures);
    _checkRetiredPackages(matrix, failures);
    _checkLockDocumentation(failures);
    _checkCurrentProductLanguage(failures);
    return failures;
  }

  _ReleaseMatrix _releaseMatrix(List<String> failures) {
    final file = File(
      '${root.path}${Platform.pathSeparator}docs${Platform.pathSeparator}release-matrix.yaml',
    );
    if (!file.existsSync()) {
      failures.add('missing docs/release-matrix.yaml');
      return const _ReleaseMatrix.empty();
    }
    try {
      final decoded = loadYaml(file.readAsStringSync());
      if (decoded is! Map || decoded['schemaVersion'] != 2) {
        throw const FormatException('release matrix schemaVersion must be 2');
      }
      final rawPackages = decoded['packages'];
      if (rawPackages is! Map) {
        throw const FormatException('release matrix packages must be a mapping');
      }
      final packages = <String, _PackageRelease>{};
      for (final entry in rawPackages.entries) {
        final name = entry.key.toString();
        final value = entry.value;
        if (value is! Map) {
          throw FormatException('$name release entry must be a mapping');
        }
        const allowedFields = {
          'version',
          'previousVersion',
          'publish',
          'releaseAction',
          'tier',
          'supportStatement',
          'bumpReason',
        };
        final unknownFields = value.keys
            .map((key) => key.toString())
            .where((key) => !allowedFields.contains(key))
            .toList();
        if (unknownFields.isNotEmpty) {
          throw FormatException(
            '$name has unknown release fields: ${unknownFields.join(', ')}',
          );
        }
        String requiredString(String key) {
          final item = value[key];
          if (item is! String || item.isEmpty) {
            throw FormatException('$name is missing non-empty $key');
          }
          return item;
        }
        final publish = value['publish'];
        if (publish is! bool) {
          throw FormatException('$name publish must be true or false');
        }
        final action = requiredString('releaseAction');
        if (!const {'publish', 'reuse', 'internal'}.contains(action)) {
          throw FormatException('$name has unsupported releaseAction $action');
        }
        if (publish && action == 'internal' || !publish && action != 'internal') {
          throw FormatException('$name publish/releaseAction disagree');
        }
        final version = requiredString('version');
        final previousVersion = requiredString('previousVersion');
        final versionPattern = RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$');
        if (!versionPattern.hasMatch(version) ||
            !versionPattern.hasMatch(previousVersion)) {
          throw FormatException('$name has a malformed semantic version');
        }
        packages[name] = _PackageRelease(
          name: name,
          version: version,
          previousVersion: previousVersion,
          publish: publish,
          releaseAction: action,
          tier: requiredString('tier'),
          supportStatement: requiredString('supportStatement'),
          bumpReason: requiredString('bumpReason'),
        );
      }
      final rawOrder = decoded['publicationOrder'];
      if (rawOrder is! List || rawOrder.any((item) => item is! String)) {
        throw const FormatException('publicationOrder must be a string list');
      }
      final order = rawOrder.cast<String>();
      if (order.toSet().length != order.length) {
        throw const FormatException('publicationOrder contains duplicates');
      }
      return _ReleaseMatrix(
        packages: packages,
        publicationOrder: order,
        retiredPackages: (decoded['retiredPackages'] is Map)
            ? _retiredPackageNames(decoded['retiredPackages'] as Map)
            : const {},
      );
    } on Object catch (error) {
      failures.add('invalid docs/release-matrix.yaml: $error');
      return const _ReleaseMatrix.empty();
    }
  }

  Set<String> _retiredPackageNames(Map value) {
    for (final entry in value.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          (entry.value as String).trim().isEmpty) {
        throw const FormatException(
          'retiredPackages must map package names to non-empty reasons',
        );
      }
    }
    return value.keys.cast<String>().toSet();
  }

  Map<String, Directory> _activePackages(List<String> failures) {
    final workspaceFile = File(
      '${root.path}${Platform.pathSeparator}pubspec.yaml',
    );
    if (!workspaceFile.existsSync()) {
      failures.add('missing root pubspec.yaml');
      return const {};
    }
    final yaml = loadYaml(workspaceFile.readAsStringSync());
    final workspaceList = (yaml is Map) ? yaml['workspace'] : null;
    if (workspaceList is! List) {
      failures.add('pubspec.yaml is missing workspace list');
      return const {};
    }

    final result = <String, Directory>{};
    for (final entry in workspaceList.whereType<String>()) {
      if (!entry.startsWith('vendor-sdk/')) continue;
      final directory = Directory(
        '${root.path}${Platform.pathSeparator}$entry',
      );
      final pubspec = File(
        '${directory.path}${Platform.pathSeparator}pubspec.yaml',
      );
      if (!pubspec.existsSync()) {
        failures.add('$entry: missing pubspec.yaml');
        continue;
      }
      final packageYaml = loadYaml(pubspec.readAsStringSync());
      final name = (packageYaml is Map)
          ? packageYaml['name']?.toString()
          : null;
      if (name == null) {
        failures.add('$entry: missing package name');
      } else {
        result[name] = directory;
      }
    }
    return result;
  }

  void _checkLinks(List<String> failures) {
    final linkPattern = RegExp(r'!?\[[^\]]*\]\(([^)]+)\)');
    for (final file in _filesWithExtension('.md')) {
      final contents = file.readAsStringSync();
      for (final match in linkPattern.allMatches(contents)) {
        final target = match.group(1)!.trim();
        if (_isExternalOrAnchor(target)) continue;
        final localTarget = target.split('#').first;
        if (localTarget.isEmpty) continue;
        final resolved = File(
          '${file.parent.path}${Platform.pathSeparator}$localTarget',
        );
        final resolvedDirectory = Directory(
          '${file.parent.path}${Platform.pathSeparator}$localTarget',
        );
        if (!resolved.existsSync() && !resolvedDirectory.existsSync()) {
          failures.add('${_relative(file)}: broken local link `$target`');
        }
      }
    }
  }

  void _checkRetiredIdentities(List<String> failures) {
    for (final file in _scannedFiles()) {
      final relative = _relative(file);
      if (_isExcludedFromRetiredCheck(relative)) continue;
      final contents = file.readAsStringSync();
      for (final pattern in _retiredPatterns) {
        if (contents.contains(pattern)) {
          failures.add('$relative: retired reference `$pattern`');
        }
      }
    }
  }

  void _checkRawScenarioIds(List<String> failures) {
    final testId = RegExp(r'''['"](?:SCN|RULE)-[A-Z0-9-]+['"]''');
    final libraryId = RegExp(r'''['"](?:RULE|CTRL)-[A-Z0-9-]+['"]''');
    final suppression = RegExp(r'^\s*//\s*zuke: allow-raw-id\s+--\s+\S');
    for (final file in _filesWithExtension('.dart')) {
      final relative = _relative(file);
      if (!relative.startsWith('examples/') ||
          relative.contains('/generated/')) {
        continue;
      }
      final isTest = relative.contains('/test/');
      final isLibrary = relative.contains('/lib/');
      if (!isTest && !isLibrary) continue;
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (!(isTest ? testId : libraryId).hasMatch(lines[index])) continue;
        // Existing compile-time annotations are the migration boundary until
        // RuleId/ControlId annotation literals can be extracted by every
        // supported analyzer version. Ordinary library literals are forbidden.
        if (isLibrary &&
            lines
                .sublist((index - 10).clamp(0, index).toInt(), index + 1)
                .any(
                  (line) =>
                      line.contains('@ImplementsRequirement') ||
                      line.contains('@PresentsRequirement') ||
                      line.contains('@ProvidesControl') ||
                      line.contains('@VerifiesRequirement'),
                )) {
          continue;
        }
        final allowed =
            suppression.hasMatch(lines[index]) ||
            (index > 0 && suppression.hasMatch(lines[index - 1]));
        if (!allowed) {
          failures.add(
            '$relative:${index + 1}: governed IDs must use generated contracts '
            'or a reasoned allow-raw-id suppression',
          );
        }
      }
    }
  }

  void _checkGuideFences(List<String> failures) {
    final guide = File(
      '${root.path}${Platform.pathSeparator}docs${Platform.pathSeparator}integration-guide.md',
    );
    if (!guide.existsSync()) {
      failures.add('missing docs/integration-guide.md');
      return;
    }
    final lines = guide.readAsLinesSync();
    String? language;
    String? info;
    var start = 0;
    final content = <String>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (language == null && line.startsWith('```')) {
        final parts = line.substring(3).trim().split(RegExp(r'\s+'));
        language = parts.first;
        info = line.substring(3).trim();
        start = index + 2;
        content.clear();
        continue;
      }
      if (language != null && line == '```') {
        if (language == 'yaml') {
          try {
            if (loadYaml(content.join('\n')) is! Map) {
              failures.add(
                'docs/integration-guide.md:$start: YAML fence must be a mapping',
              );
            }
          } catch (error) {
            failures.add(
              'docs/integration-guide.md:$start: invalid YAML fence: $error',
            );
          }
        } else if (language == 'dart') {
          final infoText = info ?? '';
          final snippet = RegExp(
            r'(?:^|\s)snippet=([a-z0-9_-]+)',
          ).firstMatch(infoText);
          final pseudocode = RegExp(
            r'(?:^|\s)pseudocode(?:\s|$)',
          ).hasMatch(infoText);
          if (snippet == null && !pseudocode) {
            failures.add(
              'docs/integration-guide.md:$start: Dart fence needs snippet=<name> or pseudocode',
            );
          } else if (snippet != null) {
            _checkSnippet(snippet.group(1)!, content.join('\n'), failures);
          }
        }
        language = null;
        info = null;
        continue;
      }
      if (language != null) content.add(line);
    }
    if (language != null) {
      failures.add('docs/integration-guide.md:$start: unterminated code fence');
    }
  }

  void _checkSnippet(String name, String documented, List<String> failures) {
    final fileName = switch (name) {
      'bindings' => '../../lib/src/shopping_bindings.dart',
      'vendor-steps' => 'vendor_steps.dart',
      'profile-filter' => 'profile_filter.dart',
      _ => '$name.dart',
    };
    final relative = name == 'bindings'
        ? 'examples/shopping_cart/lib/src/shopping_bindings.dart'
        : 'examples/shopping_cart/test/guide_snippets/$fileName';
    final file = File(
      '${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!file.existsSync()) {
      failures.add('guide snippet `$name` has no compiled fixture');
      return;
    }
    final startMarker = '// guide-snippet:$name:start';
    final endMarker = '// guide-snippet:$name:end';
    final lines = file.readAsLinesSync();
    final start = lines.indexWhere((line) => line.trim() == startMarker);
    final end = lines.indexWhere((line) => line.trim() == endMarker);
    if (start < 0 || end <= start) {
      failures.add(
        '${_relative(file)}: missing guide-snippet markers for `$name`',
      );
      return;
    }
    final source = _dedent(lines.sublist(start + 1, end)).join('\n');
    if (source.trim() != documented.trim()) {
      failures.add('guide snippet `$name` differs from ${_relative(file)}');
    }
  }

  void _checkActivePubspecs(
    Map<String, Directory> packages,
    _ReleaseMatrix matrix,
    List<String> failures,
  ) {
    for (final entry in packages.entries) {
      final pubspec = File(
        '${entry.value.path}${Platform.pathSeparator}pubspec.yaml',
      );
      final contents = pubspec.readAsStringSync();
      final relative = _relative(pubspec);
      final release = matrix.packages[entry.key];
      if (release == null) {
        failures.add('${entry.key}: active SDK package is missing from the release matrix');
        continue;
      }
      final packageYaml = loadYaml(contents);
      final expectedVersion = release.version;
      if (!RegExp(
        '^version:\\s*${RegExp.escape(expectedVersion)}\\s*\$',
        multiLine: true,
      ).hasMatch(contents)) {
        failures.add(
          '$relative: active SDK package must be version $expectedVersion',
        );
      }
      if (!RegExp(
        r'^resolution:\s*workspace\s*$',
        multiLine: true,
      ).hasMatch(contents)) {
        failures.add(
          '$relative: active SDK package must use resolution: workspace',
        );
      }
      final publishesNowhere = RegExp(
        r'^publish_to:\s*none\s*$',
        multiLine: true,
      ).hasMatch(contents);
      if (release.publish && publishesNowhere) {
        failures.add(
          '$relative: published package must not declare publish_to: none',
        );
      } else if (!release.publish && !publishesNowhere) {
        failures.add(
          '$relative: internal package must declare publish_to: none',
        );
      }
      for (final section in ['dependencies', 'dev_dependencies']) {
        final dependencies = packageYaml is Map ? packageYaml[section] : null;
        if (dependencies is! Map) continue;
        for (final dependency in dependencies.entries) {
          if (dependency.value is Map &&
              (dependency.value as Map).containsKey('path')) {
            if (release.publish) {
              failures.add('$relative: published package must not use a path dependency for ${dependency.key}');
            }
          }
          final dependencyName = dependency.key.toString();
          final dependencyRelease = matrix.packages[dependencyName];
          if (release.publish && dependencyRelease != null && !dependencyRelease.publish) {
            failures.add('$relative: published package depends on internal package $dependencyName');
          }
          if (release.publish && matrix.retiredPackages.contains(dependencyName)) {
            failures.add('$relative: published package depends on retired package $dependencyName');
          }
        }
      }
    }

    final activeNames = packages.keys.toSet();
    final matrixNames = matrix.packages.keys.toSet();
    final missingFromMatrix = activeNames.difference(matrixNames);
    for (final name in missingFromMatrix) {
      failures.add('$name: active SDK package is missing from the release matrix');
    }
    final missingFromWorkspace = matrixNames.difference(activeNames).where(
      (name) => !matrix.retiredPackages.contains(name),
    );
    for (final name in missingFromWorkspace) {
      failures.add('$name: release-matrix package is not an active workspace package');
    }

    final expectedOrder = matrix.packages.values
        .where((release) => release.releaseAction == 'publish')
        .map((release) => release.name)
        .toSet();
    final actualOrder = matrix.publicationOrder.toSet();
    if (actualOrder.length != matrix.publicationOrder.length) {
      failures.add('release matrix publicationOrder contains duplicates');
    }
    if (!identical(expectedOrder, actualOrder) &&
        (expectedOrder.length != actualOrder.length ||
            !expectedOrder.containsAll(actualOrder))) {
      failures.add(
        'release matrix publicationOrder must contain exactly the packages with releaseAction: publish',
      );
    }
  }

  void _checkReadmeTiers(
    Map<String, Directory> packages,
    _ReleaseMatrix matrix,
    List<String> failures,
  ) {
    for (final entry in packages.entries) {
      final release = matrix.packages[entry.key];
      if (release == null) {
        failures.add('no support-tier contract configured for ${entry.key}');
        continue;
      }
      final readme = File(
        '${entry.value.path}${Platform.pathSeparator}README.md',
      );
      if (!readme.existsSync() ||
          !readme.readAsStringSync().contains(release.supportStatement)) {
        failures.add(
          '${_relative(readme)}: missing support-tier contract `${release.supportStatement}`',
        );
      }
    }
  }

  void _checkPackageImportsAndCycles(
    Map<String, Directory> packages,
    _ReleaseMatrix matrix,
    List<String> failures,
  ) {
    final graph = <String, Set<String>>{};
    for (final entry in packages.entries) {
      final packageName = entry.key;
      final release = matrix.packages[packageName];
      if (release == null) continue;
      final dependencies = <String>{};
      final pubspec = File(
        '${entry.value.path}${Platform.pathSeparator}pubspec.yaml',
      );
      final yaml = loadYaml(pubspec.readAsStringSync());
      for (final section in ['dependencies', 'dev_dependencies']) {
        final raw = yaml is Map ? yaml[section] : null;
        if (raw is! Map) continue;
        for (final dependency in raw.keys) {
          final dependencyName = dependency.toString();
          if (packages.containsKey(dependencyName)) dependencies.add(dependencyName);
          final dependencyRelease = matrix.packages[dependencyName];
          if (release.publish &&
              dependencyRelease != null &&
              !dependencyRelease.publish) {
            failures.add(
              '${_relative(pubspec)}: published package references internal package $dependencyName',
            );
          }
        }
      }
      graph[packageName] = dependencies;

      final lib = Directory('${entry.value.path}${Platform.pathSeparator}lib');
      if (!lib.existsSync()) continue;
      for (final file in lib.listSync(recursive: true, followLinks: false).whereType<File>()) {
        final contents = file.readAsStringSync();
        final imports = RegExp(r"package:([A-Za-z0-9_]+?)/").allMatches(contents);
        for (final match in imports) {
          final imported = match.group(1)!;
          if (matrix.retiredPackages.contains(imported)) {
            failures.add(
              '${_relative(file)}: imports retired package $imported',
            );
          }
          final importedRelease = matrix.packages[imported];
          if (release.publish &&
              importedRelease != null &&
              !importedRelease.publish) {
            failures.add(
              '${_relative(file)}: published package imports internal package $imported',
            );
          }
          if (packageName == 'zuke_core' &&
              (imported == 'analyzer' || imported == 'dart_extractor')) {
            failures.add(
              '${_relative(file)}: zuke_core must remain analyzer/extractor-free',
            );
          }
        }
      }
    }

    final visiting = <String>{};
    final visited = <String>{};
    void visit(String packageName, List<String> path) {
      if (visiting.contains(packageName)) {
        final cycleStart = path.indexOf(packageName);
        final cycle = [
          ...path.skip(cycleStart < 0 ? 0 : cycleStart),
          packageName,
        ];
        failures.add('package dependency cycle: ${cycle.join(' -> ')}');
        return;
      }
      if (!visited.add(packageName)) return;
      visiting.add(packageName);
      for (final dependency in graph[packageName] ?? const <String>{}) {
        visit(dependency, [...path, packageName]);
      }
      visiting.remove(packageName);
    }
    for (final packageName in graph.keys) {
      visit(packageName, const []);
    }
  }

  void _checkRetiredPackages(
    _ReleaseMatrix matrix,
    List<String> failures,
  ) {
    for (final name in matrix.retiredPackages) {
      final directory = Directory(
        '${root.path}${Platform.pathSeparator}vendor-sdk${Platform.pathSeparator}$name',
      );
      if (!directory.existsSync()) continue;
      final pubspec = File(
        '${directory.path}${Platform.pathSeparator}pubspec.yaml',
      );
      if (!pubspec.existsSync()) continue;
      final yaml = loadYaml(pubspec.readAsStringSync());
      if (yaml is! Map || yaml['publish_to']?.toString() != 'none') {
        failures.add('$name: retired package must declare publish_to: none');
      }
    }
  }

  void _checkLockDocumentation(List<String> failures) {
    final legacyLock = RegExp(r'\bzuke\.lock(?:\.v\d+|\.json)\b');
    final missingProfile = RegExp(r'\bzuke\s+lock\b(?![^\n]*(?:--profile|--all-profiles))');
    for (final file in _allFiles().where((file) {
      final path = file.path.toLowerCase();
      return path.endsWith('.md') ||
          path.endsWith('.yaml') ||
          path.endsWith('.yml');
    })) {
      final relative = _relative(file);
      final contents = file.readAsStringSync();
      if (legacyLock.hasMatch(contents)) {
        failures.add('$relative: legacy/versioned lock names are forbidden; use assurance/locks/<profile>.lock.json');
      }
      for (final line in contents.split('\n')) {
        if (missingProfile.hasMatch(line)) {
          failures.add('$relative: zuke lock commands must specify --profile or --all-profiles');
        }
      }
    }
  }

  void _checkCurrentProductLanguage(List<String> failures) {
    final migration = File(
      '${root.path}${Platform.pathSeparator}docs${Platform.pathSeparator}migration.md',
    );
    if (!migration.existsSync()) {
      failures.add('missing docs/migration.md');
    } else {
      final contents = migration.readAsStringSync();
      if (!contents.startsWith('# Migrating to the Current Zuke Release')) {
        failures.add('docs/migration.md must use the current migration title');
      }
      for (final required in [
        'previous package versions pinned',
        'schema 3',
        'sourcePackage',
        'sourceAdapter',
        'assurance/locks/pullRequest.lock.json',
        'regenerate',
        'retired package',
      ]) {
        if (!contents.toLowerCase().contains(required.toLowerCase())) {
          failures.add('docs/migration.md is missing required migration guidance: $required');
        }
      }
    }

    final forbidden = <RegExp>[
      RegExp(r'\bzuke-v2\b', caseSensitive: false),
      RegExp(r'\bverify-v2\b', caseSensitive: false),
      RegExp(r'\bv2\.dart\b', caseSensitive: false),
      RegExp(r'\bzuke\.lock\.v\d+\b', caseSensitive: false),
      RegExp(r'assurance-history/v2', caseSensitive: false),
      RegExp(r'\bV2\s+(?:SDK|primary|contracts?|workspace|product|release|history|facade|result)', caseSensitive: false),
    ];
    for (final file in _allFiles().where((candidate) {
      final relative = _relative(candidate).toLowerCase();
      if (!(relative.endsWith('.md') ||
          relative.endsWith('.yaml') ||
          relative.endsWith('.yml'))) {
        return false;
      }
      if (relative.contains('/test/') ||
          relative == 'vendor-sdk/check_docs.dart' ||
          relative.endsWith('changelog.md') ||
          relative.contains('/legacy-v2-untrusted/')) {
        return false;
      }
      return true;
    })) {
      final relative = _relative(file);
      final contents = file.readAsStringSync();
      for (final pattern in forbidden) {
        if (pattern.hasMatch(contents)) {
          failures.add('$relative: product-facing legacy/V2 terminology is forbidden (${pattern.pattern})');
        }
      }
    }
  }

  Iterable<File> _filesWithExtension(String extension) =>
      _allFiles().where((file) => file.path.endsWith(extension));

  Iterable<File> _scannedFiles() => _allFiles().where((file) {
    final path = file.path.toLowerCase();
    return path.endsWith('.dart') ||
        path.endsWith('.md') ||
        path.endsWith('.yaml') ||
        path.endsWith('.yml');
  });

  Iterable<File> _allFiles() sync* {
    for (final relative in [
      'README.md',
      'docs',
      'examples',
      '.github',
      'melos.yaml',
      'vendor-sdk',
    ]) {
      final entity = FileSystemEntity.typeSync(
        '${root.path}${Platform.pathSeparator}$relative',
      );
      if (entity == FileSystemEntityType.file) {
        yield File('${root.path}${Platform.pathSeparator}$relative');
      } else if (entity == FileSystemEntityType.directory) {
        yield* Directory(
          '${root.path}${Platform.pathSeparator}$relative',
        ).listSync(recursive: true, followLinks: false).whereType<File>();
      }
    }
  }

  bool _isExcludedFromRetiredCheck(String relative) =>
      relative == 'vendor-sdk/check_docs.dart' ||
      relative == 'vendor-sdk/zuke_cli/test/check_docs_test.dart' ||
      relative == '.github/workflows/sdk-release.yml' ||
      _retiredDirectories.any(relative.startsWith);

  String _relative(File file) =>
      file.absolute.path.substring(root.path.length + 1).replaceAll('\\', '/');

  List<String> _dedent(List<String> lines) {
    final nonEmpty = lines.where((line) => line.trim().isNotEmpty).toList();
    if (nonEmpty.isEmpty) return lines;
    final indent = nonEmpty
        .map((line) => line.length - line.trimLeft().length)
        .reduce((left, right) => left < right ? left : right);
    return lines
        .map((line) => line.length >= indent ? line.substring(indent) : line)
        .toList(growable: false);
  }

  bool _isExternalOrAnchor(String target) =>
      target.startsWith('#') ||
      target.startsWith('http://') ||
      target.startsWith('https://') ||
      target.startsWith('mailto:') ||
      target.startsWith('data:');
}

class _ReleaseMatrix {
  const _ReleaseMatrix({
    required this.packages,
    required this.publicationOrder,
    required this.retiredPackages,
  });

  const _ReleaseMatrix.empty()
    : packages = const {},
      publicationOrder = const [],
      retiredPackages = const {};

  final Map<String, _PackageRelease> packages;
  final List<String> publicationOrder;
  final Set<String> retiredPackages;
}

class _PackageRelease {
  const _PackageRelease({
    required this.name,
    required this.version,
    required this.previousVersion,
    required this.publish,
    required this.releaseAction,
    required this.tier,
    required this.supportStatement,
    required this.bumpReason,
  });

  final String name;
  final String version;
  final String previousVersion;
  final bool publish;
  final String releaseAction;
  final String tier;
  final String supportStatement;
  final String bumpReason;
}
