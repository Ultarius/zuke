import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/generated/release_contract.dart';
import 'package:zuke_cli/src/ir.dart';
import 'package:zuke_cli/src/source_output_catalog.dart';
import 'package:zuke_frontend/zuke_frontend.dart';

void main() {
  late Directory root;
  late WorkspaceDiscoveryResult workspace;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zuke-source-catalog-');
    workspace = WorkspaceDiscoveryResult(
      config: ZukeConfig(
        root: root.path,
        // Keep this deliberately stale. The catalog must use the typed model,
        // not the legacy map projection.
        targetPackages: {
          'backend': [
            {
              'id': 'stale-map-package',
              'path': 'missing',
              'roots': ['wrong'],
            },
          ],
        },
        workspaceTargets: {
          'backend': WorkspaceTarget(
            id: 'backend',
            language: 'dart',
            framework: 'dart-frog',
            packages: const [
              WorkspacePackage(id: 'backend', path: '.', roots: ['lib']),
            ],
          ),
        },
      ),
      data: const MetadataExtractorResult(features: []),
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  IrAdapterOutput output({
    String? packageName = 'backend',
    String? packageRoot,
    String compatibilityId = releaseDartSourceCompatibilityId,
  }) {
    return IrAdapterOutput(
      adapter: AdapterDescriptor(
        id: 'dart-analyzer',
        version: '1',
        compatibilityId: compatibilityId,
      ),
      completeness: const IrAdapterCompleteness(),
      symbols: const [],
      inputDigest: 'sha256:${List.filled(64, 'a').join()}',
      packageName: packageName,
      packageRoot: packageRoot ?? root.path,
    );
  }

  test(
    'resolves one exact target, package, adapter, and compatibility match',
    () {
      final catalog = SourceOutputCatalog.build(workspace, [output()]);

      final resolved = catalog.resolve(
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-source',
        sourceCompatibilityId: releaseDartSourceCompatibilityId,
      );

      expect(resolved.output.inputDigest, startsWith('sha256:'));
    },
  );

  test('rejects unknown packages and compatibility mismatches', () {
    final catalog = SourceOutputCatalog.build(workspace, [output()]);

    expect(
      () => catalog.resolve(
        target: 'backend',
        sourcePackage: 'unknown',
        sourceAdapter: 'dart-source',
        sourceCompatibilityId: releaseDartSourceCompatibilityId,
      ),
      throwsA(
        isA<SourceResolveFailure>().having(
          (failure) => failure.code,
          'code',
          'ZK-SOURCE-UNKNOWN-PACKAGE',
        ),
      ),
    );
    expect(
      () => catalog.resolve(
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-source',
        sourceCompatibilityId: 'unsupported-compatibility',
      ),
      throwsA(
        isA<SourceResolveFailure>().having(
          (failure) => failure.code,
          'code',
          'ZK-SOURCE-COMPATIBILITY-MISMATCH',
        ),
      ),
    );
  });

  test('rejects ambiguous and out-of-root outputs', () {
    final ambiguous = SourceOutputCatalog.build(workspace, [
      output(),
      output(),
    ]);
    expect(
      () => ambiguous.resolve(
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-source',
        sourceCompatibilityId: releaseDartSourceCompatibilityId,
      ),
      throwsA(
        isA<SourceResolveFailure>().having(
          (failure) => failure.code,
          'code',
          'ZK-SOURCE-AMBIGUOUS',
        ),
      ),
    );

    final outside = Directory.systemTemp.createTempSync('zuke-source-outside-');
    addTearDown(() => outside.deleteSync(recursive: true));
    final outOfRoot = SourceOutputCatalog.build(workspace, [
      output(packageRoot: outside.path),
    ]);
    expect(
      () => outOfRoot.resolve(
        target: 'backend',
        sourcePackage: 'backend',
        sourceAdapter: 'dart-source',
        sourceCompatibilityId: releaseDartSourceCompatibilityId,
      ),
      throwsA(
        isA<SourceResolveFailure>().having(
          (failure) => failure.code,
          'code',
          'ZK-SOURCE-OUT-OF-ROOT',
        ),
      ),
    );
  });

  test(
    'does not attribute an out-of-root output with a wrong or missing package',
    () {
      final outside = Directory.systemTemp.createTempSync(
        'zuke-source-outside-unidentified-',
      );
      addTearDown(() => outside.deleteSync(recursive: true));

      for (final packageName in <String?>['other-package', null]) {
        final catalog = SourceOutputCatalog.build(workspace, [
          output(packageName: packageName, packageRoot: outside.path),
        ]);

        expect(
          () => catalog.resolve(
            target: 'backend',
            sourcePackage: 'backend',
            sourceAdapter: 'dart-source',
            sourceCompatibilityId: releaseDartSourceCompatibilityId,
          ),
          throwsA(
            isA<SourceResolveFailure>().having(
              (failure) => failure.code,
              'code',
              'ZK-SOURCE-NO-MATCH',
            ),
          ),
        );
      }
    },
  );
}
