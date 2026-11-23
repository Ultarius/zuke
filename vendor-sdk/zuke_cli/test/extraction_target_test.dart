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

    expect(resolvePlacement(root.path).target.id, 'backend');
  });

  test('preserves case in POSIX temporary workspace paths', () {
    final caseSensitiveRoot = Directory.systemTemp.createTempSync(
      'Zuke-Extraction-Target-',
    );
    addTearDown(() {
      if (caseSensitiveRoot.existsSync()) {
        caseSensitiveRoot.deleteSync(recursive: true);
      }
    });
    _writeWorkspace(caseSensitiveRoot, const ['backend']);

    expect(resolvePlacement(caseSensitiveRoot.path).target.id, 'backend');
  });

  test('uses an explicitly active target for multi-target membership', () {
    _writeWorkspace(root, const ['backend', 'flutter']);

    expect(
      resolvePlacement(root.path, requestedTarget: 'flutter').target.id,
      'flutter',
    );
  });

  test('rejects an active target outside package membership', () {
    _writeWorkspace(
      root,
      const ['backend', 'flutter'],
      packagePaths: {'flutter': 'packages/other'},
    );

    expect(
      () => resolvePlacement(root.path, requestedTarget: 'flutter'),
      throwsA(
        isA<PlacementFailure>().having(
          (error) => error.code,
          'code',
          'ZK-TARGET-NOT-MEMBER',
        ),
      ),
    );
  });

  test('rejects multi-target membership without an active target', () {
    _writeWorkspace(root, const ['backend', 'flutter']);

    expect(
      () => resolvePlacement(root.path),
      throwsA(
        isA<PlacementFailure>().having(
          (error) => error.code,
          'code',
          'ZK-TARGET-AMBIGUOUS',
        ),
      ),
    );
  });

  test('rejects a package that is not a configured member', () {
    _writeWorkspace(root, const ['backend'], packagePath: 'packages/other');

    expect(
      () => resolvePlacement(root.path),
      throwsA(
        isA<PlacementFailure>().having(
          (error) => error.code,
          'code',
          'ZK-TARGET-UNASSIGNED',
        ),
      ),
    );
  });

  test('an explicit workspace root takes precedence over a nearer config', () {
    _writeWorkspace(root, const ['backend'], packagePath: 'app');
    final package = Directory('${root.path}/app')..createSync();
    _writeWorkspace(package, const ['flutter'], packagePath: 'other');

    expect(
      resolvePlacement(
        package.path,
        explicitWorkspaceRoot: root.path,
      ).target.id,
      'backend',
    );
    expect(
      () => resolvePlacement(package.path),
      throwsA(
        isA<PlacementFailure>().having(
          (error) => error.code,
          'code',
          'ZK-TARGET-UNASSIGNED',
        ),
      ),
    );
  });

  test('rejects an explicit workspace root without a configuration', () {
    _writeWorkspace(root, const ['backend']);
    final empty = Directory('${root.path}/empty')..createSync();

    expect(
      () => resolvePlacement(root.path, explicitWorkspaceRoot: empty.path),
      throwsA(
        isA<PlacementFailure>()
            .having((error) => error.code, 'code', 'ZK-TARGET-UNASSIGNED')
            .having(
              (error) => error.message,
              'message',
              contains('no zuke.yaml'),
            ),
      ),
    );
  });

  test('never places a package through an absolute configured path', () {
    final workspace = Directory('${root.path}/workspace')..createSync();
    final outside = Directory('${root.path}/outside')..createSync();
    _writeWorkspace(workspace, const [
      'backend',
    ], packagePath: outside.absolute.path.replaceAll(r'\', '/'));

    expect(
      () =>
          resolvePlacement(outside.path, explicitWorkspaceRoot: workspace.path),
      throwsA(
        isA<PlacementFailure>().having(
          (error) => error.code,
          'code',
          'ZK-TARGET-UNASSIGNED',
        ),
      ),
    );
  });

  for (final (content, code) in const [
    ('targets: [\n', 'ZK-CONFIG-INVALID'),
    ('schemaVersion: 2\n', 'ZK-CONFIG-LEGACY-FORMAT'),
  ]) {
    test('reports an unusable workspace configuration as $code', () {
      File('${root.path}/zuke.yaml').writeAsStringSync(content);

      expect(
        () => resolvePlacement(root.path),
        throwsA(
          isA<PlacementFailure>().having((error) => error.code, 'code', code),
        ),
      );
    });
  }
}

void _writeWorkspace(
  Directory root,
  List<String> targets, {
  String packagePath = '.',
  Map<String, String> packagePaths = const {},
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
        path: ${packagePaths[target] ?? packagePath}
        roots: [lib]
''').join()}
''');
}
