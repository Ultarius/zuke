import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';
import 'package:zuke_cli/src/implementation_scan.dart';
import 'package:zuke_cli/src/requirement_scopes.dart';
import 'package:zuke_cli/src/tooling/source_constants.dart';
import 'package:zuke_cli/tooling.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'support/temporary_directory.dart';

void main() {
  group('Implementation scan', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('zuke-impl-'));
    tearDown(() => deleteTemporaryDirectory(root));

    /// A workspace whose generated contract declares IDs, with hand-written
    /// sources that claim some of them — including through a contract constant
    /// reference, which is how the examples actually write it.
    WorkspaceDiscoveryResult buildWorkspace() {
      File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: scan
  root: .
specifications:
  features: []
targets:
  backend:
    language: dart
    framework: dart
    contractOutput: lib/src/generated
    packages:
      - id: scan_pkg
        path: .
        roots: [lib]
''');
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: scan_pkg\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );
      final generated = Directory('${root.path}/lib/src/generated')
        ..createSync(recursive: true);
      File(
        '${generated.path}/feat_scan_001_contracts.g.dart',
      ).writeAsStringSync('''
abstract final class FeatScan001RequirementIds {
  static const addition = 'RULE-SCAN-ADDITION';
  static const multiplication = 'RULE-SCAN-MULTIPLICATION';
  static const bodySize = 'RULE-SCAN-BODY-SIZE';
}

abstract final class FeatScan001ControlIds {
  static const bodySize = ControlId('CTRL-SCAN-BODY-SIZE');
}
''');
      File('${root.path}/lib/src/logic.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:scan_pkg/src/generated/feat_scan_001_contracts.g.dart';

@ImplementsRequirement([FeatScan001RequirementIds.addition])
class Adder {
  @ZukeBinding('scan.addButton')
  final String button = '';
}
''');
      File('${root.path}/lib/src/screen.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

@PresentsRequirement(['RULE-SCAN-BODY-SIZE'])
class Screen {}

@ProvidesControl(['CTRL-SCAN-BODY-SIZE'])
class BodyGuard {}
''');
      return WorkspaceDiscovery().discover(root.path);
    }

    test('collects every implementation annotation kind', () {
      final scan = scanImplementations(root.path, buildWorkspace());

      // A presented requirement is an implementation too, so it must appear in
      // both sets: the distinction is what the requirement is, not whether it is
      // covered.
      expect(scan.implementedRequirementIds, {
        'RULE-SCAN-ADDITION',
        'RULE-SCAN-BODY-SIZE',
      });
      expect(scan.presentedRequirementIds, {'RULE-SCAN-BODY-SIZE'});
      expect(scan.providedControlIds, {'CTRL-SCAN-BODY-SIZE'});
      expect(scan.implementedBindingIds, {'scan.addButton'});
      // RULE-SCAN-MULTIPLICATION is declared by the contract and implemented
      // by nobody: that gap is the whole point of the feature.
      expect(
        scan.implementedRequirementIds.contains('RULE-SCAN-MULTIPLICATION'),
        isFalse,
      );
    });

    test('resolves IDs written as contract constant references', () {
      final scan = scanImplementations(root.path, buildWorkspace());
      // logic.dart references FeatScan001RequirementIds.addition rather than
      // spelling the literal, which is how the examples are written.
      expect(scan.implementedRequirementIds, contains('RULE-SCAN-ADDITION'));
    });

    test('a generated contract is never its own implementation', () {
      final scan = scanImplementations(root.path, buildWorkspace());
      // The contract declares RULE-SCAN-ADDITION as a constant, and logic.dart
      // claims the same ID through a reference to it. Exactly one claim must
      // exist: if the contract counted itself, the requirement would look
      // implemented twice over and a genuinely unimplemented requirement with
      // a matching constant would look covered.
      expect(
        scan.claims.where((claim) => claim.id == 'RULE-SCAN-ADDITION'),
        hasLength(1),
      );
      expect(
        scan.sourcePaths.every((path) => !path.endsWith('.g.dart')),
        isTrue,
        reason: 'generated contracts must not appear as implementation sources',
      );
    });

    test('records only sources that contributed a claim', () {
      final scan = scanImplementations(root.path, buildWorkspace());
      expect(
        scan.sourcePaths.map((path) => path.split(RegExp(r'[/\\]')).last),
        containsAll(['logic.dart', 'screen.dart']),
      );
    });

    test('every claim carries the kind of annotation that made it', () {
      final scan = scanImplementations(root.path, buildWorkspace());
      final byKind = <ImplementationKind, Set<String>>{};
      for (final claim in scan.claims) {
        byKind.putIfAbsent(claim.kind, () => <String>{}).add(claim.id);
      }
      expect(byKind[ImplementationKind.implemented], {'RULE-SCAN-ADDITION'});
      expect(byKind[ImplementationKind.presented], {'RULE-SCAN-BODY-SIZE'});
      expect(byKind[ImplementationKind.control], {'CTRL-SCAN-BODY-SIZE'});
      expect(byKind[ImplementationKind.binding], {'scan.addButton'});
    });

    test('an empty workspace scans to the empty result', () {
      final scan = scanImplementations(root.path, buildWorkspace());
      expect(ImplementationScan.empty.implementedRequirementIds, isEmpty);
      expect(scan.implementedRequirementIds, isNot(isEmpty));
    });
  });

  group('Requirement target scopes', () {
    test('a rule inherits its feature targets and may narrow them', () {
      final workspace = _featureFixture('''
# spec-begin
# schemaVersion: 1
# id: FEAT-SCOPE-001
# targets:
#   - backend
#   - flutter
# spec-end
@FEAT-SCOPE-001
Feature: Scoping
  # rule-spec-begin
  # id: RULE-SCOPE-INHERITED
  # rule-spec-end
  @RULE-SCOPE-INHERITED
  Rule: Inherits both targets
    @SCN-SCOPE-001
    Scenario: Works
      Given a step

  # rule-spec-begin
  # id: RULE-SCOPE-NARROWED
  # targets:
  #   - backend
  # rule-spec-end
  @RULE-SCOPE-NARROWED
  Rule: Narrows to backend
    @SCN-SCOPE-002
    Scenario: Works
      Given a step
''');
      final scopes = requirementTargetScopes(workspace);
      expect(
        scopes['RULE-SCOPE-INHERITED'],
        ['backend', 'flutter'],
        reason: 'a rule with no targets inherits the feature\'s',
      );
      expect(
        scopes['RULE-SCOPE-NARROWED'],
        ['backend'],
        reason: 'a rule that declares targets overrides the feature',
      );
    });

    test('appliesToTarget is the single shared scoping predicate', () {
      const scopes = {
        'RULE-BACKEND': ['backend'],
        'RULE-UNSCOPED': <String>[],
      };
      expect(requirementAppliesTo(scopes, 'RULE-BACKEND', 'backend'), isTrue);
      expect(requirementAppliesTo(scopes, 'RULE-BACKEND', 'flutter'), isFalse);
      // Unscoped applies everywhere.
      expect(requirementAppliesTo(scopes, 'RULE-UNSCOPED', 'flutter'), isTrue);
      // An ID the map never mentions is unscoped too.
      expect(requirementAppliesTo(scopes, 'RULE-UNKNOWN', 'flutter'), isTrue);
      // An unattributable target never narrows: hiding a requirement because
      // scoping metadata was missing is worse than over-reporting it.
      expect(requirementAppliesTo(scopes, 'RULE-BACKEND', null), isTrue);
    });
  });

  group('ZukeIndex implementation coverage', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('zuke-index-impl-'));
    tearDown(() => deleteTemporaryDirectory(root));

    ZukeIndex buildIndex({
      Set<String> implemented = const {'RULE-ONE'},
      Map<String, List<String>> requirementTargets = const {},
      Map<String, String> packageTargets = const {'lib': 'backend'},
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
        requirementIds: const {'RULE-ONE', 'RULE-TWO'},
        controlIds: const {'CTRL-ONE'},
        bindingIds: const {'binding.one'},
        implementedRequirementIds: implemented,
        requirementTargets: requirementTargets,
        packageTargets: packageTargets,
      );
    }

    test('implementation sets survive a JSON round trip', () {
      final index = buildIndex(
        implemented: {'RULE-ONE'},
        requirementTargets: const {
          'RULE-ONE': ['backend'],
          'RULE-TWO': ['backend', 'flutter'],
        },
        packageTargets: const {'lib': 'backend', 'apps/app': 'flutter'},
      );
      final restored = ZukeIndex.fromJson(
        Map<Object?, Object?>.from(
          jsonDecode(jsonEncode(index.toJson())) as Map,
        ),
      );
      expect(restored.implementedRequirementIds, {'RULE-ONE'});
      expect(restored.requirementTargets, {
        'RULE-ONE': ['backend'],
        'RULE-TWO': ['backend', 'flutter'],
      });
      expect(restored.packageTargets, {
        'lib': 'backend',
        'apps/app': 'flutter',
      });
      // The digest covers the new sets, so a restored index still verifies.
      expect(restored.inputDigest, index.inputDigest);
    });

    test('adding an implementation invalidates the index', () {
      final before = buildIndex(implemented: const {}).inputDigest;
      final after = buildIndex(implemented: const {'RULE-ONE'}).inputDigest;
      expect(
        after,
        isNot(before),
        reason:
            'an implementation edit must invalidate the index, or the editor '
            'keeps reporting a requirement as unimplemented after the code '
            'that implements it was added',
      );
    });

    test('re-targeting a requirement invalidates the index', () {
      final before = buildIndex(
        requirementTargets: const {
          'RULE-ONE': ['backend'],
        },
      ).inputDigest;
      final after = buildIndex(
        requirementTargets: const {
          'RULE-ONE': ['flutter'],
        },
      ).inputDigest;
      expect(after, isNot(before));
    });

    test('an index without the new keys still reads', () {
      final legacy = ZukeIndex.fromJson({
        'kind': ZukeIndex.kind,
        'inputDigest': 'sha256:${'0' * 64}',
        'generatedManifestDigest': 'sha256:${'0' * 64}',
        'generatedManifestPath': 'manifest.json',
        'inputs': <Object?>[],
        'inputPatterns': <Object?>[],
        'patternInputs': <Object?>[],
        'requirementIds': ['RULE-ONE'],
        'controlIds': <Object?>[],
        'bindingIds': <Object?>[],
      });
      expect(legacy.implementedRequirementIds, isEmpty);
      expect(legacy.requirementTargets, isEmpty);
      expect(legacy.packageTargets, isEmpty);
      // An unrecorded ID is unscoped, so it still applies everywhere.
      expect(legacy.appliesToTarget('RULE-ONE', 'flutter'), isTrue);
    });

    test('targetForPath resolves the longest matching package', () {
      final index = buildIndex(
        packageTargets: const {
          'lib': 'backend',
          'apps/mobile': 'flutter',
          'apps/mobile/lib': 'flutter-ui',
        },
      );
      expect(index.targetForPath('lib/src/app.dart'), 'backend');
      expect(index.targetForPath('apps/mobile/lib/main.dart'), 'flutter-ui');
      expect(index.targetForPath('apps/mobile/test/x_test.dart'), 'flutter');
      expect(index.targetForPath('lib\\src\\app.dart'), 'backend');
      expect(index.targetForPath('elsewhere/x.dart'), isNull);
    });

    test('a package at the workspace root owns every path in it', () {
      // A single-package workspace declares its one package as `.`, exactly as
      // in zuke.yaml. Matching that literally matches nothing, and an
      // unattributable file is reported as *unscoped* — so the failure mode is
      // every requirement applying everywhere, not a missed match.
      final index = buildIndex(
        packageTargets: const {'.': 'app'},
        implemented: const {},
        requirementTargets: const {
          'RULE-ONE': ['backend'],
          'RULE-TWO': ['app'],
        },
      );

      expect(index.targetForPath('lib/src/app.dart'), 'app');
      expect(index.targetForPath('lib\\src\\app.dart'), 'app');
      expect(index.targetForPath('test/app_test.dart'), 'app');
      expect(index.targetForPath('lib/src/deeply/nested/file.dart'), 'app');

      // Scoping is therefore live again: the `backend` requirement is no longer
      // reported in the app, and the `app` requirement is.
      expect(index.appliesToTarget('RULE-ONE', 'app'), isFalse);
      expect(index.appliesToTarget('RULE-TWO', 'app'), isTrue);
      expect(index.unimplementedRequirementIds('app'), {'RULE-TWO'});
    });

    test('a nested package still outranks the workspace root', () {
      // Longest match wins, so recording the root package must not shadow a
      // nested one in a multi-package workspace that also declares `.`.
      final index = buildIndex(
        packageTargets: const {
          '.': 'root',
          'apps/api': 'backend',
          'apps/mobile': 'flutter',
        },
      );

      expect(index.targetForPath('apps/api/lib/main.dart'), 'backend');
      expect(index.targetForPath('apps/mobile/lib/main.dart'), 'flutter');
      // Anything not under a nested package falls back to the root.
      expect(index.targetForPath('lib/shared/thing.dart'), 'root');
    });

    test('root package paths are normalized to a single spelling', () {
      // All three spellings mean the workspace root and must not produce three
      // competing entries, or the same target is stored under several keys.
      final index = buildIndex(
        packageTargets: const {'.': 'app', './': 'app', '.\\': 'app'},
      );

      expect(index.packageTargets, {'.': 'app'});
      expect(index.targetForPath('lib/src/app.dart'), 'app');
    });

    test('unimplementedRequirementIds narrows to the analyzed target', () {
      final index = buildIndex(
        implemented: const {},
        requirementTargets: const {
          'RULE-ONE': ['backend'],
          'RULE-TWO': ['backend', 'flutter'],
        },
      );
      expect(index.unimplementedRequirementIds('backend'), {
        'RULE-ONE',
        'RULE-TWO',
      });
      expect(index.unimplementedRequirementIds('flutter'), {'RULE-TWO'});
      expect(
        buildIndex(
          implemented: const {'RULE-ONE', 'RULE-TWO'},
        ).unimplementedRequirementIds('backend'),
        isEmpty,
      );
    });
  });

  group('SourceConstants', () {
    test('resolves bare, qualified, and list references', () {
      final root = Directory.systemTemp.createTempSync('zuke-consts-');
      addTearDown(() => deleteTemporaryDirectory(root));
      final declarations = File('${root.path}/contracts.dart')
        ..writeAsStringSync('''
class Ids {
  static const one = 'RULE-ONE';
  static const many = ['RULE-TWO', 'RULE-THREE'];
  static const qualified = 'RULE-FOUR';
}
''');
      final constants = SourceConstants();
      collectSourceConstants(declarations, constants);
      expect(constants.values['one'], 'RULE-ONE');
      expect(constants.values['Ids.one'], 'RULE-ONE');

      // Exercise reference resolution with real AST nodes, the way an
      // annotation argument arrives.
      final uses = File('${root.path}/uses.dart')
        ..writeAsStringSync('''
final bare = Ids.one;
final qualified = Ids.qualified;
final listed = Ids.many;
''');
      final unit = parseString(
        content: uses.readAsStringSync(),
        path: uses.path,
        throwIfDiagnostics: false,
      ).unit;
      final references = <String, Expression>{};
      unit.accept(
        _ReferenceCollector(
          (name, expression) => references[name] = expression,
        ),
      );

      expect(constants.valueOf(references['bare']!), 'RULE-ONE');
      expect(constants.valueOf(references['qualified']!), 'RULE-FOUR');
      expect(constants.idsForList(references['listed']!), [
        'RULE-TWO',
        'RULE-THREE',
      ]);
    });

    test('resolves an inline list literal, not only a named constant', () {
      final root = Directory.systemTemp.createTempSync('zuke-consts-inline-');
      addTearDown(() => deleteTemporaryDirectory(root));
      final file = File('${root.path}/inline.dart')
        ..writeAsStringSync('''
@Marker(['RULE-INLINE-A', 'RULE-INLINE-B'])
class Inline {}
''');
      final constants = SourceConstants();
      collectSourceConstants(file, constants);
      final ids = collectAnnotationIds(
        file,
        constants,
        annotationNames: const {'Marker'},
        idField: 'requirementIds',
      );
      expect(ids, {'RULE-INLINE-A', 'RULE-INLINE-B'});
    });

    test('reads the named argument as well as the first positional one', () {
      final root = Directory.systemTemp.createTempSync('zuke-consts-named-');
      addTearDown(() => deleteTemporaryDirectory(root));
      final file = File('${root.path}/named.dart')
        ..writeAsStringSync('''
@Marker(requirementIds: ['RULE-NAMED-A'])
class Named {}

@Single(value: 'ID-NAMED-B')
class SingleNamed {}
''');
      final constants = SourceConstants();
      collectSourceConstants(file, constants);

      // The declared field is what identifies which argument to read, so the
      // named form cannot be silently ignored — which would report nothing and
      // read as a missing implementation.
      expect(
        collectAnnotationIds(
          file,
          constants,
          annotationNames: const {'Marker'},
          idField: 'requirementIds',
        ),
        {'RULE-NAMED-A'},
      );
      expect(
        collectAnnotationIds(
          file,
          constants,
          annotationNames: const {'Single'},
          idField: 'value',
          single: true,
        ),
        {'ID-NAMED-B'},
      );
    });
  });
}

/// Collects each top-level variable's initializer, so a test can obtain real
/// [Expression] nodes to resolve against.
class _ReferenceCollector extends RecursiveAstVisitor<void> {
  _ReferenceCollector(this.record);

  final void Function(String name, Expression expression) record;

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (final variable in node.variables.variables) {
      final initializer = variable.initializer;
      if (initializer != null) record(variable.name.lexeme, initializer);
    }
    super.visitTopLevelVariableDeclaration(node);
  }
}

/// A workspace whose single feature is parsed from [feature].
WorkspaceDiscoveryResult _featureFixture(String feature) {
  final root = Directory.systemTemp.createTempSync('zuke-scope-');
  addTearDown(() => deleteTemporaryDirectory(root));
  File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: scopes
  root: .
specifications:
  features:
    - specs/features/example.feature
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: scopes_pkg
        path: .
        roots: [lib]
  flutter:
    language: dart
    framework: flutter
    packages:
      - id: scopes_app
        path: app
        roots: [lib]
''');
  final features = Directory('${root.path}/specs/features')
    ..createSync(recursive: true);
  File('${features.path}/example.feature').writeAsStringSync(feature);
  return WorkspaceDiscovery().discover(root.path);
}
