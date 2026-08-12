import 'dart:io';

import 'release_matrix.dart';

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
  final matrix = readReleaseMatrix(root);
  final dartFrog = matrix.compatibilityIds['dart-frog'];
  final dartSource = matrix.compatibilityIds['dart-source'];
  if (dartFrog == null || dartSource == null) {
    throw const FormatException(
      'release matrix compatibilityIds must define dart-frog and dart-source',
    );
  }
  final publicVersions = matrix.publicPackageVersions;
  final retiredPackages = matrix.retiredPackages.toList()..sort();
  final operatingSystems = [...matrix.operatingSystems]..sort();
  final compatibilityIds = matrix.compatibilityIds.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final content =
      '''// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: docs/release-matrix.yaml

/// Compatibility identity for the first-party Dart Frog topology adapter.
const releaseDartFrogCompatibilityId = '${_quote(dartFrog)}';

/// Compatibility identity for resolved Dart source extraction.
const releaseDartSourceCompatibilityId = '${_quote(dartSource)}';

/// Exact versions for the currently supported hosted public packages.
const releasePublicPackageVersions = <String, String>{
${_dartMap(publicVersions)}
};

/// Packages retained only as historical names and never published by current Zuke.
const releaseRetiredPackages = <String>{
${retiredPackages.map((value) => "  '${_quote(value)}',").join('\n')}
};

/// Operating systems covered by the release certification lanes.
const releaseSupportedOperatingSystems = ${_dartList(operatingSystems)};

/// Compatibility identities selected by the release matrix.
const releaseCompatibilityIds = <String, String>{
${_dartMap({for (final entry in compatibilityIds) entry.key: entry.value})}
};
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

String _dartList(List<String> values) {
  return '<String>[${values.map((value) => "'${_quote(value)}'").join(', ')}]';
}

String _quote(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

String _dartMap(Map<String, String> values) => values.entries
    .map((entry) => "  '${_quote(entry.key)}': '${_quote(entry.value)}',")
    .join('\n');
