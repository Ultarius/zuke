import 'dart:io';

import 'package:zuke_cli/src/workspace_digest.dart';
import 'package:zuke_cli/src/ir.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;

  File writeFile(String relativePath, String contents) {
    final file = File('${workspace.path}/$relativePath');
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync(contents);
  }

  Future<String> digest({Iterable<String> generatedPaths = const []}) =>
      WorkspaceDigest(generatedPaths: generatedPaths).compute(workspace);

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('zuke-workspace-digest-');
    writeFile('zuke.yaml', 'schemaVersion: 3\n');
    writeFile('lib/source.dart', 'const value = 1;\n');
  });

  tearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  test('is deterministic and changes for repository input changes', () async {
    final first = await digest();
    expect(await digest(), first);

    writeFile('lib/source.dart', 'const value = 2;\n');
    expect(await digest(), isNot(first));
  });

  test('hashes only discovered specification inputs when requested', () {
    final config = writeFile('zuke.yaml', 'schemaVersion: 3\n');
    final feature = writeFile(
      'specs/features/example.feature',
      'Feature: One\n',
    );
    final inputs = <String, String>{
      config.path: config.readAsStringSync(),
      feature.path: feature.readAsStringSync(),
    };
    final before = WorkspaceDigest.computeInputContents(workspace, inputs);

    writeFile('lib/source.dart', 'const unrelatedSource = 2;\n');
    expect(WorkspaceDigest.computeInputContents(workspace, inputs), before);

    inputs[feature.path] = 'Feature: Two\n';
    expect(
      WorkspaceDigest.computeInputContents(workspace, inputs),
      isNot(before),
    );
  });

  test('normalizes CRLF for text inputs but preserves binary bytes', () async {
    final feature = writeFile(
      'specs/features/example.feature',
      'Feature: One\n',
    );
    final lf = <String, String>{
      feature.path: 'Feature: One\n',
      '${workspace.path}/zuke.yaml': 'schemaVersion: 3\n',
    };
    final crlf = <String, String>{
      feature.path: 'Feature: One\r\n',
      '${workspace.path}/zuke.yaml': 'schemaVersion: 3\r\n',
    };
    expect(
      WorkspaceDigest.computeInputContents(workspace, lf),
      WorkspaceDigest.computeInputContents(workspace, crlf),
    );

    feature.writeAsStringSync('Feature: One\r\n');
    final crlfWorkspace = await digest();
    feature.writeAsStringSync('Feature: One\n');
    expect(await digest(), crlfWorkspace);

    final mapping = writeFile('mapping.yaml', 'a: 1\r\n');
    final crlfFiltered = WorkspaceDigest.computeFiltered(
      workspace.path,
      (path) => path == 'mapping.yaml',
    );
    mapping.writeAsStringSync('a: 1\n');
    expect(
      WorkspaceDigest.computeFiltered(
        workspace.path,
        (path) => path == 'mapping.yaml',
      ),
      crlfFiltered,
    );
    final binary = File('${workspace.path}/data.bin')
      ..writeAsBytesSync([13, 10]);
    expect(canonicalDigestBytes(binary.path, binary.readAsBytesSync()), [
      13,
      10,
    ]);
    expect(canonicalDigestBytes('invalid.yaml', [0xff]), [0xff]);
  });

  test('prunes tool, evidence, IDE, and platform outputs', () async {
    final before = await digest();
    const ignoredFiles = <String>[
      '.dart_tool/package_config.json',
      '.git/index',
      '.gradle/executionHistory.bin',
      '.idea/workspace.xml',
      '.zuke/analyzer-index.json',
      '.zuke/evidence/records/result.json',
      '.plugin_symlinks/plugin/file.dart',
      '.symlinks/plugin/file.dart',
      '.cxx/debug/object.o',
      '.externalNativeBuild/state.bin',
      'Pods/Manifest.lock',
      'assurance-history/v2/record.json',
      'build/output.bin',
      'coverage/lcov.info',
      'dist/archive.zip',
      'generated/evidence/record.json',
      'node_modules/package/index.js',
      'windows/flutter/ephemeral/flutter_windows.dll.pdb',
      'android/local.properties',
      'project.iml',
      '.flutter-plugins',
      '.flutter-plugins-dependencies',
      'pubspec_overrides.yaml',
    ];
    for (final path in ignoredFiles) {
      writeFile(path, 'ignored: $path\n');
    }

    expect(await digest(), before);
    for (final path in ignoredFiles) {
      writeFile(path, 'changed but still ignored: $path\n');
    }
    expect(await digest(), before);
  });

  test('excludes every generated manifest path and the lock file', () async {
    writeFile('lib/contracts.dart', 'generated v1\n');
    writeFile('custom.lock.json', 'lock v1\n');
    final before = await WorkspaceDigest(
      lockFile: 'custom.lock.json',
      generatedPaths: const ['lib/contracts.dart'],
    ).compute(workspace);

    writeFile('lib/contracts.dart', 'generated v2\n');
    writeFile('custom.lock.json', 'lock v2\n');
    expect(
      await WorkspaceDigest(
        lockFile: 'custom.lock.json',
        generatedPaths: const [r'lib\contracts.dart'],
      ).compute(workspace),
      before,
    );
  });

  test('does not follow file-system links', () async {
    final external = Directory.systemTemp.createTempSync(
      'zuke-workspace-digest-external-',
    );
    addTearDown(() {
      if (external.existsSync()) external.deleteSync(recursive: true);
    });
    final externalFile = File('${external.path}/outside.txt')
      ..writeAsStringSync('outside v1\n');
    final link = Link('${workspace.path}/linked');
    try {
      link.createSync(external.path);
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable in this environment.');
      return;
    }

    final before = await digest();
    externalFile.writeAsStringSync('outside v2\n');
    expect(await digest(), before);
  });

  test('prunes a large ignored file before reading it', () async {
    final before = await digest();
    final file = writeFile(
      'windows/flutter/ephemeral/large-debug-symbols.pdb',
      '',
    );
    final handle = file.openSync(mode: FileMode.write);
    try {
      handle.truncateSync(256 * 1024 * 1024);
    } finally {
      handle.closeSync();
    }

    expect(await digest(), before);
  });

  test('streams a large included file deterministically', () async {
    final file = writeFile('assets/large-input.bin', '');
    final handle = file.openSync(mode: FileMode.write);
    try {
      handle.truncateSync(16 * 1024 * 1024);
    } finally {
      handle.closeSync();
    }

    final first = await digest();
    expect(await digest(), first);
  });

  test('computeFilteredMany matches per-predicate computeFiltered', () {
    writeFile('specs/registry/events.yaml', 'events: []\n');
    writeFile('specs/features/example.feature', 'Feature: One\n');
    writeFile('policies/project-policy.yaml', 'policy: strict\n');
    writeFile('lib/source.dart', 'const other = 1;\n');

    final includes = <String, bool Function(String)>{
      'mapping': WorkspaceDigest.evidenceMappingInclude,
      'specificationIndex': WorkspaceDigest.evidenceSpecificationInclude,
      'unrelated': (path) => path.endsWith('missing.yaml'),
    };

    final many = WorkspaceDigest.computeFilteredMany(workspace.path, includes);
    for (final entry in includes.entries) {
      expect(
        many[entry.key],
        WorkspaceDigest.computeFiltered(workspace.path, entry.value),
        reason: 'bucket ${entry.key}',
      );
    }
    expect(
      many['mapping'],
      WorkspaceDigest.computeEvidenceIndexDigests(workspace.path)['mapping'],
    );
    expect(
      many['specificationIndex'],
      WorkspaceDigest.computeEvidenceIndexDigests(
        workspace.path,
      )['specificationIndex'],
    );
  });

  test('computeFilteredMany returns empty digests for a missing root', () {
    final missing = '${workspace.path}/does-not-exist';
    final many = WorkspaceDigest.computeFilteredMany(missing, {
      'mapping': WorkspaceDigest.evidenceMappingInclude,
    });
    expect(
      many['mapping'],
      WorkspaceDigest.computeFiltered(
        missing,
        WorkspaceDigest.evidenceMappingInclude,
      ),
    );
  });

  test('filtered digests prune ignored tool and platform directories', () {
    writeFile('specs/features/example.feature', 'Feature: One\n');
    final before = WorkspaceDigest.computeEvidenceIndexDigests(workspace.path);

    writeFile('build/specs/features/stale.feature', 'Feature: Stale\n');
    writeFile('.dart_tool/specs/registry/noise.yaml', 'noise: true\n');
    writeFile('generated/policies/noise.yaml', 'noise: true\n');
    writeFile('node_modules/specs/features/noise.feature', 'noise\n');
    writeFile('windows/flutter/ephemeral/specs/noise.feature', 'noise\n');

    expect(WorkspaceDigest.computeEvidenceIndexDigests(workspace.path), before);
    expect(
      WorkspaceDigest.computeFiltered(
        workspace.path,
        WorkspaceDigest.evidenceSpecificationInclude,
      ),
      WorkspaceDigest.computeFilteredMany(workspace.path, {
        'specificationIndex': WorkspaceDigest.evidenceSpecificationInclude,
      })['specificationIndex'],
    );
  });

  test('evidence layouts never sit under pruned directory names', () {
    const ignored = <String>{
      '.dart_tool',
      '.git',
      '.gradle',
      '.idea',
      '.plugin_symlinks',
      '.zuke',
      '.symlinks',
      '.cxx',
      '.externalNativeBuild',
      'Pods',
      'assurance-history',
      'build',
      'coverage',
      'dist',
      'generated',
      'node_modules',
    };
    const legitimateEvidencePaths = <String>[
      'specs/registry/events.yaml',
      'specs/features/example.feature',
      'policies/project-policy.yaml',
      'zuke.yaml',
    ];
    for (final path in legitimateEvidencePaths) {
      expect(
        WorkspaceDigest.evidenceMappingInclude(path) ||
            WorkspaceDigest.evidenceSpecificationInclude(path),
        isTrue,
        reason: path,
      );
      final directorySegments = path.split('/')..removeLast();
      expect(
        directorySegments.where(ignored.contains),
        isEmpty,
        reason: '$path must not live under a pruned directory',
      );
    }
    // Tool trees may contain decoy names; the pruned walk must not hash them.
    expect(
      WorkspaceDigest.evidenceMappingInclude('node_modules/zuke.yaml'),
      isTrue,
    );
    expect(
      WorkspaceDigest.evidenceSpecificationInclude(
        'build/specs/features/example.feature',
      ),
      isFalse,
    );
  });
}
