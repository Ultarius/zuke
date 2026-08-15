import 'dart:io';

import 'package:yaml/yaml.dart';

import 'release_matrix.dart';

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
    final configuredTestConstraint = policy['testConstraint'];
    final String allowedTestConstraint;
    try {
      allowedTestConstraint = _certifiedTestConstraint(
        root,
        configuredTestConstraint,
      );
    } on Object catch (error) {
      return ['dependency policy testConstraint is invalid: $error'];
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
        for (final value in [
          _dependencyValue(pubspec['dependencies'], 'test'),
          _dependencyValue(pubspec['dev_dependencies'], 'test'),
        ]) {
          if (value is! String) continue;
          if (_isExactVersion(value)) {
            failures.add(
              '${package.name}: test must use a compatible range, not exact $value',
            );
          }
          if (!_constraintAllows(value, allowedTestConstraint)) {
            failures.add(
              '${package.name}: test constraint $value does not admit '
              'the certified minimum test version '
              '${_constraintLowerBound(allowedTestConstraint)}',
            );
          }
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

Object? _dependencyValue(Object? section, String name) => section is Map
    ? section[name] is Map && section[name]['version'] is String
          ? section[name]['version']
          : section[name]
    : null;

String _certifiedTestConstraint(Directory root, Object? configured) {
  final matrix = File(
    '${root.path}${Platform.pathSeparator}docs${Platform.pathSeparator}'
    'release-matrix.yaml',
  );
  if (matrix.existsSync()) {
    final value = readReleaseMatrix(root).sdk['test'];
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException(
        'docs/release-matrix.yaml sdk.test is missing',
      );
    }
    return value;
  }
  if (configured is String && configured.trim().isNotEmpty) {
    return configured;
  }
  throw const FormatException('test constraint is missing');
}

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

bool _constraintAllows(String candidate, String certifiedConstraint) {
  final version = _Version.tryParse(_constraintLowerBound(certifiedConstraint));
  if (version == null) return false;
  final value = candidate.trim();
  final band = RegExp(r'^(\d+)\.(\d+)\.x$').firstMatch(value);
  if (band != null) {
    return version.major == int.parse(band.group(1)!) &&
        version.minor == int.parse(band.group(2)!);
  }

  if (value.startsWith('^')) {
    final lower = _Version.tryParse(value.substring(1).trim());
    if (lower == null || version.compareTo(lower) < 0) return false;
    final upper = lower.major > 0
        ? _Version(lower.major + 1, 0, 0)
        : lower.minor > 0
        ? _Version(0, lower.minor + 1, 0)
        : _Version(0, 0, lower.patch + 1);
    return version.compareTo(upper) < 0;
  }

  if (value.startsWith('~')) {
    final lower = _Version.tryParse(value.substring(1).trim());
    if (lower == null || version.compareTo(lower) < 0) return false;
    return version.compareTo(_Version(lower.major, lower.minor + 1, 0)) < 0;
  }

  final clauses = RegExp(
    r'(>=|<=|>|<|=)?\s*(\d+)\.(\d+)\.(\d+)',
  ).allMatches(value);
  if (clauses.isEmpty) return false;
  for (final clause in clauses) {
    final operator = clause.group(1) ?? '=';
    final bound = _Version(
      int.parse(clause.group(2)!),
      int.parse(clause.group(3)!),
      int.parse(clause.group(4)!),
    );
    final comparison = version.compareTo(bound);
    final passes = switch (operator) {
      '>=' => comparison >= 0,
      '>' => comparison > 0,
      '<=' => comparison <= 0,
      '<' => comparison < 0,
      '=' => comparison == 0,
      _ => false,
    };
    if (!passes) return false;
  }
  return true;
}

String _constraintLowerBound(String constraint) {
  final value = constraint.trim();
  final band = RegExp(r'^(\d+)\.(\d+)\.x$').firstMatch(value);
  if (band != null) return '${band.group(1)}.${band.group(2)}.0';
  final lower = RegExp(r'>=\s*(\d+\.\d+\.\d+)').firstMatch(value);
  if (lower != null) return lower.group(1)!;
  final caret = value.startsWith('^') ? value.substring(1).trim() : value;
  final tilde = caret.startsWith('~') ? caret.substring(1).trim() : caret;
  final exact = RegExp(r'\d+\.\d+\.\d+').firstMatch(tilde);
  if (exact != null) return exact.group(0)!;
  throw FormatException('unsupported test constraint $constraint');
}

final class _Version implements Comparable<_Version> {
  const _Version(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static _Version? tryParse(String value) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(value.trim());
    if (match == null) return null;
    return _Version(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(_Version other) {
    final majorComparison = major.compareTo(other.major);
    if (majorComparison != 0) return majorComparison;
    final minorComparison = minor.compareTo(other.minor);
    if (minorComparison != 0) return minorComparison;
    return patch.compareTo(other.patch);
  }
}

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
