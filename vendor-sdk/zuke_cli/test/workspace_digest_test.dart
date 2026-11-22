import 'dart:io';

import 'package:zuke_cli/src/workspace_digest.dart';
import 'package:zuke_cli/src/ir.dart';
import 'package:zuke_frontend/zuke_frontend.dart'
    show GherkinParser, GherkinSyntax;
import 'package:test/test.dart';

void main() {
  late Directory workspace;

  File writeFile(String relativePath, String contents) {
    final file = File('${workspace.path}/$relativePath');
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync(contents);
  }

  Future<String> digest({Iterable<String> generatedPaths = const []}) =>
      WorkspaceDigest(generatedPaths: generatedPaths).compute(workspace);

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('zuke-workspace-digest-');
    writeFile('zuke.yaml', 'schemaVersion: 3\n');
    writeFile('lib/source.dart', 'const value = 1;\n');
  });

  tearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  test('is deterministic and changes for repository input changes', () async {
    final first = await digest();
    expect(await digest(), first);

    writeFile('lib/source.dart', 'const value = 2;\n');
    expect(await digest(), isNot(first));
  });

  test('hashes only discovered specification inputs when requested', () {
    final config = writeFile('zuke.yaml', 'schemaVersion: 3\n');
    final feature = writeFile(
      'specs/features/example.feature',
      'Feature: One\n  Scenario: Works\n    Given a step\n',
    );
    final inputs = <String, String>{
      config.path: config.readAsStringSync(),
      feature.path: feature.readAsStringSync(),
    };
    final before = WorkspaceDigest.computeInputContents(workspace, inputs);

    writeFile('lib/source.dart', 'const unrelatedSource = 2;\n');
    expect(WorkspaceDigest.computeInputContents(workspace, inputs), before);

    inputs[feature.path] =
        'Feature: Two\n  Scenario: Also works\n    Given a step\n';
    expect(
      WorkspaceDigest.computeInputContents(workspace, inputs),
      before,
      reason: 'feature and scenario titles are prose, not structure',
    );

    inputs[feature.path] =
        'Feature: One\n  Scenario: Works\n    Given another step\n';
    expect(
      WorkspaceDigest.computeInputContents(workspace, inputs),
      isNot(before),
      reason: 'step text changes what executes',
    );
  });

  test('normalizes CRLF for text inputs but preserves binary bytes', () async {
    final feature = writeFile(
      'specs/features/example.feature',
      'Feature: One\n',
    );
    final lf = <String, String>{
      feature.path: 'Feature: One\n',
      '${workspace.path}/zuke.yaml': 'schemaVersion: 3\n',
    };
    final crlf = <String, String>{
      feature.path: 'Feature: One\r\n',
      '${workspace.path}/zuke.yaml': 'schemaVersion: 3\r\n',
    };
    expect(
      WorkspaceDigest.computeInputContents(workspace, lf),
      WorkspaceDigest.computeInputContents(workspace, crlf),
    );

    feature.writeAsStringSync('Feature: One\r\n');
    final crlfWorkspace = await digest();
    feature.writeAsStringSync('Feature: One\n');
    expect(await digest(), crlfWorkspace);

    final mapping = writeFile('mapping.yaml', 'a: 1\r\n');
    final crlfFiltered = WorkspaceDigest.computeFiltered(
      workspace.path,
      (path) => path == 'mapping.yaml',
    );
    mapping.writeAsStringSync('a: 1\n');
    expect(
      WorkspaceDigest.computeFiltered(
        workspace.path,
        (path) => path == 'mapping.yaml',
      ),
      crlfFiltered,
    );
    final binary = File('${workspace.path}/data.bin')
      ..writeAsBytesSync([13, 10]);
    expect(canonicalDigestBytes(binary.path, binary.readAsBytesSync()), [
      13,
      10,
    ]);
    expect(canonicalDigestBytes('invalid.yaml', [0xff]), [0xff]);
  });

  test('prunes tool, evidence, IDE, and platform outputs', () async {
    final before = await digest();
    const ignoredFiles = <String>[
      '.dart_tool/package_config.json',
      '.git/index',
      '.gradle/executionHistory.bin',
      '.idea/workspace.xml',
      '.zuke/analyzer-index.json',
      '.zuke/evidence/records/result.json',
      '.plugin_symlinks/plugin/file.dart',
      '.symlinks/plugin/file.dart',
      '.cxx/debug/object.o',
      '.externalNativeBuild/state.bin',
      'Pods/Manifest.lock',
      'assurance-history/v2/record.json',
      'build/output.bin',
      'coverage/lcov.info',
      'dist/archive.zip',
      'generated/evidence/record.json',
      'node_modules/package/index.js',
      'windows/flutter/ephemeral/flutter_windows.dll.pdb',
      'android/local.properties',
      'project.iml',
      '.flutter-plugins',
      '.flutter-plugins-dependencies',
      'pubspec_overrides.yaml',
    ];
    for (final path in ignoredFiles) {
      writeFile(path, 'ignored: $path\n');
    }

    expect(await digest(), before);
    for (final path in ignoredFiles) {
      writeFile(path, 'changed but still ignored: $path\n');
    }
    expect(await digest(), before);
  });

  test('excludes every generated manifest path and the lock file', () async {
    writeFile('lib/contracts.dart', 'generated v1\n');
    writeFile('custom.lock.json', 'lock v1\n');
    final before = await WorkspaceDigest(
      lockFile: 'custom.lock.json',
      generatedPaths: const ['lib/contracts.dart'],
    ).compute(workspace);

    writeFile('lib/contracts.dart', 'generated v2\n');
    writeFile('custom.lock.json', 'lock v2\n');
    expect(
      await WorkspaceDigest(
        lockFile: 'custom.lock.json',
        generatedPaths: const [r'lib\contracts.dart'],
      ).compute(workspace),
      before,
    );
  });

  test('does not follow file-system links', () async {
    final external = Directory.systemTemp.createTempSync(
      'zuke-workspace-digest-external-',
    );
    addTearDown(() {
      if (external.existsSync()) external.deleteSync(recursive: true);
    });
    final externalFile = File('${external.path}/outside.txt')
      ..writeAsStringSync('outside v1\n');
    final link = Link('${workspace.path}/linked');
    try {
      link.createSync(external.path);
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable in this environment.');
      return;
    }

    final before = await digest();
    externalFile.writeAsStringSync('outside v2\n');
    expect(await digest(), before);
  });

  test('prunes a large ignored file before reading it', () async {
    final before = await digest();
    final file = writeFile(
      'windows/flutter/ephemeral/large-debug-symbols.pdb',
      '',
    );
    final handle = file.openSync(mode: FileMode.write);
    try {
      handle.truncateSync(256 * 1024 * 1024);
    } finally {
      handle.closeSync();
    }

    expect(await digest(), before);
  });

  test('streams a large included file deterministically', () async {
    final file = writeFile('assets/large-input.bin', '');
    final handle = file.openSync(mode: FileMode.write);
    try {
      handle.truncateSync(16 * 1024 * 1024);
    } finally {
      handle.closeSync();
    }

    final first = await digest();
    expect(await digest(), first);
  });

  test('computeFilteredMany matches per-predicate computeFiltered', () {
    writeFile('specs/registry/events.yaml', 'events: []\n');
    writeFile('specs/features/example.feature', 'Feature: One\n');
    writeFile('policies/project-policy.yaml', 'policy: strict\n');
    writeFile('lib/source.dart', 'const other = 1;\n');

    final includes = <String, bool Function(String)>{
      'mapping': WorkspaceDigest.evidenceMappingInclude,
      'specificationIndex': WorkspaceDigest.evidenceSpecificationInclude,
      'unrelated': (path) => path.endsWith('missing.yaml'),
    };

    final many = WorkspaceDigest.computeFilteredMany(workspace.path, includes);
    for (final entry in includes.entries) {
      expect(
        many[entry.key],
        WorkspaceDigest.computeFiltered(workspace.path, entry.value),
        reason: 'bucket ${entry.key}',
      );
    }
    expect(
      many['mapping'],
      WorkspaceDigest.computeEvidenceIndexDigests(workspace.path)['mapping'],
    );
    expect(
      many['specificationIndex'],
      WorkspaceDigest.computeEvidenceIndexDigests(
        workspace.path,
      )['specificationIndex'],
    );
  });

  test('computeFilteredMany returns empty digests for a missing root', () {
    final missing = '${workspace.path}/does-not-exist';
    final many = WorkspaceDigest.computeFilteredMany(missing, {
      'mapping': WorkspaceDigest.evidenceMappingInclude,
    });
    expect(
      many['mapping'],
      WorkspaceDigest.computeFiltered(
        missing,
        WorkspaceDigest.evidenceMappingInclude,
      ),
    );
  });

  test('filtered digests prune ignored tool and platform directories', () {
    writeFile('specs/features/example.feature', 'Feature: One\n');
    final before = WorkspaceDigest.computeEvidenceIndexDigests(workspace.path);

    writeFile('build/specs/features/stale.feature', 'Feature: Stale\n');
    writeFile('.dart_tool/specs/registry/noise.yaml', 'noise: true\n');
    writeFile('generated/policies/noise.yaml', 'noise: true\n');
    writeFile('node_modules/specs/features/noise.feature', 'noise\n');
    writeFile('windows/flutter/ephemeral/specs/noise.feature', 'noise\n');

    expect(WorkspaceDigest.computeEvidenceIndexDigests(workspace.path), before);
    expect(
      WorkspaceDigest.computeFiltered(
        workspace.path,
        WorkspaceDigest.evidenceSpecificationInclude,
      ),
      WorkspaceDigest.computeFilteredMany(workspace.path, {
        'specificationIndex': WorkspaceDigest.evidenceSpecificationInclude,
      })['specificationIndex'],
    );
  });

  test('filtered digests cover spec folders named like build artifacts', () {
    Map<String, String> digests() =>
        WorkspaceDigest.computeEvidenceIndexDigests(workspace.path);

    for (final name in const ['build', 'coverage', 'dist', 'generated']) {
      final path = 'specs/features/$name/report.feature';
      writeFile(path, 'Feature: One\n  Scenario: A\n    Given one\n');
      final before = digests()['specificationIndex'];
      writeFile(path, 'Feature: One\n  Scenario: A\n    Given two\n');
      expect(digests()['specificationIndex'], isNot(before), reason: path);

      final policy = 'policies/$name/policy.yaml';
      writeFile(policy, 'value: 1\n');
      final mappingBefore = digests()['mapping'];
      writeFile(policy, 'value: 2\n');
      expect(digests()['mapping'], isNot(mappingBefore), reason: policy);
    }
  });

  test('a doc string the parser executes is never dropped as prose', () {
    String feature(String value, {String mediaType = 'json'}) => <String>[
      '# spec-begin',
      '# schemaVersion: 1',
      '# id: FEAT-ONE-001',
      '# spec-end',
      'Feature: One',
      '  # rule-spec-begin',
      '  # id: RULE-ONE-001',
      '  # rule-spec-end',
      '  Rule: Does things',
      '    Scenario: Doc strings',
      '      Given a payload',
      '        """$mediaType',
      '        {"amount": $value}',
      '        """',
      '      Then the value is shown',
      '',
    ].join('\n');

    final parsed = GherkinParser().parseFile(feature('5'), 'x.feature');
    expect(parsed.errors, isEmpty);
    final step =
        parsed.features.single.rules.single.scenarios.single.steps.first;
    expect(step.docStringMediaType, 'json');
    expect(step.docString, contains('{"amount": 5}'));
    final projection = WorkspaceDigest.structuralFeatureText(feature('5'));
    expect(
      WorkspaceDigest.structuralFeatureText(feature('6')),
      isNot(projection),
    );
    expect(
      WorkspaceDigest.structuralFeatureText(feature('5', mediaType: 'text')),
      isNot(projection),
    );
  });

  group('Examples tables', () {
    String feature(String table) => <String>[
      '# spec-begin',
      '# schemaVersion: 1',
      '# id: FEAT-ONE-001',
      '# spec-end',
      'Feature: One',
      '  # rule-spec-begin',
      '  # id: RULE-ONE-001',
      '  # rule-spec-end',
      '  Rule: Does things',
      '    Scenario Outline: Adds <value>',
      '      Given a value <value>',
      '      Examples:',
      table,
      '',
    ].join('\n');
    int cases(String content) => GherkinParser()
        .parseFile(content, 'x.feature')
        .features
        .single
        .rules
        .single
        .scenarios
        .single
        .examples
        .single
        .rows
        .length;
    const clean =
        '        | value |\n        | 1 |\n        | 2 |\n        | 3 |';

    test('a comment between rows keeps every case and the digest', () {
      final commented = feature(
        '        | value |\n        | 1 |\n        # note\n'
        '        | 2 |\n        | 3 |',
      );
      expect(cases(commented), 3);
      expect(
        WorkspaceDigest.structuralFeatureText(commented),
        WorkspaceDigest.structuralFeatureText(feature(clean)),
      );
    });

    test('content that removes cases changes the digest', () {
      final truncated = feature(
        '        | value |\n        | 1 |\n        stray text\n'
        '        | 2 |\n        | 3 |',
      );
      expect(cases(truncated), 1);
      expect(
        WorkspaceDigest.structuralFeatureText(truncated),
        isNot(WorkspaceDigest.structuralFeatureText(feature(clean))),
      );
    });
  });

  test('a delimiter before any step does not misalign doc strings', () {
    final projected = WorkspaceDigest.structuralFeatureText(
      <String>[
        'Feature: One',
        '  Scenario: Stray delimiter',
        '    """',
        '    Given a value',
        '      """',
        '      executed content',
        '      """',
        '',
      ].join('\n'),
    );
    expect(projected, contains('executed content'));
  });

  test('a doc-string opener in prose does not hide later structure', () {
    final projection = WorkspaceDigest.structuralFeatureText('''
Feature: One
  Given is the keyword for a precondition.
  """json
  Rule: Stores a document
    Scenario: Carries a document
      Given a document
''');

    expect(projection.split('\n'), containsAll(['Rule:', 'Scenario:']));
  });

  test('specification digest ignores prose edits but not step edits', () {
    const original = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-ONE-001
# spec-end

@FEAT-ONE-001
Feature: One
  A description of the feature.

  # a note about the rule
  @RULE-ONE-001
  Rule: Does things
    @SCN-ONE-001
    Scenario: Add a task
      When the user taps "add task button"
''';
    String specificationDigest() => WorkspaceDigest.computeEvidenceIndexDigests(
      workspace.path,
    )['specificationIndex']!;

    writeFile('specs/features/example.feature', original);
    final before = specificationDigest();

    writeFile(
      'specs/features/example.feature',
      original
          .replaceFirst('Feature: One', 'Feature: A whole new name')
          .replaceFirst(
            'A description of the feature.',
            'An entirely different description.',
          )
          .replaceFirst('  # a note about the rule', '  # reworded note')
          .replaceFirst('Scenario: Add a task', 'Scenario: Create a task'),
    );
    expect(specificationDigest(), before, reason: 'prose is not structure');

    writeFile(
      'specs/features/example.feature',
      original.replaceFirst('the user taps', 'the user presses'),
    );
    expect(specificationDigest(), isNot(before), reason: 'steps are structure');

    writeFile(
      'specs/features/example.feature',
      original.replaceFirst('@SCN-ONE-001', '@SCN-ONE-002'),
    );
    expect(specificationDigest(), isNot(before), reason: 'tags are structure');

    writeFile(
      'specs/features/example.feature',
      original.replaceFirst('# id: FEAT-ONE-001', '# id: FEAT-TWO-001'),
    );
    expect(
      specificationDigest(),
      isNot(before),
      reason: 'spec metadata is structure',
    );
  });

  test('structuralFeatureText keeps structure and drops prose', () {
    const content = '''
# spec-begin
# schemaVersion: 1
# id: FEAT-ONE-001
# spec-end
Feature: One
  Free-text description of the feature.
  # an ordinary comment
@FEAT-ONE-001
Rule: Does things
  Background:
    Given the catalog is open
  Scenario Outline: Covers <case>
    Given the catalog is open
    When the user asks for <case>
    Then the answer is shown
      """
      expected
      """
    Examples:
      | case |
      | sum  |
''';
    final projected = WorkspaceDigest.structuralFeatureText(content);

    expect(projected, contains('# id: FEAT-ONE-001'));
    expect(projected, contains('Feature:'));
    expect(projected, contains('Rule:'));
    expect(projected, contains('Background:'));
    expect(projected, contains('Scenario Outline:'));
    expect(projected, contains('Given the catalog is open'));
    expect(projected, contains('| case |'));
    expect(projected, contains('"""'));
    expect(projected, contains('expected'));

    expect(projected, isNot(contains('Feature: One')));
    expect(projected, isNot(contains('Free-text description')));
    expect(projected, isNot(contains('ordinary comment')));
    expect(projected, isNot(contains('Covers <case>')));
  });

  test('structuralFeatureText keeps every keyword the parser accepts', () {
    for (final keyword in GherkinSyntax.keywords) {
      expect(
        WorkspaceDigest.structuralFeatureText('$keyword A title\n'),
        keyword,
        reason:
            '$keyword is in the shared vocabulary but not in the '
            'projection',
      );
    }
    for (final keyword in GherkinSyntax.stepKeywords) {
      expect(
        WorkspaceDigest.structuralFeatureText('$keyword a step\n'),
        '$keyword a step',
        reason:
            '$keyword is in the shared vocabulary but not in the '
            'projection',
      );
    }
  });

  test('structuralFeatureText closes a doc string on its own fence', () {
    final content = <String>[
      'Feature: One',
      '  Scenario: Doc strings',
      '    Given a value',
      '      """',
      "      '''",
      '      a line with a different fence is still content',
      '      """',
      '    Then the value is shown',
      '',
    ].join('\n');
    final projected = WorkspaceDigest.structuralFeatureText(content);
    expect(
      projected,
      contains('a line with a different fence is still content'),
    );
    expect(projected, contains('Then the value is shown'));
  });

  test('structuralFeatureText reads metadata markers in a doc string as '
      'content', () {
    String feature(String comment) => <String>[
      'Feature: One',
      '  Scenario: Doc strings',
      '    Given a value',
      '      """',
      '      # spec-begin',
      '      """',
      '    # $comment',
      '    Then the value is shown',
      '',
    ].join('\n');
    // A marker that opened a metadata block would keep the comment that
    // follows, so a wording-only edit would make evidence stale.
    expect(
      WorkspaceDigest.structuralFeatureText(feature('first wording')),
      WorkspaceDigest.structuralFeatureText(feature('second wording')),
    );
  });

  test('evidence layouts never sit under pruned directory names', () {
    const ignored = <String>{
      '.dart_tool',
      '.git',
      '.gradle',
      '.idea',
      '.plugin_symlinks',
      '.zuke',
      '.symlinks',
      '.cxx',
      '.externalNativeBuild',
      'Pods',
      'assurance-history',
      'build',
      'coverage',
      'dist',
      'generated',
      'node_modules',
    };
    const legitimateEvidencePaths = <String>[
      'specs/registry/events.yaml',
      'specs/features/example.feature',
      'policies/project-policy.yaml',
      'zuke.yaml',
    ];
    for (final path in legitimateEvidencePaths) {
      expect(
        WorkspaceDigest.evidenceMappingInclude(path) ||
            WorkspaceDigest.evidenceSpecificationInclude(path),
        isTrue,
        reason: path,
      );
      final directorySegments = path.split('/')..removeLast();
      expect(
        directorySegments.where(ignored.contains),
        isEmpty,
        reason: '$path must not live under a pruned directory',
      );
    }
    // Tool trees may contain decoy names; the pruned walk must not hash them.
    expect(
      WorkspaceDigest.evidenceMappingInclude('node_modules/zuke.yaml'),
      isTrue,
    );
    expect(
      WorkspaceDigest.evidenceSpecificationInclude(
        'build/specs/features/example.feature',
      ),
      isFalse,
    );
  });
}
