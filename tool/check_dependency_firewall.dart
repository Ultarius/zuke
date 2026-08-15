import 'dart:io';

import 'package:yaml/yaml.dart';

final class DependencyFirewall {
  const DependencyFirewall(this.root, {this.policyFile});

  final Directory root;
  final File? policyFile;

  List<String> check() {
    final policy = loadYaml(
      (policyFile ??
              File(
                '${root.path}${Platform.pathSeparator}tool${Platform.pathSeparator}dependency-policy.yaml',
              ))
          .readAsStringSync(),
    );
    if (policy is! Map) return const ['dependency policy must be a mapping'];
    final allowedTestConstraint = policy['testConstraint'];
    if (allowedTestConstraint is! String || allowedTestConstraint.isEmpty) {
      return const ['dependency policy testConstraint is missing'];
    }
    final packageRules = policy['packages'];
    if (packageRules is! Map) {
      return const ['dependency policy packages must be a mapping'];
    }

    final failures = <String>[];
    for (final package in _workspacePackages()) {
      final rule = packageRules[package.name];
      if (rule is! Map) continue;
      final pubspec = loadYaml(package.file.readAsStringSync());
      if (pubspec is! Map) {
        failures.add('${package.name}: pubspec must be a mapping');
        continue;
      }
      final runtime = _dependencyNames(pubspec['dependencies']);
      final dev = _dependencyNames(pubspec['dev_dependencies']);
      _forbid(
        failures,
        package.name,
        'runtime',
        runtime,
        rule['forbiddenRuntime'],
      );
      _forbid(failures, package.name, 'dev', dev, rule['forbiddenDev']);
      _require(
        failures,
        package.name,
        'runtime',
        runtime,
        rule['requireRuntime'],
      );
      _require(failures, package.name, 'dev', dev, rule['requireDev']);
      _requireSdk(failures, package.name, pubspec, rule['requireRuntimeSdk']);

      if (rule['rejectExactTestConstraint'] == true) {
        final value =
            _dependencyValue(pubspec['dependencies'], 'test') ??
            _dependencyValue(pubspec['dev_dependencies'], 'test');
        if (value is String && _isExactVersion(value)) {
          failures.add(
            '${package.name}: test must use a compatible range, not exact $value',
          );
        }
      }
    }
    return failures;
  }

  List<_WorkspacePackage> _workspacePackages() {
    final rootPubspec = loadYaml(
      File(
        '${root.path}${Platform.pathSeparator}pubspec.yaml',
      ).readAsStringSync(),
    );
    final workspace = rootPubspec is Map ? rootPubspec['workspace'] : null;
    if (workspace is! List) return const [];
    return [
      for (final entry in workspace)
        if (entry is String) _packageAt(entry),
    ];
  }

  _WorkspacePackage _packageAt(String relative) {
    final file = File(
      '${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}'
      '${Platform.pathSeparator}pubspec.yaml',
    );
    final decoded = file.existsSync()
        ? loadYaml(file.readAsStringSync())
        : null;
    final name = decoded is Map && decoded['name'] is String
        ? decoded['name'] as String
        : relative;
    return _WorkspacePackage(name, file);
  }
}

final class _WorkspacePackage {
  const _WorkspacePackage(this.name, this.file);

  final String name;
  final File file;
}

Set<String> _dependencyNames(Object? value) =>
    value is Map ? value.keys.whereType<String>().toSet() : <String>{};

Object? _dependencyValue(Object? section, String name) =>
    section is Map ? section[name] : null;

void _forbid(
  List<String> failures,
  String package,
  String section,
  Set<String> actual,
  Object? raw,
) {
  if (raw is! List) return;
  for (final name in raw.whereType<String>()) {
    if (actual.contains(name)) {
      failures.add('$package: $name is forbidden in $section dependencies');
    }
  }
}

void _require(
  List<String> failures,
  String package,
  String section,
  Set<String> actual,
  Object? raw,
) {
  if (raw is! List) return;
  for (final name in raw.whereType<String>()) {
    if (!actual.contains(name)) {
      failures.add('$package: $name is required in $section dependencies');
    }
  }
}

void _requireSdk(
  List<String> failures,
  String package,
  Object? pubspec,
  Object? raw,
) {
  if (raw is! List || pubspec is! Map) return;
  final dependencies = pubspec['dependencies'];
  for (final name in raw.whereType<String>()) {
    final value = dependencies is Map ? dependencies[name] : null;
    final expectedSdk = name == 'flutter_test' ? 'flutter' : name;
    if (value is! Map || value['sdk'] != expectedSdk) {
      failures.add('$package: $name must be an SDK dependency');
    }
  }
}

bool _isExactVersion(String value) =>
    RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(value.trim());

Future<void> main(List<String> args) async {
  final root = Directory.current;
  final failures = DependencyFirewall(root).check();
  if (failures.isEmpty) {
    stdout.writeln('Dependency firewall passed.');
    return;
  }
  for (final failure in failures) {
    stderr.writeln('DEPENDENCY-FIREWALL: $failure');
  }
  exitCode = 1;
}
