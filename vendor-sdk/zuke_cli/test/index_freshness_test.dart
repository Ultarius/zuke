import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/tooling.dart';

import 'support/temporary_directory.dart';
import 'support/resolved_workspace.dart';

void main() {
  group('Analyzer index freshness', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('zuke-fresh-'));
    tearDown(() => deleteTemporaryDirectory(root));

    /// A workspace whose single package implements its rule through a constant
    /// declared in the generated contract — the shape the examples use, and the
    /// one that made a first generation report itself stale.
    Future<void> writeWorkspace() async {
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: freshness_fixture\n'
        'environment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );
      File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: freshness
  root: .
specifications:
  features:
    - specs/features/f.feature
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: freshness_pkg
        path: .
        roots: [lib]
''');
      final features = Directory('${root.path}/specs/features')
        ..createSync(recursive: true);
      File('${features.path}/f.feature').writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-FRESH-001
# spec-end
@FEAT-FRESH-001
Feature: Freshness
  # rule-spec-begin
  # id: RULE-FRESH-ONE
  # rule-spec-end
  @RULE-FRESH-ONE
  Rule: One
    @SCN-FRESH-001
    Scenario: Works
      Given a step
''');
      final lib = Directory('${root.path}/lib/src')
        ..createSync(recursive: true);
      File('${lib.path}/service.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'generated/feat_fresh_001_contracts.g.dart';

class Service {
  @ImplementsRequirement([FeatFresh001RequirementIds.one])
  void run() {}
}
''');
      await configureFixturePackages(root);
    }

    ZukeIndex readIndex() =>
        ZukeIndex.read(File('${root.path}/.zuke/analyzer-index.json'));

    test(
      'a first generation already resolves the contract it just wrote',
      () async {
        await writeWorkspace();
        // Nothing is generated yet, so the contract constant cannot resolve from
        // disk. The index must still record the implementation, because it was
        // built from the content generation was about to write.
        final result = _generate(root.path);
        expect(result, 0);

        final index = readIndex();
        expect(
          index.implementationClaims.map((claim) => claim.id),
          contains('RULE-FRESH-ONE'),
          reason: 'the contract constant must resolve against pending content',
        );
        expect(index.isCurrent(root: root.path), isTrue);
      },
    );

    test('changing a constant-only source is detected as stale', () async {
      await writeWorkspace();
      expect(_generate(root.path), 0);
      expect(readIndex().isCurrent(root: root.path), isTrue);

      // A file that only *defines* a constant cannot change any annotation, so
      // nothing in the index used to move. It still changes what the annotation
      // resolves to, so freshness has to notice.
      File(
        '${root.path}/lib/src/ids.dart',
      ).writeAsStringSync("const ruleIds = ['RULE-SOMETHING-ELSE'];\n");
      final before = readIndex();
      expect(
        before.isCurrent(root: root.path),
        isFalse,
        reason:
            'adding a Dart source file must invalidate the source inventory',
      );
      expect(_generate(root.path), 0);
      expect(
        readIndex().inputs.map((input) => input.path),
        contains('lib/src/ids.dart'),
        reason: 'a constant-only source belongs in the inventory',
      );

      File(
        '${root.path}/lib/src/ids.dart',
      ).writeAsStringSync("const ruleIds = ['RULE-ANOTHER'];\n");
      expect(
        readIndex().isCurrent(root: root.path),
        isFalse,
        reason: 'editing it must invalidate the index',
      );
    });

    test('a root that is an alias of the real path is not stale', () {
      // The specification inventory is matched by walking the root as it was
      // spelled and comparing against the resolved one. When those differ the
      // walk matches nothing, every input looks deleted, and a freshly generated
      // index reports itself stale on the next command. macOS hits this with
      // `/var` against `/private/var`, and Windows CI with 8.3 aliases such as
      // `RUNNER~1`, so the check has to accept either spelling.
      final alias = _aliasDirectory(root.path);
      if (alias == null) {
        markTestSkipped('could not create a directory alias on this platform');
        return;
      }
      addTearDown(() {
        if (Directory(alias).existsSync()) {
          Directory(alias).deleteSync(recursive: true);
        }
      });

      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: freshness_fixture\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );
      File('${root.path}/zuke.yaml').writeAsStringSync('schemaVersion: 3\n');
      final features = Directory('${root.path}/specs/features')
        ..createSync(recursive: true);
      File('${features.path}/f.feature').writeAsStringSync(
        '@FEAT-FRESH-001\nFeature: Freshness\n'
        '  @RULE-FRESH-ONE\n  Rule: One\n    @SCN-FRESH-001\n'
        '    Scenario: Works\n      Given a step\n',
      );
      final manifest = File('${root.path}/generated-manifest.json')
        ..writeAsStringSync('{"files":[]}');
      Directory('${root.path}/.zuke').createSync(recursive: true);

      // Built from the real path, then judged through the alias: the two are the
      // same directory, so the index must still be current.
      final index = ZukeIndex.create(
        root: root.path,
        inputPaths: [
          File('${root.path}/zuke.yaml').path,
          File('${features.path}/f.feature').path,
        ],
        inputPatterns: ['specs/features/*.feature'],
        patternInputPaths: [File('${features.path}/f.feature').path],
        generatedManifestContent: manifest.readAsStringSync(),
        generatedManifestPath: 'generated-manifest.json',
        requirementIds: const {},
        controlIds: const {},
        bindingIds: const {},
      );

      // Guards the premise of the assertions below: with no recorded pattern
      // inventory there is nothing to compare, and the test would pass whatever
      // the walker did.
      expect(
        index.patternInputs,
        {'specs/features/f.feature'},
        reason: 'the specification inventory must actually be recorded',
      );

      final issues = index.freshnessIssues(root: alias);
      expect(
        issues.map((issue) => '${issue.kind}: ${issue.message}'),
        isEmpty,
        reason: 'an aliased root is the same directory, not a changed one',
      );
      expect(index.isCurrent(root: alias), isTrue);
    });
  });
}

/// A second path to [real] that resolves to the same directory, or null when the
/// platform or the environment will not allow one.
String? _aliasDirectory(String real) {
  final alias = '$real-alias';
  if (Platform.isWindows) {
    final result = Process.runSync('cmd', ['/c', 'mklink', '/J', alias, real]);
    return result.exitCode == 0 ? alias : null;
  }
  try {
    Link(alias).createSync(real);
    return alias;
  } on FileSystemException {
    return null;
  }
}

int _generate(String root) {
  final result = Process.runSync(Platform.resolvedExecutable, [
    '--suppress-analytics',
    'run',
    'zuke_cli:zuke',
    'generate',
    '--root',
    root,
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    fail('generate failed:\n${result.stdout}\n${result.stderr}');
  }
  return result.exitCode;
}
