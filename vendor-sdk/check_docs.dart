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
  static const _tiers = <String, String>{
    'zuke': 'Primary Zuke pure-Dart SDK.',
    'zuke_core':
        'Supported Zuke infrastructure dependency; not a primary application package.',
    'zuke_annotations': 'Supported application-facing public API.',
    'zuke_frontend': 'Supported application-facing public API.',
    'zuke_runner': 'Compatibility package for the primary Zuke SDK.',
    'zuke_runner_flutter': 'Supported application-facing public API.',
    'zuke_http_runtime': 'Supported application-facing public API.',
    'zuke_cli': 'Supported application-facing public API.',
    'zuke_dart_build_hook': 'Supported application-facing public API.',
    'assurance_ir': 'Adapter-author surface.',
    'adapter_sdk': 'Adapter-author surface.',
    'evidence_ledger': 'Published implementation dependency.',
    'dart_extractor': 'Published implementation dependency.',
    'zuke_generator': 'Published implementation dependency.',
    'proof_engine': 'Published implementation dependency.',
    'zuke_reporter': 'Published implementation dependency.',
    'zuke_adapter_dart_frog': 'Supported adapter extension API.',
    'zuke_analyzer': 'Repository-only tooling; not published to pub.dev.',
    'zuke_conformance': 'Repository-only tooling; not published to pub.dev.',
    'zuke_verifier': 'Repository-only tooling; not published to pub.dev.',
    'zuke_test_support': 'Repository-only tooling; not published to pub.dev.',
  };

  static const _publishedPackages = <String>{
    'zuke',
    'zuke_core',
    'zuke_annotations',
    'zuke_frontend',
    'zuke_runner',
    'zuke_runner_flutter',
    'zuke_http_runtime',
    'zuke_dart_build_hook',
    'zuke_cli',
    'assurance_ir',
    'adapter_sdk',
    'evidence_ledger',
    'dart_extractor',
    'zuke_generator',
    'proof_engine',
    'zuke_reporter',
    'zuke_adapter_dart_frog',
  };

  List<String> check() {
    final failures = <String>[];
    final activePackages = _activePackages(failures);
    _checkLinks(failures);
    _checkRetiredIdentities(failures);
    _checkRawScenarioIds(failures);
    _checkGuideFences(failures);
    _checkActivePubspecs(activePackages, _releaseMatrix(), failures);
    _checkReadmeTiers(activePackages, failures);
    return failures;
  }

  Map<String, String> _releaseMatrix() {
    final file = File(
      '${root.path}${Platform.pathSeparator}docs${Platform.pathSeparator}release-matrix.yaml',
    );
    if (!file.existsSync()) return const {};
    final decoded = loadYaml(file.readAsStringSync());
    final packages = decoded is Map ? decoded['packages'] : null;
    if (packages is! Map) return const {};
    return {
      for (final entry in packages.entries)
        entry.key.toString(): entry.value.toString(),
    };
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
    if (result.length != _tiers.length) {
      failures.add(
        'expected ${_tiers.length} active SDK packages, found ${result.length}',
      );
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
    Map<String, String> matrix,
    List<String> failures,
  ) {
    for (final entry in packages.entries) {
      final pubspec = File(
        '${entry.value.path}${Platform.pathSeparator}pubspec.yaml',
      );
      final contents = pubspec.readAsStringSync();
      final relative = _relative(pubspec);
      final expectedVersion = matrix[entry.key] ?? '0.1.0';
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
      final isPublished = _publishedPackages.contains(entry.key);
      final publishesNowhere = RegExp(
        r'^publish_to:\s*none\s*$',
        multiLine: true,
      ).hasMatch(contents);
      if (isPublished &&
          RegExp(r'^publish_to:', multiLine: true).hasMatch(contents)) {
        failures.add(
          '$relative: published SDK package must not declare publish_to',
        );
      } else if (!isPublished && !publishesNowhere) {
        failures.add(
          '$relative: repository-only SDK package must declare publish_to: none',
        );
      }
      final packageYaml = loadYaml(contents);
      for (final section in ['dependencies', 'dev_dependencies']) {
        final dependencies = packageYaml is Map ? packageYaml[section] : null;
        if (dependencies is! Map) continue;
        for (final dependency in dependencies.entries) {
          if (dependency.value is Map &&
              (dependency.value as Map).containsKey('path')) {
            failures.add(
              '$relative: active SDK package must not use a path dependency for ${dependency.key}',
            );
          }
        }
      }
      for (final internal in packages.keys) {
        for (final section in ['dependencies', 'dev_dependencies']) {
          final dependencies = packageYaml is Map ? packageYaml[section] : null;
          if (dependencies is! Map || !dependencies.containsKey(internal)) {
            continue;
          }
          final declared = dependencies[internal];
          final expectedConstraint = matrix.containsKey(internal)
              ? '^${matrix[internal]}'
              : '^0.1.0';
          if (declared?.toString() != expectedConstraint) {
            failures.add('$relative: $internal must use $expectedConstraint');
          }
        }
      }
    }
  }

  void _checkReadmeTiers(
    Map<String, Directory> packages,
    List<String> failures,
  ) {
    for (final entry in packages.entries) {
      final expected = _tiers[entry.key];
      if (expected == null) {
        failures.add('no support-tier contract configured for ${entry.key}');
        continue;
      }
      final readme = File(
        '${entry.value.path}${Platform.pathSeparator}README.md',
      );
      if (!readme.existsSync() ||
          !readme.readAsStringSync().contains(expected)) {
        failures.add(
          '${_relative(readme)}: missing support-tier contract `$expected`',
        );
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
