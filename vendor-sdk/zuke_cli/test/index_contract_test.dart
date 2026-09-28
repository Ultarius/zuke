import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:zuke_cli/editor.dart';

import 'cli_test_helper.dart';
import 'support/index_schema.dart';
import '../../../tool/check_editor_contract.dart' as guard;

void main() {
  test('index serialization keys match the versioned contract golden', () {
    // Anchored to the workspace root, not the current directory. CI runs this
    // file with `working-directory: vendor-sdk/zuke_cli`, so relative paths
    // only happen to work there; `dart test vendor-sdk/zuke_cli/test` from the
    // repository root would resolve the plugin pubspec outside the repo.
    final workspace = zukeWorkspaceRoot();
    final cli = Directory(p.join(workspace.path, 'vendor-sdk', 'zuke_cli'));
    final plugin =
        loadYaml(
              File(
                p.join(
                  workspace.path,
                  'vendor-sdk',
                  'zuke_analyzer',
                  'pubspec.yaml',
                ),
              ).readAsStringSync(),
            )
            as Map;
    final actual = {
      'contractVersion': zukeIndexContract,
      'pluginVersion': plugin['version'],
      'serializers': indexSerializerKeys(cli),
    };
    final expected = jsonDecode(
      File(
        p.join(cli.path, 'test', 'goldens', 'index_contract.json'),
      ).readAsStringSync(),
    );
    expect(
      actual,
      expected,
      reason:
          'Update the golden, bump zukeIndexContract and the plugin version together.',
    );
  });

  test('header detects incompatible versions before reading the payload', () {
    expect(
      ZukeIndexHeader({
        'contractVersion': zukeIndexContract + 1,
      }).isIncompatible,
      isTrue,
    );
    expect(ZukeIndexHeader({}).isIncompatible, isFalse);
    expect(
      () => ZukeIndexHeader({'contractVersion': '1'}),
      throwsFormatException,
    );
    expect(
      () => ZukeIndexHeader({'contractVersion': null}),
      throwsFormatException,
    );
  });

  test('claim deduplication cannot confuse delimiters with identity', () {
    final claims = normalizedImplementationClaims(const [
      ZukeImplementationClaim(id: 'c', target: 'a|b'),
      ZukeImplementationClaim(id: 'b|c', target: 'a'),
      ZukeImplementationClaim(id: 'c', target: 'a|b'),
    ]);
    expect(claims, hasLength(2));
  });

  test(
    'different spec findings cannot collide across message and feature ID',
    () {
      const first = ZukeSpecDiagnostic(
        file: 'specs/features/a.feature',
        line: 3,
        column: 1,
        code: 'ZUKE-REF-001',
        severity: 'error',
        message: 'a|b',
        featureId: 'c',
      );
      const second = ZukeSpecDiagnostic(
        file: 'specs/features/a.feature',
        line: 3,
        column: 1,
        code: 'ZUKE-REF-001',
        severity: 'error',
        message: 'a',
        featureId: 'b|c',
      );
      final root = Directory.systemTemp.createTempSync('zuke-spec-key-');
      addTearDown(() => root.deleteSync(recursive: true));
      final index = ZukeIndex.create(
        root: root.path,
        inputPaths: const [],
        generatedManifestContent: '{"files":[]}',
        generatedManifestPath: 'lib/src/.zuke-generated.json',
        requirementIds: const [],
        controlIds: const [],
        bindingIds: const [],
        specDiagnostics: const [first, second],
      );
      expect(index.specDiagnostics, hasLength(2));
    },
  );

  test('contract guard requires schema and plugin versions to advance', () {
    final old = {
      'contractVersion': 1,
      'pluginVersion': '0.1.1',
      'serializers': {
        'Index': ['a'],
      },
    };
    expect(
      () => guard.validateContractTransition(old, {
        ...old,
        'serializers': {
          'Index': ['a', 'b'],
        },
      }),
      throwsStateError,
    );
    expect(
      () =>
          guard.validateContractTransition(old, {...old, 'contractVersion': 2}),
      throwsStateError,
    );
    expect(
      () => guard.validateContractTransition(old, {
        ...old,
        'contractVersion': 2,
        'pluginVersion': '0.1.0',
      }),
      throwsStateError,
    );
    guard.validateContractTransition(old, {
      ...old,
      'contractVersion': 2,
      'pluginVersion': '0.1.2',
      'serializers': {
        'Index': ['a', 'b'],
      },
    });
  });
}
