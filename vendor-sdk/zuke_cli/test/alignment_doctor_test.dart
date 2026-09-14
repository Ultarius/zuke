import 'dart:io';

import 'package:test/test.dart';

import '../lib/src/alignment_doctor.dart';

void main() {
  test('allows the supported tuple without requiring equal versions', () {
    final root = Directory.systemTemp.createTempSync('zuke-alignment-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: consumer
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  zuke_core: ^0.4.0
dev_dependencies:
  zuke_cli: ^0.5.0
''');
    File('${root.path}/pubspec.lock').writeAsStringSync('''
packages:
  zuke_core:
    version: "0.4.0"
  zuke_cli:
    version: "0.5.0"
''');

    final report = const AlignmentDoctor().inspect(root);

    expect(report.passed, isTrue);
    expect(report.details['supportedVersions'], isNotEmpty);
  });

  test('rejects a constraint outside the supported release tuple', () {
    final root = Directory.systemTemp.createTempSync('zuke-alignment-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: consumer
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  zuke_core: ^0.3.0
''');

    final report = const AlignmentDoctor().inspect(root);

    expect(report.passed, isFalse);
    expect(
      report.diagnostics.map((diagnostic) => diagnostic.code),
      contains('ZK-ALIGNMENT-CONSTRAINT'),
    );
  });

  test('reports a declared package missing from the lockfile', () {
    final root = Directory.systemTemp.createTempSync('zuke-alignment-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: consumer
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  zuke_core: ^0.4.0
''');

    final report = const AlignmentDoctor().inspect(root);

    expect(report.passed, isFalse);
    expect(
      report.diagnostics.map((diagnostic) => diagnostic.code),
      contains('ZK-ALIGNMENT-UNRESOLVED'),
    );
  });
}
