import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/implementation_scan.dart';
import 'package:zuke_cli/src/proof_engine/binding_coverage_engine.dart';
import 'package:zuke_cli/src/requirement_scopes.dart';
import 'package:zuke_cli/tooling.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'support/temporary_directory.dart';
import 'support/resolved_workspace.dart';

void main() {
  test('one-character packages outrank the workspace root in either order', () {
    for (final packages in [
      {'.': 'root', 'a': 'nested'},
      {'a': 'nested', '.': 'root'},
    ]) {
      expect(targetForWorkspacePath(packages, 'a/test/main.dart'), 'nested');
      expect(packageIdForWorkspacePath(packages, 'a/test/main.dart'), 'nested');
      expect(targetForWorkspacePath(packages, 'ab/main.dart'), 'root');
    }
  });
  group('Target-aware implementation claims', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('zuke-claim-tgt-'));
    tearDown(() => deleteTemporaryDirectory(root));

    /// A workspace with a `backend` package at the root and a `flutter` package
    /// under `app/`, where the only implementation of a backend-scoped rule
    /// lives in the Flutter package.
    ///
    /// This is the case that made the editor and `zuke validate` disagree: a
    /// flat set of implemented IDs cannot tell a Flutter claim from a backend
    /// one, so the Flutter claim hid the missing backend implementation from the
    /// editor while the CLI still reported it.
    WorkspaceDiscoveryResult buildWorkspace() {
      File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: claims
  root: .
specifications:
  features:
    - specs/features/claims.feature
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: claims_api
        path: .
        roots: [lib]
  flutter:
    language: dart
    framework: flutter
    packages:
      - id: claims_app
        path: app
        roots: [lib]
''');
      final features = Directory('${root.path}/specs/features')
        ..createSync(recursive: true);
      File('${features.path}/claims.feature').writeAsStringSync('''
# spec-begin
# schemaVersion: 1
# id: FEAT-CLAIMS-001
# targets:
#   - backend
#   - flutter
# spec-end
@FEAT-CLAIMS-001
Feature: Claims
  # rule-spec-begin
  # id: RULE-BACKEND-ONLY
  # targets:
  #   - backend
  # rule-spec-end
  @RULE-BACKEND-ONLY
  Rule: Backend only
    @SCN-CLAIMS-001
    Scenario: Works
      Given a step
  # rule-spec-begin
  # id: RULE-SHARED
  # targets:
  #   - backend
  #   - flutter
  # rule-spec-end
  @RULE-SHARED
  Rule: Shared
    @SCN-CLAIMS-002
    Scenario: Works
      Given a step
''');
      final appLib = Directory('${root.path}/app/lib')
        ..createSync(recursive: true);
      File('${appLib.path}/screen.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

class Screen {
  @ImplementsRequirement(['RULE-BACKEND-ONLY'])
  void build() {}
}
''');
      final backendLib = Directory('${root.path}/lib')
        ..createSync(recursive: true);
      File('${backendLib.path}/service.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

class Service {
  @ImplementsRequirement(['RULE-SHARED'])
  void run() {}
}
''');
      return WorkspaceDiscovery().discover(root.path);
    }

    test('each claim records the target that owns its file', () async {
      final workspace = buildWorkspace();
      await configureFixturePackages(root);
      final scan = await scanImplementations(root.path, workspace);

      final backendOnly = scan.claims.firstWhere(
        (claim) => claim.id == 'RULE-BACKEND-ONLY',
      );
      // Declared in the Flutter package, so the claim belongs to `flutter`.
      expect(backendOnly.target, 'flutter');
      expect(backendOnly.sourcePath, 'app/lib/screen.dart');
      expect(backendOnly.kind, ImplementationKind.implemented);

      final shared = scan.claims.firstWhere(
        (claim) => claim.id == 'RULE-SHARED',
      );
      expect(shared.target, 'backend');
      expect(shared.sourcePath, 'lib/service.dart');
    });

    test('a claim from another target does not satisfy this one', () async {
      final workspace = buildWorkspace();
      await configureFixturePackages(root);
      final scan = await scanImplementations(root.path, workspace);
      final claims = scan.claims
          .map((claim) => claim.toIndexClaim())
          .toList(growable: false);
      final index = ZukeIndex(
        inputDigest: 'input',
        generatedManifestDigest: 'manifest',
        generatedManifestPath: 'manifest.json',
        inputs: const [],
        requirementIds: const {'RULE-BACKEND-ONLY', 'RULE-SHARED'},
        controlIds: const {},
        bindingIds: const {},
        requirementTargets: const {
          'RULE-BACKEND-ONLY': ['backend'],
          'RULE-SHARED': ['backend', 'flutter'],
        },
        packageTargets: workspacePackageTargets(workspace),
        implementationClaims: claims,
      );

      // The Flutter claim does not implement the backend-only requirement, so
      // the backend package is still told about it.
      expect(index.unimplementedRequirementIds('backend'), {
        'RULE-BACKEND-ONLY',
      });
      // `RULE-SHARED` is declared for both targets and only the backend package
      // claims it, so the Flutter package is told about it too. A claim satisfies
      // only its own target — the rule `zuke validate` already applied, and the
      // reason the two now share one function.
      expect(index.unimplementedRequirementIds('flutter'), {'RULE-SHARED'});
    });

    test('an unattributable file makes an unpinned claim that satisfies all', () {
      // Leniency in the same direction as requirementAppliesTo: a file Zuke
      // cannot attribute is not held to a target, so its claim counts for all of
      // them rather than none.
      const claims = [
        ZukeImplementationClaim(id: 'RULE-ANY'),
        ZukeImplementationClaim(id: 'RULE-PINNED', target: 'backend'),
      ];
      const index = ZukeIndex(
        inputDigest: 'input',
        generatedManifestDigest: 'manifest',
        generatedManifestPath: 'manifest.json',
        inputs: [],
        requirementIds: {'RULE-ANY', 'RULE-PINNED'},
        controlIds: {},
        bindingIds: {},
        implementationClaims: claims,
      );

      // backend: RULE-ANY by the unpinned claim, RULE-PINNED by its own claim.
      expect(index.unimplementedRequirementIds('backend'), isEmpty);
      // flutter: RULE-ANY by the unpinned claim, but RULE-PINNED was claimed for
      // backend only — which is the whole point of keeping the target.
      expect(index.unimplementedRequirementIds('flutter'), {'RULE-PINNED'});
      // catalog: neither claim applies except the unpinned one.
      expect(index.unimplementedRequirementIds('catalog'), {'RULE-PINNED'});
    });
  });

  group('Annotation source selection', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('zuke-annot-src-'));
    tearDown(() => deleteTemporaryDirectory(root));

    /// A workspace with three sources: a plain annotated file, one using a
    /// prefixed import, and a documentation snippet under `test/guide_snippets/`.
    WorkspaceDiscoveryResult buildWorkspace() {
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: annot_src\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );
      File('${root.path}/zuke.yaml').writeAsStringSync('''
schemaVersion: 3
workspace:
  name: annot-src
  root: .
specifications:
  features: []
targets:
  backend:
    language: dart
    framework: dart
    packages:
      - id: annot_src
        path: .
        roots: [lib, test]
''');
      final lib = Directory('${root.path}/lib/src')
        ..createSync(recursive: true);
      File('${lib.path}/plain.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

class Plain {
  @ImplementsRequirement(['RULE-PLAIN'])
  void go() {}
}
''');
      // The same annotation, reached through an import prefix. Matching the
      // source spelling alone drops it, which reads as a requirement nothing
      // implements — the exact inverse of what the rule reports.
      File('${lib.path}/prefixed.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart' as z;

class Prefixed {
  @z.ImplementsRequirement(['RULE-PREFIXED'])
  void go() {}
}
''');
      final snippet = Directory('${root.path}/test/guide_snippets')
        ..createSync(recursive: true);
      File('${snippet.path}/doc.dart').writeAsStringSync('''
// Documentation snippet, deliberately not real code.
class Snippet {
  @ImplementsRequirement(['RULE-SNIPPET'])
  void go() {}
}
''');
      return WorkspaceDiscovery().discover(root.path);
    }

    test('a prefixed annotation still contributes coverage', () async {
      final workspace = buildWorkspace();
      await configureFixturePackages(root);
      final scan = await scanImplementations(root.path, workspace);

      expect(
        scan.implementedRequirementIds,
        containsAll(['RULE-PLAIN', 'RULE-PREFIXED']),
      );
    });

    test('a documentation snippet does not count as an implementation', () async {
      // Extraction excludes these, so counting them here would let prose in the
      // guide satisfy coverage for a requirement nothing implements.
      final workspace = buildWorkspace();
      await configureFixturePackages(root);
      final scan = await scanImplementations(root.path, workspace);

      expect(scan.implementedRequirementIds, isNot(contains('RULE-SNIPPET')));
      expect(
        scan.claims.map((claim) => claim.id),
        isNot(contains('RULE-SNIPPET')),
      );
    });
  });

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

    test('collects every implementation annotation kind', () async {
      final workspace = buildWorkspace();
      await configureFixturePackages(root);
      final scan = await scanImplementations(root.path, workspace);

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

    test('resolves IDs written as contract constant references', () async {
      final workspace = buildWorkspace();
      await configureFixturePackages(root);
      final scan = await scanImplementations(root.path, workspace);
      // logic.dart references FeatScan001RequirementIds.addition rather than
      // spelling the literal, which is how the examples are written.
      expect(scan.implementedRequirementIds, contains('RULE-SCAN-ADDITION'));
    });

    test('a generated contract is never its own implementation', () async {
      final workspace = buildWorkspace();
      await configureFixturePackages(root);
      final scan = await scanImplementations(root.path, workspace);
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

    test('records only sources that contributed a claim', () async {
      final workspace = buildWorkspace();
      await configureFixturePackages(root);
      final scan = await scanImplementations(root.path, workspace);
      expect(
        scan.sourcePaths.map((path) => path.split(RegExp(r'[/\\]')).last),
        containsAll(['logic.dart', 'screen.dart']),
      );
    });

    test('every claim carries the kind of annotation that made it', () async {
      final workspace = buildWorkspace();
      await configureFixturePackages(root);
      final scan = await scanImplementations(root.path, workspace);
      final byKind = <ImplementationKind, Set<String>>{};
      for (final claim in scan.claims) {
        byKind.putIfAbsent(claim.kind, () => <String>{}).add(claim.id);
      }
      expect(byKind[ImplementationKind.implemented], {'RULE-SCAN-ADDITION'});
      expect(byKind[ImplementationKind.presented], {'RULE-SCAN-BODY-SIZE'});
      expect(byKind[ImplementationKind.control], {'CTRL-SCAN-BODY-SIZE'});
      expect(byKind[ImplementationKind.binding], {'scan.addButton'});
    });

    test('an empty workspace scans to the empty result', () async {
      final workspace = buildWorkspace();
      await configureFixturePackages(root);
      final scan = await scanImplementations(root.path, workspace);
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
      String? claimTarget = 'lib',
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
        // The claims are what the coverage decision reads; the flat set above is
        // a summary. Passing null creates unpinned claims.
        implementationClaims: [
          for (final id in implemented)
            ZukeImplementationClaim(
              id: id,
              target: claimTarget == null ? null : packageTargets[claimTarget],
            ),
        ],
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

    test('two spellings of one file are recorded once', () {
      // Regression. `zuke.yaml` was already contributed by the discovery input
      // set and was also named explicitly, and because the caller's set
      // deduplicates *raw* paths while the index records normalized ones, the
      // duplicate survived into every committed example index. It looked harmless
      // — same file, same digest — but `inputDigest` hashes the list as given, so
      // the committed index described an input set the generator could not
      // reliably reproduce, and CI reported it stale against unchanged sources.
      final config = File('${root.path}/zuke.yaml')
        ..writeAsStringSync('schemaVersion: 3\n');
      final manifest = File('${root.path}/generated-manifest.json')
        ..writeAsStringSync('{"files":[]}');

      ZukeIndex create(List<String> inputPaths) => ZukeIndex.create(
        root: root.path,
        inputPaths: inputPaths,
        generatedManifestContent: manifest.readAsStringSync(),
        generatedManifestPath: 'generated-manifest.json',
        requirementIds: const [],
        controlIds: const [],
        bindingIds: const [],
      );

      final byAbsolute = create([config.path]);
      final byBothRoutes = create([
        config.path,
        // A different spelling of the same file, which is what a caller reaching
        // it by two routes produces.
        '${root.path}${Platform.pathSeparator}zuke.yaml',
        'zuke.yaml',
      ]);

      expect(byAbsolute.inputs.map((input) => input.path).toList(), [
        'zuke.yaml',
      ]);
      expect(
        byBothRoutes.inputs.map((input) => input.path).toList(),
        ['zuke.yaml'],
        reason:
            'one file must occupy one slot in `inputs` however many routes '
            'reached it; a duplicate changes inputDigest and makes a committed '
            'index report itself stale',
      );
      // Same recorded input set, so the same digest. This is the property that
      // actually broke: not a cosmetic duplicate, an unreproducible fingerprint.
      expect(
        byBothRoutes.inputDigest,
        byAbsolute.inputDigest,
        reason:
            'spelling the same file twice must not change what the index claims '
            'to have read, or `--check` fails on an unchanged workspace',
      );
      expect(
        byBothRoutes.freshnessIssues(root: root.path),
        isEmpty,
        reason: 'the deduplicated index must still verify against its inputs',
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

    test('an index without the binding-coverage facts is refused', () {
      // Deliberately strict. The ID sets above stayed lenient because an
      // unrecorded ID is genuinely ambiguous — "declared nothing" and "recorded
      // nothing" mean the same thing downstream. The binding-coverage facts are
      // the opposite: an absent registration list cannot stand in for an empty
      // one, because "this workspace registered nothing" is a claim about
      // absence, and reading a pre-contract index as if it had made that claim
      // would report every slot as a gap.
      expect(
        () => ZukeIndex.fromJson({
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
        }),
        throwsFormatException,
      );
    });

    test('an empty registration list is not the same as an unreadable one', () {
      // The distinction the strict read exists to keep: an explicit empty list is
      // a complete answer, while an entry missing its unknown-marking keys is
      // rejected rather than defaulted.
      final complete = buildIndex();
      expect(complete.managedRegistrations, isEmpty);
      expect(
        complete.unresolvedManagedRegistrations,
        0,
        reason: 'a scan that resolved everything records no unknowns',
      );

      final json = complete.toJson();
      json['managedRegistrations'] = [
        {
          'scenarioId': 'SCN-ONE',
          'sourcePath': 'test/one_test.dart',
          // target, packageId and evidenceTypes all absent.
        },
      ];
      expect(
        () => ZukeIndex.fromJson(json),
        throwsFormatException,
        reason:
            'a registration without its unknown-marking keys must be refused, '
            'not read as publishing nothing',
      );
    });

    test('a registration keeps its unknowns across a round trip', () {
      final written = ZukeIndex(
        inputDigest: 'sha256:${'0' * 64}',
        generatedManifestDigest: 'sha256:${'0' * 64}',
        generatedManifestPath: 'manifest.json',
        inputs: const [],
        requirementIds: const {},
        controlIds: const {},
        bindingIds: const {},
        managedRegistrations: const [
          ManagedRegistrationFact(
            scenarioId: 'SCN-ONE',
            sourcePath: 'test/one_test.dart',
          ),
          ManagedRegistrationFact(
            scenarioId: 'SCN-TWO',
            sourcePath: 'test/two_test.dart',
            target: 'app',
            packageId: 'app',
            evidenceTypes: ['unit'],
          ),
        ],
        unresolvedManagedRegistrations: 1,
      ).toJson();

      // The keys are present with null values, not omitted: that is the encoding
      // for "unknown", and the reader requires them.
      expect(
        (written['managedRegistrations'] as List).first,
        containsPair('evidenceTypes', isNull),
      );
      final reread = ZukeIndex.fromJson(written);
      expect(reread.managedRegistrations.first.evidenceTypes, isNull);
      expect(reread.managedRegistrations.first.target, isNull);
      expect(reread.managedRegistrations.last.evidenceTypes, ['unit']);
      expect(
        reread.unresolvedManagedRegistrations,
        1,
        reason:
            'the unresolved count is what makes a slot undecidable; dropping it '
            'would let the editor report a gap the CLI refuses to decide',
      );
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
