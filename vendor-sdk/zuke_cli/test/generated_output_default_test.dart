import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/configuration_preflight.dart';
import 'package:zuke_cli/src/extraction_service.dart';

import 'cli_test_helper.dart';
import 'helpers/eligible_workspace.dart';
import 'support/temporary_directory.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('zuke-output-default-');
    await createEligibleWorkspace(root);
  });
  tearDown(() => deleteTemporaryDirectory(root));

  Future<void> generate() async {
    final result = await runInProcessCli([
      'generate',
      '--root',
      root.path,
      '--quiet',
    ]);
    expect(result.exitCode, 0, reason: result.stderr);
  }

  Future<String> provenance() async {
    final extraction = await ExtractionService().extract(
      requireCurrentWorkspace(root.path),
      includeEvidence: false,
    );
    expect(extraction.errors, isEmpty);
    return extraction.outputs.single.requirePublishedSourceDigest();
  }

  test('an omitted contractOutput keeps provenance across a rename', () async {
    expect(
      File('${root.path}/zuke.yaml').readAsStringSync(),
      isNot(contains('contractOutput')),
      reason: 'this test is about the default output',
    );
    await generate();
    final before = await provenance();

    final feature = File('${root.path}/specs/features/gateway.feature');
    feature.writeAsStringSync(
      feature.readAsStringSync().replaceFirst(
        'Scenario: trivial',
        'Scenario: renamed without changing its steps',
      ),
    );
    await generate();

    expect(await provenance(), before);
  });
}
