import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:zuke_core/zuke_core.dart';

final class TestHostDoctorReport {
  const TestHostDoctorReport({
    required this.diagnostics,
    required this.details,
  });

  final List<Diagnostic> diagnostics;
  final Map<String, Object?> details;
}

/// Explains SDK-pinned test infrastructure without modifying the consumer.
///
/// This is deliberately diagnostic-only. Pub remains the authority for
/// solving the graph and this command never writes overrides or pubspecs.
final class TestHostDoctor {
  const TestHostDoctor(this.root, {this.flutterRoot, this.pubCache});

  final Directory root;
  final Directory? flutterRoot;
  final Directory? pubCache;

  TestHostDoctorReport inspect() {
    final constraints = <String, String>{};
    final packageRoots = <Directory>[root, ..._workspaceMembers()];
    for (final packageRoot in packageRoots) {
      final file = File(
        '${packageRoot.path}${Platform.pathSeparator}pubspec.yaml',
      );
      if (!file.existsSync()) continue;
      final decoded = loadYaml(file.readAsStringSync());
      final name = decoded is Map && decoded['name'] is String
          ? decoded['name'] as String
          : packageRoot.path;
      final value = _dependencyValue(decoded, 'test');
      if (value != null) constraints[name] = value;
    }

    final lock = _readLock();
    final resolvedTest = lock['test'];
    final resolvedTestApi = lock['test_api'];
    final flutterPin = _flutterPinnedTestApi();
    final expectedTestApi = _testPackageApi(resolvedTest);
    final diagnostics = <Diagnostic>[];

    if (flutterPin != null &&
        expectedTestApi != null &&
        flutterPin != expectedTestApi) {
      diagnostics.add(
        Diagnostic(
          code: 'ZK-TEST-SDK-PIN',
          stage: 'doctor',
          severity: DiagnosticSeverity.error,
          owner: DiagnosticOwner.project,
          message:
              'Flutter SDK pins test_api $flutterPin, but the selected '
              'test package requires test_api $expectedTestApi.',
          remediation:
              'Choose a test constraint compatible with the Flutter SDK, '
              'or use a Flutter SDK with a compatible pin. Zuke does not '
              'install dependency overrides.',
        ),
      );
    } else if (flutterPin != null &&
        constraints.values.any(_isExactVersion) &&
        expectedTestApi == null) {
      diagnostics.add(
        const Diagnostic(
          code: 'ZK-TEST-SDK-PIN',
          stage: 'doctor',
          severity: DiagnosticSeverity.warning,
          owner: DiagnosticOwner.project,
          message:
              'The consumer has an exact test constraint while Flutter '
              'pins test_api. Compatibility cannot be confirmed until Pub '
              'resolves the graph.',
          remediation:
              'Use a compatible test range or run flutter pub get and inspect '
              'the resulting test/test_api versions.',
        ),
      );
    }

    return TestHostDoctorReport(
      diagnostics: List.unmodifiable(diagnostics),
      details: {
        'flutterPinnedTestApi': flutterPin,
        'resolvedTest': resolvedTest,
        'resolvedTestApi': resolvedTestApi,
        'testPackageRequiresTestApi': expectedTestApi,
        'directTestConstraints': constraints,
      },
    );
  }

  List<Directory> _workspaceMembers() {
    final file = File('${root.path}${Platform.pathSeparator}pubspec.yaml');
    if (!file.existsSync()) return const [];
    final decoded = loadYaml(file.readAsStringSync());
    final workspace = decoded is Map ? decoded['workspace'] : null;
    if (workspace is! List) return const [];
    return [
      for (final value in workspace)
        if (value is String)
          Directory(
            '${root.path}${Platform.pathSeparator}'
            '${value.replaceAll('/', Platform.pathSeparator)}',
          ),
    ];
  }

  Map<String, String> _readLock() {
    final file = File('${root.path}${Platform.pathSeparator}pubspec.lock');
    if (!file.existsSync()) return const {};
    final decoded = loadYaml(file.readAsStringSync());
    final packages = decoded is Map ? decoded['packages'] : null;
    if (packages is! Map) return const {};
    return {
      for (final name in const ['test', 'test_api'])
        if (packages[name] is Map && packages[name]['version'] is String)
          name: packages[name]['version'] as String,
    };
  }

  String? _flutterPinnedTestApi() {
    final flutterRoot = _findFlutterRoot();
    if (flutterRoot == null) return null;
    final file = File(
      '${flutterRoot.path}${Platform.pathSeparator}packages${Platform.pathSeparator}'
      'flutter_test${Platform.pathSeparator}pubspec.yaml',
    );
    if (!file.existsSync()) return null;
    final decoded = loadYaml(file.readAsStringSync());
    final dependencies = decoded is Map ? decoded['dependencies'] : null;
    final value = dependencies is Map ? dependencies['test_api'] : null;
    if (value is String) return value;
    if (value is Map && value['version'] is String) {
      return value['version'] as String;
    }
    return null;
  }

  String? _testPackageApi(String? version) {
    if (version == null) return null;
    final cache = pubCache ?? Directory(_defaultPubCache());
    final file = File(
      '${cache.path}${Platform.pathSeparator}hosted${Platform.pathSeparator}pub.dev'
      '${Platform.pathSeparator}test-$version${Platform.pathSeparator}pubspec.yaml',
    );
    if (!file.existsSync()) return null;
    final decoded = loadYaml(file.readAsStringSync());
    final dependencies = decoded is Map ? decoded['dependencies'] : null;
    final value = dependencies is Map ? dependencies['test_api'] : null;
    if (value is String) return value;
    if (value is Map && value['version'] is String) {
      return value['version'] as String;
    }
    return null;
  }

  Directory? _findFlutterRoot() {
    if (flutterRoot != null) return flutterRoot;
    final configured = Platform.environment['FLUTTER_ROOT'];
    if (configured != null && configured.trim().isNotEmpty) {
      final directory = Directory(configured);
      if (directory.existsSync()) return directory;
    }
    final command = Platform.isWindows ? 'where' : 'which';
    try {
      final result = Process.runSync(command, const [
        'flutter',
      ], runInShell: Platform.isWindows);
      if (result.exitCode != 0) return null;
      for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
        final value = line.trim();
        if (value.isEmpty) continue;
        final executable = File(value);
        final candidate = executable.parent.parent;
        if (Directory(
          '${candidate.path}${Platform.pathSeparator}packages${Platform.pathSeparator}flutter_test',
        ).existsSync()) {
          return candidate;
        }
      }
    } on Object {
      return null;
    }
    return null;
  }

  String _defaultPubCache() {
    final configured = Platform.environment['PUB_CACHE'];
    if (configured != null && configured.trim().isNotEmpty) {
      return configured;
    }
    if (Platform.isWindows) {
      return '${Platform.environment['LOCALAPPDATA'] ?? ''}'
          '${Platform.pathSeparator}Pub${Platform.pathSeparator}Cache';
    }
    return '${Platform.environment['HOME'] ?? ''}'
        '${Platform.pathSeparator}.pub-cache';
  }
}

String? _dependencyValue(Object? pubspec, String package) {
  if (pubspec is! Map) return null;
  for (final section in const ['dependencies', 'dev_dependencies']) {
    final dependencies = pubspec[section];
    final value = dependencies is Map ? dependencies[package] : null;
    if (value is String) return value;
    if (value is Map && value['version'] is String) {
      return value['version'] as String;
    }
  }
  return null;
}

bool _isExactVersion(String value) =>
    RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(value.trim());
