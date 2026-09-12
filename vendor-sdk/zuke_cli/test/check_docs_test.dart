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

  test('accepts a complete current active SDK release surface', () {
    expect(DocumentationChecker(root).check(), isEmpty);
  });

  test(
    'accepts a retired package that has been removed from the workspace',
    () {
      final matrix = File('${root.path}/docs/release-matrix.yaml');
      matrix.writeAsStringSync(
        matrix.readAsStringSync().replaceFirst(
          'retiredPackages: {}',
          'retiredPackages:\n  removed_package: Consolidated into zuke_cli.',
        ),
      );

      expect(DocumentationChecker(root).check(), isEmpty);
    },
  );

  test('rejects path dependencies and retired identities', () {
    File(
      '${root.path}/vendor-sdk/zuke_frontend/pubspec.yaml',
    ).writeAsStringSync(
      'name: zuke_frontend\nversion: 0.2.1\nresolution: workspace\n'
      'dependencies:\n  yaml:\n    path: ../yaml\n',
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
            '// guide-snippet:sample:start\nvoid source() {}\n'
            '// guide-snippet:sample:end\n',
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

  test('rejects versioned current artifact discriminators in active libraries', () {
    final fixture = File('${root.path}/vendor-sdk/zuke_core/lib/src/current.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        "Map<String, Object?> toJson() => {'schemaVersion': 'zuke.current.v1'};\n",
      );

    expect(fixture.existsSync(), isTrue);
    expect(
      DocumentationChecker(root).check().join('\n'),
      contains('current Zuke artifacts must use an unversioned kind'),
    );
  });
}

void _writeBaseline(Directory root) {
  const packages = <String, Map<String, String>>{
    'zuke_core': {
      'version': '0.3.0',
      'previousVersion': '0.2.1',
      'action': 'publish',
      'tier': 'Shared infrastructure',
      'support':
          'Supported Zuke infrastructure dependency; applications normally use a primary SDK package.',
    },
    'zuke_annotations': {
      'version': '0.3.0',
      'previousVersion': '0.2.0',
      'action': 'publish',
      'tier': 'Narrow SDK',
      'support': 'Supported application-facing annotation API.',
    },
    'zuke_frontend': {
      'version': '0.2.0',
      'previousVersion': '0.1.1',
      'action': 'publish',
      'tier': 'Narrow SDK',
      'support': 'Supported frontend and configuration API.',
    },
    'zuke': {
      'version': '0.3.1',
      'previousVersion': '0.3.0',
      'action': 'publish',
      'tier': 'Primary SDK',
      'support': 'Primary pure-Dart Zuke SDK and supported facade.',
    },
    'zuke_runner': {
      'version': '0.3.1',
      'previousVersion': '0.3.0',
      'action': 'publish',
      'tier': 'Compatibility',
      'support': 'Compatibility package for the primary Zuke SDK.',
    },
    'zuke_runner_flutter': {
      'version': '0.3.1',
      'previousVersion': '0.3.0',
      'action': 'publish',
      'tier': 'Specialized SDK',
      'support': 'Supported Flutter testWidgets integration boundary.',
    },
    'zuke_http_runtime': {
      'version': '0.1.1',
      'previousVersion': '0.1.1',
      'action': 'reuse',
      'tier': 'Specialized SDK',
      'support': 'Supported application-facing HTTP runtime boundary.',
    },
    'zuke_cli': {
      'version': '0.4.0',
      'previousVersion': '0.3.1',
      'action': 'publish',
      'tier': 'Specialized SDK',
      'support':
          'Supported CLI for generation, extraction, validation, locks, and gates.',
    },
    'zuke_dart_build_hook': {
      'version': '0.3.0',
      'previousVersion': '0.2.0',
      'action': 'publish',
      'tier': 'Specialized SDK',
      'support': 'Supported optional package-owned build-time validation hook.',
    },
    'zuke_analyzer': {
      'version': '0.1.0',
      'previousVersion': '0.1.0',
      'action': 'internal',
      'tier': 'Repository tooling',
      'support': 'Repository-only analyzer plugin; not published to pub.dev.',
    },
    'zuke_conformance': {
      'version': '0.1.0',
      'previousVersion': '0.1.0',
      'action': 'internal',
      'tier': 'Repository tooling',
      'support':
          'Repository-only conformance tooling; not published to pub.dev.',
    },
    'zuke_test_support': {
      'version': '0.1.0',
      'previousVersion': '0.1.0',
      'action': 'internal',
      'tier': 'Repository tooling',
      'support': 'Repository-only test support; not published to pub.dev.',
    },
    'zuke_verifier': {
      'version': '0.1.0',
      'previousVersion': '0.1.0',
      'action': 'internal',
      'tier': 'Repository tooling',
      'support':
          'Repository-only verification tooling; not published to pub.dev.',
    },
  };
  final paths = <String>[];
  final matrix = StringBuffer('''schemaVersion: 2
sdk:
  dart: '>=3.10.0 <4.0.0'
operatingSystems: [linux, windows]
packages:
''');
  final publicationOrder = <String>[];
  for (final entry in packages.entries) {
    final directory = Directory('${root.path}/vendor-sdk/${entry.key}')
      ..createSync(recursive: true);
    paths.add('  - vendor-sdk/${entry.key}');
    final value = entry.value;
    final internal = value['action'] == 'internal';
    File('${directory.path}/pubspec.yaml').writeAsStringSync(
      'name: ${entry.key}\nversion: ${value['version']}\n'
      'resolution: workspace\n${internal ? 'publish_to: none\n' : ''}',
    );
    File(
      '${directory.path}/README.md',
    ).writeAsStringSync('# ${entry.key}\n${value['support']}\n');
    matrix
      ..writeln('  ${entry.key}:')
      ..writeln('    version: ${value['version']}')
      ..writeln('    previousVersion: ${value['previousVersion']}')
      ..writeln('    publish: ${internal ? 'false' : 'true'}')
      ..writeln('    releaseAction: ${value['action']}')
      ..writeln('    tier: ${value['tier']}')
      ..writeln('    supportStatement: ${value['support']}')
      ..writeln('    bumpReason: test fixture');
    if (!internal && value['action'] == 'publish') {
      publicationOrder.add(entry.key);
    }
  }
  File(
    '${root.path}/pubspec.yaml',
  ).writeAsStringSync('workspace:\n${paths.join('\n')}\n');
  File('${root.path}/README.md').writeAsStringSync('# root\n');
  Directory('${root.path}/docs').createSync(recursive: true);
  File('${root.path}/docs/release-matrix.yaml').writeAsStringSync(
    '${matrix}retiredPackages: {}\n'
    'compatibilityIds:\n'
    '  dart-frog: dart-frog-gen-2-route-topology-v1\n'
    '  dart-source: dart-source-package-v1\n'
    'contracts:\n'
    '  diagnostic: zuke.diagnostic-registry\n'
    '  commandResult: zuke.command-result\n'
    '  evidenceRecord: zuke.evidence-record\n'
    '  lock: zuke.lock\n'
    'publicationOrder:\n'
    '${publicationOrder.map((name) => '  - $name').join('\n')}\n',
  );
  File('${root.path}/docs/integration-guide.md').writeAsStringSync('# guide\n');
  File('${root.path}/docs/migration.md').writeAsStringSync(
    '''# Migrating to the Current Zuke Release

Previous package versions pinned until ready to migrate.
schema 3 sourcePackage sourceAdapter assurance/locks/pullRequest.lock.json
regenerate retired package
''',
  );
  Directory('${root.path}/examples').createSync(recursive: true);
  Directory('${root.path}/.github').createSync(recursive: true);
}
