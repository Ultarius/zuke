import 'dart:io';

import 'package:yaml/yaml.dart';

const _output = 'vendor-sdk/zuke_cli/lib/src/generated/release_contract.dart';

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final unknown = args.where((arg) => arg != '--check').toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown argument: ${unknown.join(', ')}');
    exitCode = 64;
    return;
  }

  final root = Directory.current;
  final matrixFile = File('${root.path}/docs/release-matrix.yaml');
  if (!matrixFile.existsSync()) {
    stderr.writeln('Missing docs/release-matrix.yaml');
    exitCode = 1;
    return;
  }
  final decoded = loadYaml(matrixFile.readAsStringSync());
  if (decoded is! Map || decoded['schemaVersion'] != 2) {
    stderr.writeln('release matrix schemaVersion must be 2');
    exitCode = 1;
    return;
  }
  final rawIds = decoded['compatibilityIds'];
  if (rawIds is! Map) {
    stderr.writeln('release matrix compatibilityIds must be a mapping');
    exitCode = 1;
    return;
  }

  String required(String key) {
    final value = rawIds[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('compatibilityIds.$key must be non-empty');
    }
    return value;
  }

  final dartFrog = required('dart-frog');
  final dartSource = required('dart-source');
  final content = '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: docs/release-matrix.yaml

/// Compatibility identity for the first-party Dart Frog topology adapter.
const releaseDartFrogCompatibilityId = '${_quote(dartFrog)}';

/// Compatibility identity for resolved Dart source extraction.
const releaseDartSourceCompatibilityId = '${_quote(dartSource)}';
''';
  final output = File('${root.path}/$_output');
  if (check) {
    if (!output.existsSync() || output.readAsStringSync() != content) {
      stderr.writeln('Generated release contract is stale: $_output');
      exitCode = 1;
    }
    return;
  }
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(content);
  stdout.writeln('Generated $_output');
}

String _quote(String value) => value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
