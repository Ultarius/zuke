import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// Framework-owned starting configurations; project policy stays explicit.
enum InitPreset {
  dart,
  flutter,
  dartFrog;

  static InitPreset detect(Directory root) {
    final pubspec = File('${root.path}/pubspec.yaml');
    if (!pubspec.existsSync()) return dart;
    final document = loadYaml(pubspec.readAsStringSync());
    final dependencies = document is Map ? document['dependencies'] : null;
    if (dependencies is Map) {
      if (dependencies.containsKey('flutter')) return flutter;
      if (dependencies.containsKey('dart_frog')) return dartFrog;
    }
    return dart;
  }

  String configuration(Directory root) {
    final name = root.absolute.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final framework = this == dartFrog ? 'dart-frog' : this.name;
    final executable = this == flutter ? 'flutter' : 'dart';
    final adapter = this == dartFrog ? 'dart-frog' : 'dart-source';
    final compatibility = this == dartFrog
        ? 'dart-frog-gen-2-route-topology-v1'
        : 'dart-source-package-v1';
    return '''schemaVersion: 3
workspace:
  name: ${jsonEncode(name)}
  root: .
specifications:
  features: [specs/features/**/*.feature]
targets:
  app:
    language: dart
    framework: $framework
    packages:
      - id: app
        path: .
        roots: ${this == dartFrog ? '[lib, routes, test]' : '[lib, test]'}
    contractOutput: lib/src/generated
    contractExport: lib/zuke_contracts.dart
execution:
  runners:
    - id: app-tests
      kind: gherkin
      target: app
      sourcePackage: app
      sourceAdapter: $adapter
      sourceCompatibilityId: $compatibility
      runnerCompatibilityId: $executable-test-v1
      evidenceTypes: ${this == flutter ? '[unit, flutter-widget]' : '[unit]'}
      executable: $executable
      args: [test, --reporter, expanded]
      workingDirectory: .
      timeoutSeconds: 120
lock:
  directory: assurance/locks
  profiles: [pullRequest, merge, release, nightly]
trust:
  bundle: assurance-history/trust/ed25519.json
  algorithm: ed25519
''';
  }
}
