import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/check_dependency_firewall.dart';

void main() {
  test('current workspace obeys the test-host dependency boundary', () {
    final root = _findRoot(Directory.current);
    expect(DependencyFirewall(root).check(), isEmpty);
  });

  test('rejects an exact runner test constraint', () {
    final root = Directory.systemTemp.createTempSync('zuke-firewall-');
    addTearDown(() => root.deleteSync(recursive: true));
    _writePolicy(root);
    _writePackage(root, 'zuke_runner', '''name: zuke_runner
dependencies:
  test: 1.31.1
''');

    expect(
      DependencyFirewall(root).check(),
      contains(contains('exact 1.31.1')),
    );
  });

  test('rejects a range that excludes the certified minimum', () {
    final root = Directory.systemTemp.createTempSync('zuke-firewall-');
    addTearDown(() => root.deleteSync(recursive: true));
    _writePolicy(root);
    _writePackage(root, 'zuke_runner', '''name: zuke_runner
dependencies:
  test: '>=1.31.1 <2.0.0'
''');

    expect(
      DependencyFirewall(root).check(),
      contains(
        contains('does not admit the certified minimum test version 1.31.0'),
      ),
    );
  });

  test('accepts a range containing the certified minimum', () {
    final root = Directory.systemTemp.createTempSync('zuke-firewall-');
    addTearDown(() => root.deleteSync(recursive: true));
    _writePolicy(root);
    _writePackage(root, 'zuke_runner', '''name: zuke_runner
dependencies:
  test: '>=1.31.0 <1.32.0'
''');

    expect(DependencyFirewall(root).check(), isEmpty);
  });

  test('uses the release matrix instead of the policy fallback', () {
    final root = Directory.systemTemp.createTempSync('zuke-firewall-');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/docs').createSync(recursive: true);
    final matrix = File(
      '${_findRoot(Directory.current).path}/docs/release-matrix.yaml',
    ).readAsStringSync().replaceFirst("test: '1.31.x'", "test: '1.32.x'");
    File('${root.path}/docs/release-matrix.yaml').writeAsStringSync(matrix);
    _writePolicy(root);
    _writePackage(root, 'zuke_runner', '''name: zuke_runner
dependencies:
  test: '>=1.32.0 <1.33.0'
''');

    expect(DependencyFirewall(root).check(), isEmpty);
  });

  test('rejects direct test dependencies in the Flutter runner', () {
    final root = Directory.systemTemp.createTempSync('zuke-firewall-');
    addTearDown(() => root.deleteSync(recursive: true));
    _writePolicy(root);
    _writePackage(root, 'zuke_runner_flutter', '''name: zuke_runner_flutter
dependencies:
  flutter:
    sdk: flutter
  flutter_test:
    sdk: flutter
  test: ^1.31.0
''');

    expect(
      DependencyFirewall(root).check(),
      contains(contains('test is forbidden in runtime dependencies')),
    );
  });
}

void _writePolicy(Directory root) {
  Directory('${root.path}/tool').createSync(recursive: true);
  File('${root.path}/tool/dependency-policy.yaml').writeAsStringSync('''
schemaVersion: 1
testConstraint: '1.31.x'
packages:
  zuke_runner:
    requireRuntime: [test]
    rejectExactTestConstraint: true
  zuke_runner_flutter:
    requireRuntimeSdk: [flutter, flutter_test]
    forbiddenRuntime: [test]
''');
}

void _writePackage(Directory root, String name, String pubspec) {
  final path = Directory('${root.path}/packages/$name')
    ..createSync(recursive: true);
  File('${path.path}/pubspec.yaml').writeAsStringSync(pubspec);
  File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: test_workspace
workspace:
  - packages/$name
''');
}

Directory _findRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    if (File('${current.path}/docs/release-matrix.yaml').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate the Zuke workspace root');
    }
    current = parent;
  }
}
