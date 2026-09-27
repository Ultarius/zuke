import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/spec_lint_scan.dart';
import 'package:zuke_cli/src/tooling/dart_extractor/zuke_index.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'support/temporary_directory.dart';

void main() {
  group('Spec diagnostic scan', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('zuke-spec-lint-'));
    tearDown(() => deleteTemporaryDirectory(root));

    /// Writes a workspace whose single feature declares [featureTargets] as its
    /// targets. Declaring a target that zuke.yaml does not define is the cheapest
    /// way to produce a real reference finding.
    WorkspaceDiscoveryResult buildWorkspace({
      required List<String> featureTargets,
    }) {
      File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: spec-lint
  root: .
specifications:
  features:
    - specs/features/dashboard.feature
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: spec_lint_pkg
        path: .
        roots: [lib]
''');
      final features = Directory('${root.path}/specs/features')
        ..createSync(recursive: true);
      final targetBlock = featureTargets
          .map((target) => '#   - $target')
          .join('\n');
      File('${features.path}/dashboard.feature').writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-DASH-001
# targets:
$targetBlock
# spec-end
@FEAT-DASH-001
Feature: Dashboard
  # rule-spec-begin
  # id: RULE-DASH-ONE
  # rule-spec-end
  @RULE-DASH-ONE
  Rule: One rule
    @SCN-DASH-001
    Scenario: Works
      Given a step
''');
      return WorkspaceDiscovery().discover(root.path);
    }

    test(
      'an unknown target is recorded with a real specification location',
      () {
        final workspace = buildWorkspace(
          featureTargets: const ['backend', 'nope'],
        );
        final diagnostics = scanSpecDiagnostics(workspace, root: root.path);

        final unknownTarget = diagnostics.firstWhere(
          (diagnostic) => diagnostic.code == 'ZUKE-REF-009',
        );
        expect(unknownTarget.file, 'specs/features/dashboard.feature');
        // The location must be a real line in the file, not a default.
        expect(unknownTarget.line, greaterThan(0));
        expect(
          unknownTarget.featureId,
          'FEAT-DASH-001',
          reason: 'attribution comes from the spec file, not the message',
        );
        expect(unknownTarget.severity, 'error');
        expect(unknownTarget.message, contains('nope'));
      },
    );

    test('a workspace whose references all resolve records nothing', () {
      final workspace = buildWorkspace(featureTargets: const ['backend']);
      expect(scanSpecDiagnostics(workspace, root: root.path), isEmpty);
    });

    test('locations are workspace-relative and forward-slashed', () {
      final workspace = buildWorkspace(featureTargets: const ['nope']);
      final diagnostics = scanSpecDiagnostics(workspace, root: root.path);

      for (final diagnostic in diagnostics) {
        expect(diagnostic.file, isNot(startsWith('/')));
        expect(diagnostic.file, isNot(startsWith(r'C:')));
        expect(diagnostic.file, isNot(contains(r'\')));
        // A path recorded relative to the workspace is what makes the index
        // byte-identical in a different checkout.
        expect(diagnostic.file, startsWith('specs/'));
      }
    });

    test('a root that was not canonicalized cannot leak an absolute path', () {
      // `Directory('.').absolute.path` is `.../ws/.`, with a trailing `\.` that
      // no discovered path starts with. Relativizing against it fails, and the
      // old fallback then recorded the absolute path — which made the index
      // digest differ per invocation and per machine. A path that cannot be
      // expressed relatively is now dropped instead.
      final workspace = buildWorkspace(featureTargets: const ['nope']);
      final uncanonical = '${root.path}\\.';
      expect(
        uncanonical.endsWith('\\.'),
        isTrue,
        reason: 'guards the premise of this test',
      );

      expect(
        scanSpecDiagnostics(workspace, root: uncanonical),
        isEmpty,
        reason: 'no finding may be recorded with an un-relativizable root',
      );
    });

    test('the same findings and digest come from any root spelling', () {
      // The property that makes the index portable: `--root .`,
      // `--root <absolute>`, and a trailing separator must all agree, or
      // `zuke generate --check` fails depending on how it was invoked.
      final workspace = buildWorkspace(featureTargets: const ['nope']);
      final canonical = canonicalizeRoot(root.path);

      final byCanonical = scanSpecDiagnostics(workspace, root: canonical);
      final byAbsolute = scanSpecDiagnostics(workspace, root: root.path);
      final byTrailingSlash = scanSpecDiagnostics(
        workspace,
        root: '$canonical/',
      );

      expect(byCanonical, isNotEmpty);
      expect(byAbsolute.map((d) => d.key), byCanonical.map((d) => d.key));
      expect(byTrailingSlash.map((d) => d.key), byCanonical.map((d) => d.key));
    });
  });

  group('ZukeIndex spec diagnostics', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('zuke-spec-idx-'));
    tearDown(() => deleteTemporaryDirectory(root));

    ZukeIndex buildIndex({
      List<ZukeSpecDiagnostic> specDiagnostics = const [],
      Map<String, String> featureFiles = const {},
    }) {
      final config = File('${root.path}/zuke.yaml')
        ..writeAsStringSync('schemaVersion: 3\n');
      final manifest = File('${root.path}/generated-manifest.json')
        ..writeAsStringSync('{"files":[]}');
      return ZukeIndex.create(
        root: root.path,
        inputPaths: [config.path],
        generatedManifestContent: manifest.readAsStringSync(),
        generatedManifestPath: 'generated-manifest.json',
        requirementIds: const {'RULE-ONE'},
        controlIds: const {},
        bindingIds: const {},
        specDiagnostics: specDiagnostics,
        featureFiles: featureFiles,
      );
    }

    const finding = ZukeSpecDiagnostic(
      file: 'specs/features/dashboard.feature',
      line: 5,
      column: 5,
      code: 'ZUKE-REF-009',
      severity: 'error',
      message: 'Unknown target "nope"',
      featureId: 'FEAT-DASH-001',
    );

    test('findings and feature files survive a JSON round trip', () {
      final index = buildIndex(
        specDiagnostics: const [finding],
        featureFiles: const {
          'FEAT-DASH-001': 'lib/src/generated/feat_dash_001_contracts.g.dart',
        },
      );
      final restored = ZukeIndex.fromJson(
        Map<Object?, Object?>.from(
          jsonDecode(jsonEncode(index.toJson())) as Map,
        ),
      );

      expect(restored.specDiagnostics, hasLength(1));
      expect(restored.specDiagnostics.single.file, finding.file);
      expect(restored.specDiagnostics.single.line, 5);
      expect(restored.specDiagnostics.single.column, 5);
      expect(restored.specDiagnostics.single.code, 'ZUKE-REF-009');
      expect(restored.specDiagnostics.single.severity, 'error');
      expect(restored.specDiagnostics.single.featureId, 'FEAT-DASH-001');
      expect(restored.featureFiles, index.featureFiles);
    });

    test('a healthy workspace writes no specDiagnostics key at all', () {
      // The feature must be invisible in the index until something is wrong,
      // or every regenerated index churns for no reason.
      final index = buildIndex();
      expect(index.toJson().containsKey('specDiagnostics'), isFalse);
      expect(index.toJson().containsKey('featureFiles'), isFalse);
    });

    test('duplicate findings collapse and order is deterministic', () {
      final duplicated = buildIndex(
        specDiagnostics: const [
          finding,
          finding,
          ZukeSpecDiagnostic(
            file: 'specs/features/aaa.feature',
            line: 2,
            column: 1,
            code: 'ZUKE-REF-001',
            severity: 'error',
            message: 'Unknown Epic',
            featureId: 'FEAT-AAA-001',
          ),
        ],
      );

      expect(duplicated.specDiagnostics, hasLength(2));
      expect(
        duplicated.specDiagnostics.first.file,
        'specs/features/aaa.feature',
        reason: 'sorted so regenerating an unchanged workspace is stable',
      );
      // Sorting must not depend on input order.
      final reversed = buildIndex(
        specDiagnostics: const [
          ZukeSpecDiagnostic(
            file: 'specs/features/aaa.feature',
            line: 2,
            column: 1,
            code: 'ZUKE-REF-001',
            severity: 'error',
            message: 'Unknown Epic',
            featureId: 'FEAT-AAA-001',
          ),
          finding,
          finding,
        ],
      );
      expect(
        reversed.specDiagnostics.map((d) => d.key),
        duplicated.specDiagnostics.map((d) => d.key),
      );
      expect(
        reversed.inputDigest,
        duplicated.inputDigest,
        reason: 'the digest is what makes staleness detection work',
      );
    });

    test('a malformed finding is dropped without failing the read', () {
      final index = buildIndex(specDiagnostics: const [finding]);
      final json = Map<String, Object?>.from(index.toJson());
      json['specDiagnostics'] = [
        ...json['specDiagnostics']! as List,
        // Every one of these is unreadable in a different way.
        {
          'file': '',
          'line': 1,
          'code': 'X',
          'severity': 'error',
          'message': 'y',
        },
        {
          'file': 'a.feature',
          'line': 0,
          'code': 'X',
          'severity': 'error',
          'message': 'y',
        },
        {'file': 'a.feature', 'severity': 'error', 'message': 'no line'},
        {'line': 3, 'code': 'X', 'severity': 'error', 'message': 'no file'},
        {'file': 'a.feature', 'line': 2, 'code': 'X', 'message': 'no severity'},
        'not a map',
        null,
      ];
      // The missing-severity entry above is deliberately *readable*: it defaults
      // to error, which the next test pins.

      // A finding is advice, not a correctness input. Unreadable ones are
      // dropped so the other rules keep working, and the readable ones survive.
      final restored = ZukeIndex.fromJson(
        Map<Object?, Object?>.from(jsonDecode(jsonEncode(json)) as Map),
      );
      expect(restored.specDiagnostics, hasLength(2));
      expect(
        restored.specDiagnostics.map((d) => d.code),
        containsAll(['ZUKE-REF-009', 'X']),
      );
    });

    test('a missing severity defaults to error rather than dropping', () {
      final index = buildIndex(specDiagnostics: const [finding]);
      final json = Map<String, Object?>.from(index.toJson());
      final entries = json['specDiagnostics']! as List;
      json['specDiagnostics'] = [
        {'file': 'a.feature', 'line': 2, 'code': 'X', 'message': 'no severity'},
      ];

      final restored = ZukeIndex.fromJson(
        Map<Object?, Object?>.from(jsonDecode(jsonEncode(json)) as Map),
      );
      expect(restored.specDiagnostics, hasLength(1));
      expect(restored.specDiagnostics.single.severity, 'error');
      // The original entry is untouched: the guard only applies to the copy.
      expect(entries, hasLength(1));
    });

    test('featuresAtPath maps a generated file back to its feature', () {
      final index = buildIndex(
        featureFiles: const {
          'FEAT-DASH-001': 'lib/src/generated/feat_dash_001_contracts.g.dart',
          'FEAT-OTHER-001': 'lib/src/generated/feat_other_001_contracts.g.dart',
        },
      );

      expect(
        index.featuresAtPath(
          'lib/src/generated/feat_dash_001_contracts.g.dart',
        ),
        {'FEAT-DASH-001'},
      );
      expect(
        index.featuresAtPath(
          'lib/src/generated/feat_other_001_contracts.g.dart',
        ),
        {'FEAT-OTHER-001'},
      );
      // Hand-written Dart is never a generated contract, so it reports nothing
      // and the rule stays out of the way.
      expect(index.featuresAtPath('lib/src/dashboard_screen.dart'), isEmpty);
    });

    test('featuresAtPath tolerates a backslash path', () {
      final index = buildIndex(
        featureFiles: const {
          'FEAT-DASH-001': 'lib/src/generated/feat_dash_001_contracts.g.dart',
        },
      );
      expect(
        index.featuresAtPath(
          r'lib\src\generated\feat_dash_001_contracts.g.dart',
        ),
        {'FEAT-DASH-001'},
      );
    });
  });

  group('Spec diagnostic line anchoring', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('zuke-anchor-'));
    tearDown(() => deleteTemporaryDirectory(root));

    /// Builds a workspace whose feature and rule both reference values that do
    /// not exist, with a blank comment line inside each block so that any fixed
    /// offset would be wrong.
    List<ZukeSpecDiagnostic> scan() {
      File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: anchor
  root: .
specifications:
  features:
    - specs/features/authorized.feature
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: anchor
        path: .
        roots: [lib]
''');
      final features = Directory('${root.path}/specs/features')
        ..createSync(recursive: true);
      File('${features.path}/authorized.feature').writeAsStringSync(
        [
          '# spec-begin',
          '# schemaVersion: 1',
          '# id: FEAT-ANCHOR-001',
          '# targets:',
          '#',
          '#   - backend',
          '#',
          '#   - no_such_target',
          '# spec-end',
          '@FEAT-ANCHOR-001',
          'Feature: Authorized connection',
          '  # rule-spec-begin',
          '  # id: RULE-ANCHOR-001',
          '  # targets:',
          '  #   - also_no_such_target',
          '  # securityProfile: no-such-profile',
          '  # rule-spec-end',
          '  @RULE-ANCHOR-001',
          '  Rule: One',
          '    @SCN-ANCHOR-001',
          '    Scenario: Works',
          '      Given a step',
          '',
        ].join('\n'),
      );
      return scanSpecDiagnostics(
        WorkspaceDiscovery().discover(root.path),
        root: root.path,
      );
    }

    test('an unknown feature target is reported on its own line', () {
      final finding = scan().firstWhere(
        (d) => d.message.contains('no_such_target'),
      );
      // `#   - no_such_target` is line 8. The block starts at line 1, and a blank
      // comment line sits at 5, so neither the block start nor a fixed offset
      // would produce 8.
      expect(finding.line, 8);
      expect(finding.code, 'ZUKE-REF-009');
      expect(finding.featureId, 'FEAT-ANCHOR-001');
    });

    test('an unknown rule target is validated and reported on its own line', () {
      final finding = scan().firstWhere(
        (d) => d.message.contains('also_no_such_target'),
      );
      // `  #   - also_no_such_target` is line 15.
      expect(finding.line, 15);
      expect(finding.code, 'ZUKE-REF-009');
      // A rule target is validated, so the finding is attributed to the feature
      // that owns the rule and lands on that feature's contract.
      expect(finding.featureId, 'FEAT-ANCHOR-001');
    });

    test('an unknown security profile is reported on its own line', () {
      final finding = scan().firstWhere((d) => d.code == 'ZUKE-REF-008');
      // `  # securityProfile: no-such-profile` is line 16, while the rule block
      // starts at 12.
      expect(finding.line, 16);
      expect(finding.message, contains('no-such-profile'));
    });

    test('no finding is reported at a metadata block start', () {
      for (final finding in scan()) {
        expect(
          finding.line,
          isNot(anyOf(1, 12)),
          reason: 'block starts are the coarse fallback: ${finding.message}',
        );
      }
    });

    test('a target shared with a binding still points at the target line', () {
      // The regression this guards: keyed by value alone, a feature target and a
      // binding target spelled the same way share one entry, so the finding about
      // the target lands on the binding's line. Both are real lines in the right
      // block, so nothing looks wrong and the reported line is simply not the one
      // to edit.
      File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: anchor
  root: .
specifications:
  features:
    - specs/features/shared.feature
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: anchor
        path: .
        roots: [lib]
''');
      final features = Directory('${root.path}/specs/features')
        ..createSync(recursive: true);
      File('${features.path}/shared.feature').writeAsStringSync(
        [
          '# spec-begin',
          '# schemaVersion: 1',
          '# id: FEAT-SHARED-001',
          '# targets:',
          '#   - no_such_target',
          '# bindings:',
          '#   required:',
          '#     - id: binding.shared',
          '#       target: no_such_target',
          '# spec-end',
          '@FEAT-SHARED-001',
          'Feature: Shared target spelling',
          '  # rule-spec-begin',
          '  # id: RULE-SHARED-001',
          '  # rule-spec-end',
          '  @RULE-SHARED-001',
          '  Rule: One',
          '    @SCN-SHARED-001',
          '    Scenario: Works',
          '      Given a step',
          '',
        ].join('\n'),
      );

      final diagnostics = scanSpecDiagnostics(
        WorkspaceDiscovery().discover(root.path),
        root: root.path,
      );
      final targetFinding = diagnostics.firstWhere(
        (d) => d.message.contains('no_such_target') && d.code == 'ZUKE-REF-009',
      );
      // `#   - no_such_target` is line 5; the binding's identical target is line 9.
      expect(targetFinding.line, 5);
    });
  });

  group('ZukeIndex.relativeToRoot', () {
    test('returns the path under the root', () {
      expect(
        ZukeIndex.relativeToRoot('/repo', '/repo/lib/src/app.dart'),
        'lib/src/app.dart',
      );
      expect(
        ZukeIndex.relativeToRoot(r'C:\repo', r'C:\repo\lib\src\app.dart'),
        'lib/src/app.dart',
      );
      expect(
        ZukeIndex.relativeToRoot('/repo/', '/repo/lib/a.dart'),
        'lib/a.dart',
      );
    });

    test('refuses a path that merely shares a prefix', () {
      // `/repo-other` starts with `/repo` but is a different tree. Slicing it
      // would yield `other/lib/a.dart`, which looks relative and silently
      // attributes the file to the wrong target.
      expect(
        ZukeIndex.relativeToRoot('/repo', '/repo-other/lib/a.dart'),
        isNull,
      );
      expect(ZukeIndex.relativeToRoot('/repo', 'C:/repo/lib/a.dart'), isNull);
      expect(ZukeIndex.relativeToRoot('/repo', '/repo'), isNull);
      expect(ZukeIndex.relativeToRoot('/repo', '/repository/a.dart'), isNull);
      expect(ZukeIndex.relativeToRoot('', '/repo/a.dart'), isNull);
    });

    test('a trailing separator on the root is not part of it', () {
      expect(
        ZukeIndex.relativeToRoot('/repo/', '/repo/lib/a.dart'),
        'lib/a.dart',
      );
      expect(ZukeIndex.relativeToRoot('/repo///', '/repo'), isNull);
    });

    test('matching tolerates case only where the filesystem does', () {
      final windows = Platform.isWindows;
      // A case mismatch must not silently disable every rule that depends on
      // this. The failure mode of ignoring it looks like "no diagnostics
      // configured" rather than "wrong case".
      expect(
        ZukeIndex.relativeToRoot(
          windows ? r'C:\Repo' : '/repo',
          windows ? r'c:\repo\lib\a.dart' : '/repo/lib/a.dart',
        ),
        'lib/a.dart',
      );
      if (windows) {
        // The returned substring keeps the caller's casing, not the root's, and
        // is forward-slashed like every other path in the index.
        expect(
          ZukeIndex.relativeToRoot(r'C:\Repo', r'c:\repo\Lib\A.dart'),
          'Lib/A.dart',
        );
      }
      // Case never rescues a genuinely different directory.
      expect(
        ZukeIndex.relativeToRoot('/repo', '/Repo-Other/lib/a.dart'),
        isNull,
      );
    });
  });
}
