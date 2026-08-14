import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/tooling.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zuke-extraction-target-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('resolves the only package membership without a provider target', () {
    _writeWorkspace(root, const ['backend']);

    expect(resolveExtractionTarget(root.path), 'backend');
  });

  test('uses an explicitly active target for multi-target membership', () {
    _writeWorkspace(root, const ['backend', 'flutter']);

    expect(
      resolveExtractionTarget(root.path, requestedTarget: 'flutter'),
      'flutter',
    );
  });

  test('rejects multi-target membership without an active target', () {
    _writeWorkspace(root, const ['backend', 'flutter']);

    expect(
      () => resolveExtractionTarget(root.path),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('ZK-PROVIDER-TARGET-AMBIGUOUS'),
        ),
      ),
    );
  });

  test('rejects a package that is not a configured member', () {
    _writeWorkspace(root, const ['backend'], packagePath: 'packages/other');

    expect(
      () => resolveExtractionTarget(root.path),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('ZK-PROVIDER-TARGET-AMBIGUOUS'),
        ),
      ),
    );
  });
}

void _writeWorkspace(
  Directory root,
  List<String> targets, {
  String packagePath = '.',
}) {
  File('${root.path}${Platform.pathSeparator}zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: target-test
  root: .
specifications:
  features: []
targets:
${targets.map((target) => '''  $target:
    language: dart
    framework: dart
    packages:
      - id: sample
        path: $packagePath
        roots: [lib]
''').join()}
''');
}
