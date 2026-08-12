import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'release_matrix.dart';

/// Structural release guard for the consolidated hosted boundary.
///
/// It checks source shape and the published runtime dependency graph, without
/// running package tests, so it can run early in publication CI and catch
/// accidental re-introduction of retired implementations or analyzer-heavy
/// runtime dependencies.
Future<void> main() async {
  final root = Directory.current;
  final failures = <String>[];
  late final ReleaseMatrix matrix;
  try {
    matrix = readReleaseMatrix(root);
  } on Object catch (error) {
    failures.add('release matrix could not be read: $error');
    matrix = const ReleaseMatrix.empty();
  }
  final adapterFiles = _dartFiles(
    Directory('${root.path}/vendor-sdk/zuke_cli/lib'),
  ).where((file) => file.path.endsWith('dart_frog_adapter.dart')).toList();
  if (adapterFiles.length != 1) {
    failures.add(
      'expected exactly one active Dart Frog adapter, found ${adapterFiles.length}',
    );
  }

  final ledgerEntries = <String>[];
  // Limit the scan to published source trees. Walking every generated SDK
  // directory (including nested .dart_tool caches) makes this structural
  // check unnecessarily slow and can appear hung on CI.
  final publishedSourceRoots = [
    Directory('${root.path}/vendor-sdk/zuke_cli/lib'),
    Directory('${root.path}/vendor-sdk/zuke_core/lib'),
  ];
  for (final sourceRoot in publishedSourceRoots) {
    for (final file in _dartFiles(sourceRoot)) {
      final contents = file.readAsStringSync();
      if (RegExp(r'\bclass\s+EvidenceLedgerEntry\b').hasMatch(contents)) {
        ledgerEntries.add(file.path);
      }
    }
  }
  if (ledgerEntries.length != 1 ||
      !ledgerEntries.single
          .replaceAll('\\', '/')
          .endsWith('vendor-sdk/zuke_cli/lib/src/evidence_ledger.dart')) {
    failures.add(
      'EvidenceLedgerEntry must have one implementation in zuke_cli; '
      'found ${ledgerEntries.join(', ')}',
    );
  }

  final activePackages = matrix.packages.values
      .where(
        (package) =>
            package.releaseAction == 'publish' ||
            package.releaseAction == 'reuse',
      )
      .map((package) => package.name)
      .toSet();
  final internalPackages = matrix.packages.values
      .where((package) => package.releaseAction == 'internal')
      .map((package) => package.name)
      .toSet();
  final privatePackages = {...internalPackages, ...matrix.retiredPackages};
  final packageGraph = <String, Set<String>>{};
  for (final package in activePackages) {
    final packageDirectory = Directory('${root.path}/vendor-sdk/$package');
    final pubspec = File('${packageDirectory.path}/pubspec.yaml');
    if (!pubspec.existsSync()) {
      failures.add('published package $package is missing pubspec.yaml');
      continue;
    }
    final document = _readPubspec(pubspec, failures);
    final dependencies = <String, Object?>{};
    for (final section in const ['dependencies', 'dev_dependencies']) {
      final values = document[section];
      if (values is Map) {
        for (final entry in values.entries) {
          if (entry.key is String) {
            dependencies[entry.key as String] = entry.value;
          }
        }
      }
    }
    final packageDependencies = <String>{};
    for (final entry in dependencies.entries) {
      final dependency = entry.key;
      if (privatePackages.contains(dependency)) {
        failures.add(
          '$package depends on unpublished or retired package $dependency',
        );
      }
      if (_isPathDependency(entry.value)) {
        failures.add(
          '$package uses a path dependency for $dependency; hosted packages must be path-free',
        );
      }
      if (activePackages.contains(dependency)) {
        packageDependencies.add(dependency);
      }
    }
    packageGraph[package] = packageDependencies;
    if (package == 'zuke_core' &&
        dependencies.keys.any(
          (dependency) =>
              dependency == 'analyzer' || dependency == 'dart_extractor',
        )) {
      failures.add('zuke_core has a direct analyzer/extractor dependency');
    }
    for (final file in _dartFiles(Directory('${packageDirectory.path}/lib'))) {
      final contents = file.readAsStringSync();
      for (final retired in matrix.retiredPackages) {
        if (RegExp('package:${RegExp.escape(retired)}/').hasMatch(contents)) {
          failures.add(
            '$package imports retired package $retired in ${file.path}',
          );
        }
      }
    }
  }

  for (final internal in internalPackages) {
    final pubspec = File('${root.path}/vendor-sdk/$internal/pubspec.yaml');
    if (!pubspec.existsSync()) {
      failures.add('internal package $internal is missing pubspec.yaml');
      continue;
    }
    final document = _readPubspec(pubspec, failures);
    if (document['publish_to'] != 'none') {
      failures.add('internal package $internal must declare publish_to: none');
    }
  }
  _findCycles(packageGraph, failures);

  final coreRuntimeDependencies = await _runtimeDependencyClosure(
    root,
    'zuke_core',
    failures,
  );
  if (coreRuntimeDependencies.contains('analyzer') ||
      coreRuntimeDependencies.any(
        (dependency) =>
            dependency == 'dart_extractor' ||
            dependency.startsWith('dart_extractor:'),
      )) {
    failures.add(
      'zuke_core has an analyzer or extractor in its transitive runtime '
      'dependency graph: ${coreRuntimeDependencies.toList()..sort()}',
    );
  }

  final core = Directory('${root.path}/vendor-sdk/zuke_core/lib');
  for (final file in _dartFiles(core)) {
    final contents = file.readAsStringSync();
    if (RegExp(
      r"package:analyzer|package:dart_extractor|dart_extractor/",
    ).hasMatch(contents)) {
      failures.add('zuke_core imports analyzer/extractor code: ${file.path}');
    }
  }

  final result = {
    'kind': 'zuke.framework-boundaries',
    'passed': failures.isEmpty,
    'adapterFiles': adapterFiles.map((file) => file.path).toList(),
    'ledgerEntries': ledgerEntries,
    'activePackages': activePackages.toList()..sort(),
    'zukeCoreRuntimeDependencies': coreRuntimeDependencies.toList()..sort(),
    'failures': failures,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  if (failures.isNotEmpty) exitCode = 1;
}

Map<Object?, Object?> _readPubspec(File file, List<String> failures) {
  try {
    final decoded = loadYaml(file.readAsStringSync());
    if (decoded is! Map) {
      throw const FormatException('pubspec root is not a mapping');
    }
    return Map<Object?, Object?>.from(decoded);
  } on Object catch (error) {
    failures.add('unable to parse ${file.path}: $error');
    return const {};
  }
}

bool _isPathDependency(Object? value) =>
    value is Map &&
    value['path'] is String &&
    (value['path'] as String).isNotEmpty;

Future<Set<String>> _runtimeDependencyClosure(
  Directory root,
  String packageName,
  List<String> failures,
) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    const [
      '--suppress-analytics',
      'pub',
      'deps',
      '--json',
      '-C',
      'vendor-sdk/zuke_core',
    ],
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    failures.add(
      'unable to inspect the zuke_core runtime dependency graph: '
      '${_singleLine(result.stderr)}',
    );
    return <String>{};
  }

  late final Object? decoded;
  try {
    decoded = jsonDecode(result.stdout as String);
  } on Object catch (error) {
    failures.add(
      'zuke_core dependency graph was not valid Pub JSON: ${_singleLine(error)}',
    );
    return <String>{};
  }
  if (decoded is! Map || decoded['packages'] is! List) {
    failures.add('zuke_core dependency graph was not valid Pub JSON');
    return <String>{};
  }

  final packages = <String, Map<String, Object?>>{};
  for (final entry in decoded['packages'] as List) {
    if (entry is! Map || entry['name'] is! String) continue;
    packages[entry['name'] as String] = Map<String, Object?>.from(entry);
  }
  final rootPackage = packages[packageName];
  if (rootPackage == null) {
    failures.add('zuke_core was missing from its Pub dependency graph');
    return <String>{};
  }

  final closure = <String>{};
  final pending = <String>[
    ..._stringList(rootPackage['directDependencies']),
  ];
  while (pending.isNotEmpty) {
    final dependency = pending.removeLast();
    if (!closure.add(dependency)) continue;
    final package = packages[dependency];
    if (package == null) {
      failures.add(
        'zuke_core dependency graph omitted runtime package $dependency',
      );
      continue;
    }
    pending.addAll(_stringList(package['directDependencies']));
  }
  return closure;
}

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().toList()
    : const <String>[];

String _singleLine(Object? value) => value
    .toString()
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

void _findCycles(Map<String, Set<String>> graph, List<String> failures) {
  final visiting = <String>{};
  final visited = <String>{};
  final reported = <String>{};

  void visit(String package, List<String> path) {
    if (visiting.contains(package)) {
      final start = path.indexOf(package);
      final cycle = [
        ...path.sublist(start < 0 ? 0 : start),
        package,
      ].join(' -> ');
      if (reported.add(cycle)) {
        failures.add('Zuke package dependency cycle: $cycle');
      }
      return;
    }
    if (!visited.add(package)) return;
    visiting.add(package);
    for (final dependency in graph[package] ?? const <String>{}) {
      visit(dependency, [...path, package]);
    }
    visiting.remove(package);
  }

  for (final package in graph.keys) {
    visit(package, const []);
  }
}

Iterable<File> _dartFiles(Directory directory) sync* {
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}
