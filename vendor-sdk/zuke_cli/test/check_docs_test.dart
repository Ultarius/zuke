import 'dart:io';

import 'package:test/test.dart';

import '../../check_docs.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zuke-doc-check-');
    _writeBaseline(root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('accepts a complete active SDK release surface', () {
    expect(DocumentationChecker(root).check(), isEmpty);
  });

  test('rejects path dependencies and retired identities', () {
    File(
      '${root.path}/vendor-sdk/zuke_frontend/pubspec.yaml',
    ).writeAsStringSync(
      'name: zuke_frontend\nversion: 0.1.0\nresolution: workspace\ndependencies:\n  yaml:\n    path: ../yaml\n',
    );
    File(
      '${root.path}/docs/current.md',
    ).writeAsStringSync('import `package:spec_runtime/runtime.dart`;\n');

    final failures = DocumentationChecker(root).check().join('\n');

    expect(failures, contains('path dependency'));
    expect(failures, contains('retired reference `spec_runtime`'));
  });

  test('rejects unclassified Dart fences and source drift', () {
    File(
      '${root.path}/docs/integration-guide.md',
    ).writeAsStringSync('```dart\nvoid main() {}\n```\n');
    expect(
      DocumentationChecker(root).check().join('\n'),
      contains('Dart fence needs snippet=<name> or pseudocode'),
    );

    File(
      '${root.path}/docs/integration-guide.md',
    ).writeAsStringSync('```dart snippet=sample\nvoid documented() {}\n```\n');
    final fixture =
        File(
            '${root.path}/examples/shopping_cart/test/guide_snippets/sample.dart',
          )
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(
            '// guide-snippet:sample:start\nvoid source() {}\n// guide-snippet:sample:end\n',
          );
    expect(fixture.existsSync(), isTrue);
    expect(
      DocumentationChecker(root).check().join('\n'),
      contains('guide snippet `sample` differs'),
    );
  });

  test('rejects an invalid YAML fence and missing tier contract', () {
    File(
      '${root.path}/docs/integration-guide.md',
    ).writeAsStringSync('```yaml\nkey: [\n```\n');
    File(
      '${root.path}/vendor-sdk/zuke_runner/README.md',
    ).writeAsStringSync('# zuke_runner\n');

    final failures = DocumentationChecker(root).check().join('\n');

    expect(failures, contains('invalid YAML fence'));
    expect(failures, contains('missing support-tier contract'));
  });

  test('rejects unsuppressed governed IDs in executable example tests', () {
    final fixture = File('${root.path}/examples/demo/test/raw_id_test.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync("const id = 'SCN-DEMO-ONE';\n");
    expect(
      DocumentationChecker(root).check().join('\n'),
      contains('governed IDs must use generated contracts'),
    );
    fixture.writeAsStringSync(
      '// zuke: allow-raw-id -- parser negative fixture\n'
      "const id = 'SCN-DEMO-ONE';\n",
    );
    expect(DocumentationChecker(root).check(), isEmpty);
  });
}

void _writeBaseline(Directory root) {
  const packageNames = <String>[
    'zuke_core',
    'zuke_conformance',
    'zuke_analyzer',
    'zuke_dart_build_hook',
    'zuke_annotations',
    'zuke_frontend',
    'zuke_http_runtime',
    'zuke_runner',
    'zuke_runner_flutter',
    'zuke_cli',
    'zuke_verifier',
    'zuke_test_support',
  ];
  final paths = <String>[];
  for (final name in packageNames) {
    final directory = Directory('${root.path}/vendor-sdk/$name')
      ..createSync(recursive: true);
    paths.add('  - vendor-sdk/$name');
    final tier = switch (name) {
      'zuke_core' =>
        'Supported Zuke infrastructure dependency; not a primary application package.',
      'zuke_analyzer' ||
      'zuke_conformance' ||
      'zuke_verifier' ||
      'zuke_test_support' =>
        'Repository-only tooling; not published to pub.dev.',
      _ => 'Supported application-facing public API.',
    };
    final publishTo = switch (name) {
      'zuke_analyzer' ||
      'zuke_conformance' ||
      'zuke_verifier' ||
      'zuke_test_support' => 'publish_to: none\n',
      _ => '',
    };
    File('${directory.path}/pubspec.yaml').writeAsStringSync(
      'name: $name\nversion: 0.1.0\nresolution: workspace\n$publishTo',
    );
    File('${directory.path}/README.md').writeAsStringSync('# $name\n$tier\n');
  }
  File('${root.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('workspace:\n${paths.join('\n')}\n');
  File('${root.path}/README.md').writeAsStringSync('# root\n');
  Directory('${root.path}/docs').createSync(recursive: true);
  File('${root.path}/docs/integration-guide.md').writeAsStringSync('# guide\n');
  Directory('${root.path}/examples').createSync(recursive: true);
  Directory('${root.path}/.github').createSync(recursive: true);
}
