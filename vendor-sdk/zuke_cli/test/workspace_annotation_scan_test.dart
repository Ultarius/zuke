import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/implementation_scan.dart';
import 'package:zuke_cli/src/verified_requirement_scan.dart';
import 'package:zuke_cli/src/workspace_annotation_scan.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'support/resolved_workspace.dart';
import 'support/temporary_directory.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('zuke-resolved-scan-');
    await configureFixturePackages(root);
  });
  tearDown(() => deleteTemporaryDirectory(root));

  File source(String path, String content) {
    final file = File.fromUri(root.uri.resolve(path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  WorkspaceDiscoveryResult workspace({
    List<String> roots = const ['lib', 'lib/src'],
  }) => WorkspaceDiscoveryResult(
    config: ZukeConfig(
      workspaceTargets: {
        'backend': WorkspaceTarget(
          id: 'backend',
          language: 'dart',
          framework: 'dart',
          packages: [WorkspacePackage(id: 'fixture', path: '.', roots: roots)],
        ),
      },
    ),
    data: const MetadataExtractorResult(),
  );

  test(
    'resolves colliding names through imports, re-exports and parts',
    () async {
      source(
        'lib/a.dart',
        "const rule = 'RULE-A'; class Ids { static const all = [rule]; }",
      );
      source(
        'lib/b.dart',
        "const rule = 'RULE-B'; class Ids { static const all = [rule]; }",
      );
      source(
        'lib/unimported.dart',
        "const rule = 'RULE-WRONG'; class Ids { static const all = [rule]; }",
      );
      source(
        'lib/barrel.dart',
        "export 'package:zuke_annotations/zuke_annotations.dart'; export 'a.dart' show Ids;",
      );
      source('lib/src/service.dart', '''
import '../barrel.dart';
import '../b.dart' as b;
part 'proof.dart';
const allRules = [...Ids.all, ...b.Ids.all];
@ImplementsRequirement(allRules)
class Service {}
''');
      source('lib/src/proof.dart', '''
part of 'service.dart';
@VerifiesRequirement(allRules)
void proof() {}
''');
      final scan = await scanWorkspaceAnnotations(root.path, workspace());
      final implementation = ImplementationScan.fromScan(scan);
      final verification = VerifiedRequirementScan.fromScan(scan);
      expect(implementation.implementedRequirementIds, {'RULE-A', 'RULE-B'});
      expect(verification.requirementIds, {'RULE-A', 'RULE-B'});
      expect(
        scan.claims,
        hasLength(4),
        reason: 'overlapping roots must not duplicate claims',
      );
      expect(scan.claims.every((claim) => claim.target == 'backend'), isTrue);
      expect(verification.sourcePaths.single, endsWith('proof.dart'));
    },
  );

  test(
    'local annotation shadowing cannot claim implementation coverage',
    () async {
      source('lib/source.dart', '''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_annotations/zuke_annotations.dart' as z;
class ImplementsRequirement {
  final List<String> requirementIds;
  const ImplementsRequirement(this.requirementIds);
}
@ImplementsRequirement(['RULE-FAKE'])
class Fake {}
@z.ImplementsRequirement(['RULE-REAL'])
class Real {}
@z.VerifiesRequirement(['RULE-INVALID-PLACEMENT'])
class InvalidProof {}
''');
      final scan = await scanWorkspaceAnnotations(root.path, workspace());
      expect(scan.claims.map((claim) => claim.id), ['RULE-REAL']);
    },
  );

  test(
    'pending and removed generated files affect resolution before writes',
    () async {
      final contract = source(
        'lib/generated/ids.g.dart',
        "const rule = 'RULE-OLD';",
      );
      final removed = source(
        'lib/generated/removed.g.dart',
        "const removedRule = 'RULE-REMOVED';",
      );
      source('lib/service.dart', '''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'generated/ids.g.dart';
import 'generated/removed.g.dart';
@ImplementsRequirement([rule])
class Current {}
@ImplementsRequirement([removedRule])
class Stale {}
''');
      final scan = await scanWorkspaceAnnotations(
        root.path,
        workspace(),
        pendingContent: {contract.path: "const rule = 'RULE-NEW';"},
        generatedPaths: {contract.path, removed.path},
      );
      expect(scan.claims.map((claim) => claim.id), ['RULE-NEW']);
      expect(scan.inputPaths, isNot(contains(contract.path)));
      expect(scan.inputPaths, isNot(contains(removed.path)));
      expect(contract.readAsStringSync(), contains('RULE-OLD'));
    },
  );

  test('tracks imported constants outside configured source roots', () async {
    final ids = source('lib/shared/ids.dart', "const rule = 'RULE-SHARED';");
    source('lib/src/service.dart', '''
import 'package:zuke_annotations/zuke_annotations.dart';
import '../shared/ids.dart';
@ImplementsRequirement([rule])
class Service {}
''');
    final scan = await scanWorkspaceAnnotations(
      root.path,
      workspace(roots: ['lib/src']),
    );
    expect(scan.claims.single.id, 'RULE-SHARED');
    expect(scan.inputPaths, contains(ids.path));
    expect(scan.sourcePaths, isNot(contains(ids.path)));
  });
}
