import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/verified_requirement_scan.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

import 'support/resolved_workspace.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zuke-verified-scan-');
    Directory('${root.path}/lib').createSync(recursive: true);
  });

  tearDown(() {
    if (root.existsSync()) {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  WorkspaceDiscoveryResult workspace() => WorkspaceDiscoveryResult(
    config: ZukeConfig(
      workspaceTargets: {
        'app': WorkspaceTarget(
          id: 'app',
          language: 'dart',
          framework: 'dart',
          packages: [
            WorkspacePackage(id: 'app', path: '.', roots: const ['lib']),
          ],
        ),
      },
    ),
    data: const MetadataExtractorResult(),
  );

  test('resolves an inline list literal', () async {
    File('${root.path}/lib/proof.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
class Proof {
  void covers() {}
}
@VerifiesRequirement(['RULE-INLINE'])
void main() {}
''');
    await configureFixturePackages(root);
    final scan = await scanVerifiedRequirements(root.path, workspace());
    expect(scan.requirementIds, {'RULE-INLINE'});
  });

  test('resolves a static const List<String> alias', () async {
    File('${root.path}/lib/ids.dart').writeAsStringSync('''
class RuleIds {
  static const List<String> all = ['RULE-ALIAS-A', 'RULE-ALIAS-B'];
}
''');
    File('${root.path}/lib/proof.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'ids.dart';

@VerifiesRequirement(RuleIds.all)
void main() {}
''');
    await configureFixturePackages(root);
    final scan = await scanVerifiedRequirements(root.path, workspace());
    expect(scan.requirementIds, {'RULE-ALIAS-A', 'RULE-ALIAS-B'});
  });

  test('resolves a top-level const List alias', () async {
    File('${root.path}/lib/ids.dart').writeAsStringSync('''
const firstRule = 'RULE-TOP-A';
const secondRule = 'RULE-TOP-B';
const verifiedRules = [firstRule, secondRule];
''');
    File('${root.path}/lib/proof.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'ids.dart';

@VerifiesRequirement(verifiedRules)
void main() {}
''');
    await configureFixturePackages(root);
    final scan = await scanVerifiedRequirements(root.path, workspace());
    expect(scan.requirementIds, {'RULE-TOP-A', 'RULE-TOP-B'});
  });

  test(
    'resolves const list members declared in another scanned file',
    () async {
      File('${root.path}/lib/a_ids.dart').writeAsStringSync('''
import 'z_members.dart';

const verifiedRules = [firstRule, secondRule];
''');
      File('${root.path}/lib/z_members.dart').writeAsStringSync('''
const firstRule = 'RULE-CROSS-FILE-A';
const secondRule = 'RULE-CROSS-FILE-B';
''');
      File('${root.path}/lib/proof.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'a_ids.dart';

@VerifiesRequirement(verifiedRules)
void main() {}
''');
      await configureFixturePackages(root);
      final scan = await scanVerifiedRequirements(root.path, workspace());
      expect(scan.requirementIds, {'RULE-CROSS-FILE-A', 'RULE-CROSS-FILE-B'});
    },
  );

  test('resolves a static const List alias of const string members', () async {
    File('${root.path}/lib/ids.dart').writeAsStringSync('''
class RuleIds {
  static const first = 'RULE-MEMBER-A';
  static const second = 'RULE-MEMBER-B';
  static const all = [first, second];
}
''');
    File('${root.path}/lib/proof.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'ids.dart';

@VerifiesRequirement(RuleIds.all)
void main() {}
''');
    await configureFixturePackages(root);
    final scan = await scanVerifiedRequirements(root.path, workspace());
    expect(scan.requirementIds, {'RULE-MEMBER-A', 'RULE-MEMBER-B'});
  });
}
