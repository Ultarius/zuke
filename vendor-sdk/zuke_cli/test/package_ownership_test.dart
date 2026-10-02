import 'dart:io';
import 'package:test/test.dart';
import 'package:zuke_cli/src/tooling/dart_extractor/zuke_index.dart';
import 'package:zuke_cli/src/implementation_claims.dart';
import 'package:zuke_cli/src/requirement_scopes.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

void main() {
  test('index creation and decoding reject conflicting normalized owners', () {
    ZukeIndex create(Map<String, String> targets) => ZukeIndex.create(
      root: Directory.systemTemp.path,
      inputPaths: const [],
      generatedManifestContent: '{"files":[]}',
      generatedManifestPath: 'generated-manifest.json',
      requirementIds: const [],
      controlIds: const [],
      bindingIds: const [],
      packageTargets: targets,
    );
    const targets = {'apps/api': 'first', './apps/api/': 'second'};
    expect(() => create(targets), throwsFormatException);
    final json = create(const {}).toJson()..['packageTargets'] = targets;
    expect(() => ZukeIndex.fromJson(json), throwsFormatException);
  });
  test(
    'direct configurations cannot overwrite either package ownership map',
    () {
      final workspace = WorkspaceDiscoveryResult(
        config: const ZukeConfig(
          workspaceTargets: {
            'app': WorkspaceTarget(
              id: 'app',
              language: 'dart',
              framework: 'flutter',
              packages: [
                WorkspacePackage(id: 'first', path: '.', roots: ['lib']),
                WorkspacePackage(id: 'second', path: './', roots: ['test']),
              ],
            ),
          },
        ),
        data: MetadataExtractorResult(features: const []),
      );
      expect(() => workspacePackageTargets(workspace), throwsFormatException);
      expect(() => workspacePackageIds(workspace), throwsFormatException);
    },
  );
  test('raw lookup maps reject conflicting aliases in either order', () {
    for (final values in [
      {'apps/api': 'first', './apps/api/': 'second'},
      {'./apps/api/': 'second', 'apps/api': 'first'},
    ]) {
      expect(
        () => targetForWorkspacePath(values, 'apps/api/lib/main.dart'),
        throwsFormatException,
      );
      expect(
        () => packageIdForWorkspacePath(values, 'apps/api/lib/main.dart'),
        throwsFormatException,
      );
    }
  });
  test('equivalent aliases for the same owner remain harmless', () {
    const values = {'.': 'app', './': 'app'};
    expect(targetForWorkspacePath(values, 'lib/main.dart'), 'app');
    expect(packageIdForWorkspacePath(values, 'lib/main.dart'), 'app');
  });
}
