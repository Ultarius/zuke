import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'cli_test_helper.dart';
import '../lib/src/test_host_doctor.dart';

void main() {
  test('reports consumer test constraints without writing overrides', () {
    final root = Directory.systemTemp.createTempSync('zuke-test-host-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: consumer
dev_dependencies:
  test: 1.31.1
''');

    final report = TestHostDoctor(root).inspect();

    expect(
      report.details['directTestConstraints'],
      containsPair('consumer', '1.31.1'),
    );
    expect(report.status, 'undetermined');
    expect(
      report.diagnostics.map((diagnostic) => diagnostic.code),
      contains('ZK-TEST-HOST-UNRESOLVED'),
    );
    expect(File('${root.path}/pubspec_overrides.yaml').existsSync(), isFalse);
  });

  test('reports a Flutter pin conflict from the resolved test package', () {
    final root = Directory.systemTemp.createTempSync('zuke-test-host-pin-');
    final flutterRoot = Directory('${root.path}/flutter')
      ..createSync(recursive: true);
    final flutterTest = Directory('${flutterRoot.path}/packages/flutter_test')
      ..createSync(recursive: true);
    File('${flutterTest.path}/pubspec.yaml').writeAsStringSync('''
name: flutter_test
dependencies:
  test_api: 0.7.11
''');
    final pubCache = Directory('${root.path}/pub-cache')..createSync();
    final testPackage = Directory('${pubCache.path}/hosted/pub.dev/test-1.31.1')
      ..createSync(recursive: true);
    File('${testPackage.path}/pubspec.yaml').writeAsStringSync('''
name: test
dependencies:
  test_api: 0.7.12
''');
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: consumer
dev_dependencies:
  test: 1.31.1
''');
    File('${root.path}/pubspec.lock').writeAsStringSync('''
packages:
  test:
    version: 1.31.1
  test_api:
    version: 0.7.12
''');
    addTearDown(() => root.deleteSync(recursive: true));

    final report = TestHostDoctor(
      root,
      flutterRoot: flutterRoot,
      pubCache: pubCache,
    ).inspect();

    expect(
      report.diagnostics.map((diagnostic) => diagnostic.code),
      contains('ZK-TEST-SDK-PIN'),
    );
    expect(report.status, 'incompatible');
    expect(report.details['flutterPinnedTestApi'], '0.7.11');
    expect(report.details['resolvedTestApi'], '0.7.12');
  });

  test('reports compatible when the resolved tuple matches Flutter', () {
    final root = Directory.systemTemp.createTempSync('zuke-test-host-ok-');
    final flutterRoot = Directory('${root.path}/flutter')
      ..createSync(recursive: true);
    final flutterTest = Directory('${flutterRoot.path}/packages/flutter_test')
      ..createSync(recursive: true);
    File('${flutterTest.path}/pubspec.yaml').writeAsStringSync('''
name: flutter_test
dependencies:
  test_api: 0.7.11
''');
    final pubCache = Directory('${root.path}/pub-cache')..createSync();
    final testPackage = Directory('${pubCache.path}/hosted/pub.dev/test-1.31.0')
      ..createSync(recursive: true);
    File('${testPackage.path}/pubspec.yaml').writeAsStringSync('''
name: test
dependencies:
  test_api: 0.7.11
''');
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: consumer
dev_dependencies:
  test: '>=1.31.0 <1.32.0'
''');
    File('${root.path}/pubspec.lock').writeAsStringSync('''
packages:
  test:
    version: 1.31.0
  test_api:
    version: 0.7.11
''');
    addTearDown(() => root.deleteSync(recursive: true));

    final report = TestHostDoctor(
      root,
      flutterRoot: flutterRoot,
      pubCache: pubCache,
    ).inspect();

    expect(report.status, 'compatible');
    expect(report.diagnostics, isEmpty);
  });

  test('doctor test-host is a structured CLI command', () async {
    final root = Directory.systemTemp.createTempSync('zuke-test-host-cli-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: consumer\n');

    final result = await runInProcessCli([
      'doctor',
      'test-host',
      '--root',
      root.path,
      '--format',
      'json',
    ]);
    final decoded = jsonDecode(result.stdout) as Map<Object?, Object?>;

    expect(result.exitCode, 2);
    expect(decoded['status'], 'failed');
    expect(decoded['eligible'], isFalse);
    expect(decoded['command'], 'doctor test-host');
    expect(decoded['testHost'], containsPair('status', 'undetermined'));
  });

  test('hosted certification requires an explicit host and platform', () async {
    final result = await runInProcessCli(['certify', 'hosted']);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('--platform'));
    expect(result.stderr, contains('--host'));
  });
}
