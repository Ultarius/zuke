import 'dart:io';

import 'package:zuke_core/zuke_core.dart';
import 'package:yaml/yaml.dart';

import 'generated/release_contract.dart';
import 'test_host_doctor.dart';

final class AlignmentDoctorReport {
  const AlignmentDoctorReport({
    required this.diagnostics,
    required this.details,
  });

  final List<Diagnostic> diagnostics;
  final Map<String, Object?> details;

  bool get passed => diagnostics.every(
    (diagnostic) => diagnostic.severity != DiagnosticSeverity.error,
  );
}

/// Checks the consumer's declared, overridden, and resolved Zuke tuple.
///
/// A release tuple is intentionally a set of supported package versions. It
/// does not require every package to have the same version number: the CLI,
/// runners, annotations, and adapters have independent release cadences.
final class AlignmentDoctor {
  const AlignmentDoctor();

  AlignmentDoctorReport inspect(Directory root) {
    final diagnostics = <Diagnostic>[];
    final declarations = <String, Map<String, String>>{};
    final overrides = <String, String>{};
    final packageFiles = _packageFiles(root);
    for (final file in packageFiles) {
      final packageName =
          file.path == '${root.path}${Platform.pathSeparator}pubspec.yaml'
          ? '.'
          : file.parent.path;
      try {
        final document = _mapping(loadYaml(file.readAsStringSync()));
        declarations[packageName] = _zukeDependencies(document);
        _readOverrides(document['dependency_overrides'], overrides);
      } on Object catch (error) {
        diagnostics.add(
          Diagnostic(
            code: 'ZK-ALIGNMENT-MALFORMED-MANIFEST',
            stage: 'doctor',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.project,
            message: '$packageName has a malformed pubspec.yaml.',
            remediation: 'Fix the manifest and run the alignment check again.',
            context: {'errorType': error.runtimeType.toString()},
          ),
        );
      }
    }
    _readOverrides(
      _readOptionalMapping(
        File('${root.path}${Platform.pathSeparator}pubspec_overrides.yaml'),
      )?['dependency_overrides'],
      overrides,
    );
    final resolved = _resolvedPackages(root);
    final declarationConstraints = <String, Map<String, String>>{};
    for (final entry in declarations.entries) {
      for (final packageEntry in entry.value.entries) {
        declarationConstraints.putIfAbsent(
          packageEntry.key,
          () => {},
        )[entry.key] = packageEntry.value;
        final expected = releasePublicPackageVersions[packageEntry.key];
        if (packageEntry.key == 'zuke_test_support') continue;
        if (expected == null || !_admits(packageEntry.value, expected)) {
          diagnostics.add(
            Diagnostic(
              code: 'ZK-ALIGNMENT-CONSTRAINT',
              stage: 'doctor',
              severity: DiagnosticSeverity.error,
              owner: DiagnosticOwner.project,
              message:
                  '${entry.key}: ${packageEntry.key} does not admit the supported release version.',
              remediation:
                  'Use a constraint that admits the supported Zuke release tuple.',
            ),
          );
        }
      }
    }
    for (final package in releasePublicPackageVersions.keys) {
      final selected = resolved[package];
      final declared = declarationConstraints.containsKey(package);
      if (declared && selected == null) {
        diagnostics.add(
          Diagnostic(
            code: 'ZK-ALIGNMENT-UNRESOLVED',
            stage: 'doctor',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.environment,
            message: '$package is declared but missing from pubspec.lock.',
            remediation:
                'Resolve dependencies before running alignment checks.',
          ),
        );
        continue;
      }
      if (selected == null) continue;
      final expected = releasePublicPackageVersions[package]!;
      if (selected['version'] != expected) {
        diagnostics.add(
          Diagnostic(
            code: 'ZK-ALIGNMENT-RESOLUTION',
            stage: 'doctor',
            severity: DiagnosticSeverity.error,
            owner: DiagnosticOwner.environment,
            message: '$package resolved to an unsupported release version.',
            remediation: 'Resolve dependencies using the supported Zuke tuple.',
            context: {'expected': expected},
          ),
        );
      }
    }
    final host = TestHostDoctor(root).inspect();
    diagnostics.addAll(host.diagnostics);
    return AlignmentDoctorReport(
      diagnostics: List.unmodifiable(diagnostics),
      details: {
        'supportedVersions': releasePublicPackageVersions,
        'declarations': declarationConstraints,
        'overrides': overrides,
        'resolved': resolved,
        'testHost': host.details,
      },
    );
  }

  List<File> _packageFiles(Directory root) {
    final result = <File>[];
    final rootPubspec = File(
      '${root.path}${Platform.pathSeparator}pubspec.yaml',
    );
    if (!rootPubspec.existsSync()) return result;
    result.add(rootPubspec);
    try {
      final document = _mapping(loadYaml(rootPubspec.readAsStringSync()));
      final workspace = document['workspace'];
      if (workspace is List) {
        for (final member in workspace.whereType<String>()) {
          final file = File(
            '${root.path}${Platform.pathSeparator}${member.replaceAll('/', Platform.pathSeparator)}${Platform.pathSeparator}pubspec.yaml',
          );
          if (file.existsSync()) result.add(file);
        }
      }
    } on Object {
      // The root manifest diagnostic is emitted by inspect().
    }
    return result;
  }

