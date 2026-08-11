import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zuke_cli/tooling.dart';

void main() {
  test('unresolved elements are never treated as matching', () {
    expect(isResolvedLibrary(null, 'package:example/example.dart'), isFalse);
    expect(resolvedElementName(null), isNull);
  });

  test(
    'index rejects generated output changed behind an unchanged manifest',
    () {
      final root = Directory.systemTemp.createTempSync('zuke-index-');
      addTearDown(() => _deleteDirectoryWithRetry(root));
      final input = File('${root.path}/zuke.yaml')..writeAsStringSync('v: 1\n');
      final output = File('${root.path}/generated.dart')
        ..writeAsStringSync('one\n');
      final manifest = File('${root.path}/manifest.json')
        ..writeAsStringSync(
          jsonEncode({
            'files': [
              {
                'path': 'generated.dart',
                'contentHash': sha256
                    .convert(output.readAsBytesSync())
                    .toString(),
              },
            ],
          }),
        );
      final index = ZukeIndex.create(
        root: root.path,
        inputPaths: [input.path],
        generatedManifestContent: manifest.readAsStringSync(),
        generatedManifestPath: 'manifest.json',
        requirementIds: const [],
        controlIds: const [],
        bindingIds: const [],
      );
      expect(index.isCurrent(root: root.path), isTrue);

      output.writeAsStringSync('two\n');
      expect(index.isCurrent(root: root.path), isFalse);
      final issues = index.freshnessIssues(root: root.path);
      expect(issues, hasLength(1));
      expect(
        issues.single.kind,
        ZukeIndexFreshnessIssueKind.generatedOutputDigestMismatch,
      );
      expect(issues.single.path, 'generated.dart');
    },
  );

  test('annotation target support matrix is explicit and fail closed', () {
    expect(
      supportsZukeAnnotationTarget('ImplementsRequirement', 'mixin'),
      isTrue,
    );
    expect(
      supportsZukeAnnotationTarget('PresentsRequirement', 'field'),
      isFalse,
    );
    expect(supportsZukeAnnotationTarget('ProvidesControl', 'function'), isTrue);
    expect(supportsZukeAnnotationTarget('ZukeBinding', 'getter'), isTrue);
    expect(
      supportsZukeAnnotationTarget('VerifiesRequirement', 'class'),
      isFalse,
    );
    expect(supportsZukeAnnotationTarget('Unknown', 'class'), isFalse);
    expect(isZukeAnnotation(null), isFalse);
    expect(zukeAnnotationName(null), isNull);
  });

  test('index JSON round-trips and detects input and manifest drift', () {
    final root = Directory.systemTemp.createTempSync('zuke-index-json-');
    addTearDown(() => root.deleteSync(recursive: true));
    final input = File('${root.path}/zuke.yaml')
      ..writeAsStringSync('schemaVersion: 2\n');
    final output = File('${root.path}/generated.dart')
      ..writeAsStringSync('generated\n');
    final manifest = File('${root.path}/manifest.json')
      ..writeAsStringSync(
        jsonEncode({
          'files': [
            {
              'path': 'generated.dart',
              'contentHash': sha256
                  .convert(output.readAsBytesSync())
                  .toString(),
            },
          ],
        }),
      );
    final created = ZukeIndex.create(
      root: root.path,
      inputPaths: [input.path, '${root.path}/missing.yaml'],
      generatedManifestContent: manifest.readAsStringSync(),
      generatedManifestPath: 'manifest.json',
      requirementIds: const ['RULE-1', ''],
      controlIds: const ['CTRL-1', ''],
      bindingIds: const ['binding-1', ''],
    );
    final indexFile = File('${root.path}/index.json')
      ..writeAsStringSync(jsonEncode(created.toJson()));
    final decoded = ZukeIndex.read(indexFile);

    expect(decoded.requirementIds, {'RULE-1'});
    expect(decoded.controlIds, {'CTRL-1'});
    expect(decoded.bindingIds, {'binding-1'});
    expect(decoded.inputs.single.path, 'zuke.yaml');
    expect(decoded.isCurrent(root: root.path), isTrue);

    input.writeAsStringSync('schemaVersion: 3\n');
    expect(decoded.isCurrent(root: root.path), isFalse);
    expect(
      decoded.freshnessIssues(root: root.path).single.kind,
      ZukeIndexFreshnessIssueKind.inputDigestMismatch,
    );
    input.writeAsStringSync('schemaVersion: 2\n');
    manifest.writeAsStringSync('{"files":"invalid"}');
    expect(decoded.isCurrent(root: root.path), isFalse);
    expect(
      decoded.freshnessIssues(root: root.path).single.kind,
      ZukeIndexFreshnessIssueKind.generatedManifestDigestMismatch,
    );
  });

  test(
    'freshness issues distinguish malformed manifests and missing files',
    () {
      final root = Directory.systemTemp.createTempSync('zuke-index-issues-');
      addTearDown(() => _deleteDirectoryWithRetry(root));
      final input = File('${root.path}/zuke.yaml')
        ..writeAsStringSync('schemaVersion: 2\n');
      final manifest = File('${root.path}/manifest.json')
        ..writeAsStringSync('{"files":"invalid"}');
      final malformed = ZukeIndex.create(
        root: root.path,
        inputPaths: [input.path],
        generatedManifestContent: manifest.readAsStringSync(),
        generatedManifestPath: 'manifest.json',
        requirementIds: const [],
        controlIds: const [],
        bindingIds: const [],
      );
      expect(
        malformed.freshnessIssues(root: root.path).single.kind,
        ZukeIndexFreshnessIssueKind.generatedManifestMalformed,
      );

      manifest.writeAsStringSync('{"files":[]}');
      final missingInput = ZukeIndex.create(
        root: root.path,
        inputPaths: [input.path],
        generatedManifestContent: manifest.readAsStringSync(),
        generatedManifestPath: 'manifest.json',
        requirementIds: const [],
        controlIds: const [],
        bindingIds: const [],
      );
      input.deleteSync();
      final inputIssue = missingInput.freshnessIssues(root: root.path).single;
      expect(inputIssue.kind, ZukeIndexFreshnessIssueKind.inputMissing);
      expect(inputIssue.path, 'zuke.yaml');

      manifest.deleteSync();
      expect(
        missingInput.freshnessIssues(root: root.path).single.kind,
        ZukeIndexFreshnessIssueKind.generatedManifestMissing,
      );
    },
  );

  test('index parser rejects malformed schemas, IDs, inputs, and paths', () {
    final digest = 'sha256:${List.filled(64, 'a').join()}';
    final valid = <String, Object?>{
      'schemaVersion': ZukeIndex.schemaVersion,
      'inputDigest': digest,
      'generatedManifestDigest': digest,
      'generatedManifestPath': 'manifest.json',
      'inputs': [
        {'path': 'zuke.yaml', 'digest': digest},
      ],
      'requirementIds': ['RULE-1'],
      'controlIds': ['CTRL-1'],
      'bindingIds': ['binding-1'],
    };
    final invalid = <Map<String, Object?>>[
      {...valid, 'schemaVersion': 'unknown'},
      {...valid, 'inputDigest': ''},
      {
        ...valid,
        'requirementIds': [''],
      },
      {...valid, 'inputs': 'invalid'},
      {
        ...valid,
        'inputs': [
          {'path': '../escape', 'digest': digest},
        ],
      },
      {...valid, 'generatedManifestPath': '../manifest.json'},
    ];

    for (final json in invalid) {
      expect(() => ZukeIndex.fromJson(json), throwsFormatException);
    }
  });
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  var attempts = 0;
  var delay = const Duration(milliseconds: 25);
  while (DateTime.now().isBefore(deadline)) {
    attempts++;
    if (!directory.existsSync()) return;
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(delay);
      delay = delay * 2;
      if (delay > const Duration(milliseconds: 500)) {
        delay = const Duration(milliseconds: 500);
      }
    }
  }
  throw StateError(
    'Unable to remove index fixture after $attempts attempt(s): '
    '${directory.path}',
  );
}