  Map<String, String> _zukeDependencies(Map<Object?, Object?> document) {
    final result = <String, String>{};
    for (final section in const ['dependencies', 'dev_dependencies']) {
      final values = document[section];
      if (values is! Map) continue;
      for (final entry in values.entries) {
        final name = entry.key;
        if (name is! String || !_isZukePackage(name)) continue;
        final value = entry.value;
        if (value is String && value.trim().isNotEmpty) {
          result[name] = value.trim();
        } else if (value is Map && value['sdk'] is String) {
          result[name] = 'sdk:${value['sdk']}';
        } else {
          result[name] = '<non-scalar>';
        }
      }
    }
    return result;
  }

  void _readOverrides(Object? raw, Map<String, String> output) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      if (entry.key is! String) continue;
      final value = entry.value;
      output[entry.key as String] = _overrideDescription(value);
    }
  }

  Map<String, Map<String, Object?>> _resolvedPackages(Directory root) {
    final file = File('${root.path}${Platform.pathSeparator}pubspec.lock');
    if (!file.existsSync()) return const {};
    try {
      final document = _mapping(loadYaml(file.readAsStringSync()));
      final packages = document['packages'];
      if (packages is! Map) return const {};
      return {
        for (final entry in packages.entries)
          if (entry.key is String &&
              entry.value is Map &&
              _isZukePackage(entry.key as String))
            entry.key as String: {
              for (final item in (entry.value as Map).entries)
                if (item.key is String &&
                    (item.value is String ||
                        item.value is num ||
                        item.value is bool))
                  item.key as String: item.value,
              if ((entry.value as Map)['description'] is Map)
                for (final descriptionEntry
                    in ((entry.value as Map)['description'] as Map).entries)
                  if (descriptionEntry.key is String &&
                      (descriptionEntry.value is String ||
                          descriptionEntry.value is num ||
                          descriptionEntry.value is bool))
                    'description.${descriptionEntry.key}':
                        descriptionEntry.value,
            },
      };
    } on Object {
      return const {};
    }
  }

  Map<Object?, Object?>? _readOptionalMapping(File file) {
    if (!file.existsSync()) return null;
    try {
      return _mapping(loadYaml(file.readAsStringSync()));
    } on Object {
      return null;
    }
  }
}

String _overrideDescription(Object? value) {
  if (value is! Map) return value.toString();
  final git = value['git'];
  if (git is Map) {
    final url = git['url'];
    final ref = git['ref'];
    final path = value['path'] ?? git['path'];
    return 'git:${url ?? '<url>'}'
        '${ref is String && ref.isNotEmpty ? '@$ref' : ''}'
        '${path is String && path.isNotEmpty ? '#$path' : ''}';
  }
  if (value['path'] is String) return 'path:${value['path']}';
  return 'mapping';
}

Map<Object?, Object?> _mapping(Object? value) {
  if (value is! Map) throw const FormatException('YAML root must be a mapping');
  return Map<Object?, Object?>.from(value);
}

bool _isZukePackage(String package) =>
    package == 'zuke' || package.startsWith('zuke_');

bool _admits(String constraint, String version) {
  final expected = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
  if (expected == null) return false;
  final actual = [
    int.parse(expected.group(1)!),
    int.parse(expected.group(2)!),
    int.parse(expected.group(3)!),
  ];
  final trimmed = constraint.trim();
  if (trimmed == 'any' || trimmed == '*') return true;
  final clauses = RegExp(
    r'(\^|~|>=|<=|>|<|=)?\s*(\d+)\.(\d+)\.(\d+)',
  ).allMatches(trimmed).toList(growable: false);
  if (clauses.isEmpty) return false;
  for (final clause in clauses) {
    final operator = clause.group(1) ?? '=';
    final base = [
      int.parse(clause.group(2)!),
      int.parse(clause.group(3)!),
      int.parse(clause.group(4)!),
    ];
    final comparison = _compare(actual, base);
    final valid = switch (operator) {
      '^' => _caretAllows(actual, base),
      '~' => actual[0] == base[0] && actual[1] == base[1] && comparison >= 0,
      '>=' => comparison >= 0,
      '<=' => comparison <= 0,
      '>' => comparison > 0,
      '<' => comparison < 0,
      _ => comparison == 0,
    };
    if (!valid) return false;
  }
  return true;
}

int _compare(List<int> left, List<int> right) {
  for (var index = 0; index < 3; index++) {
    final comparison = left[index].compareTo(right[index]);
    if (comparison != 0) return comparison;
  }
  return 0;
}

bool _caretAllows(List<int> actual, List<int> base) {
  if (_compare(actual, base) < 0) return false;
  if (base[0] > 0) return actual[0] == base[0];
  if (base[1] > 0) {
    return actual[0] == 0 && actual[1] == base[1];
  }
  return actual[0] == 0 && actual[1] == 0 && actual[2] == base[2];
}
