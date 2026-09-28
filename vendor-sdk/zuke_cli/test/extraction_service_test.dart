import 'dart:convert';
import 'dart:io';

import 'package:zuke_cli/src/dart_extractor.dart';
import 'package:zuke_cli/src/ir.dart';
import 'package:test/test.dart';
import 'package:zuke_core/zuke_core.dart' show SourceSnapshotDigest;
import 'package:zuke_frontend/zuke_frontend.dart';
import 'package:zuke_cli/src/extraction_service.dart';

void main() {
  group('ExtractionService Cache Invalidation', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('zuke-extract-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test(
      'content-addressed cache invalidates on file content change',
      () async {
        final srcDir = Directory('${tempDir.path}/lib')
          ..createSync(recursive: true);
        File('${srcDir.path}/math.dart').writeAsStringSync('const a = 1;');
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
          'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
        );

        final output1 = await DartExtractor().extract(
          tempDir.path,
          roots: ['lib'],
          target: 'backend',
        );
        final digest1 = output1.inputDigest;

        File('${srcDir.path}/math.dart').writeAsStringSync('const a = 2;');
        final output2 = await DartExtractor().extract(
          tempDir.path,
          roots: ['lib'],
          target: 'backend',
        );
        final digest2 = output2.inputDigest;

        expect(digest1, isNotEmpty);
        expect(digest2, isNotEmpty);
        expect(digest1, isNot(equals(digest2)));
      },
    );

    test('cache invalidates on imported constant change', () async {
      final libDir = Directory('${tempDir.path}/lib')
        ..createSync(recursive: true);
      final constantsDir = Directory('${tempDir.path}/lib/constants')
        ..createSync(recursive: true);
      File(
        '${constantsDir.path}/values.dart',
      ).writeAsStringSync('const baseValue = 10;\n');
      File('${libDir.path}/calculator.dart').writeAsStringSync(
        "import 'constants/values.dart';\nconst result = baseValue + 5;\n",
      );
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
      );

      final output1 = await DartExtractor().extract(
        tempDir.path,
        roots: ['lib'],
        target: 'backend',
      );
      final digest1 = output1.inputDigest;

      File(
        '${constantsDir.path}/values.dart',
      ).writeAsStringSync('const baseValue = 20;\n');
      final output2 = await DartExtractor().extract(
        tempDir.path,
        roots: ['lib'],
        target: 'backend',
      );
      final digest2 = output2.inputDigest;

      expect(digest1, isNotEmpty);
      expect(digest2, isNotEmpty);
      expect(digest1, isNot(equals(digest2)));
    });

    test(
      'extracts configured packages, persists cache, and reuses it',
      () async {
        _writePackage(tempDir);
        final workspace = _workspace(tempDir);
        final service = ExtractionService();

        final first = await service.extract(workspace);
        final second = await service.extract(workspace);

        expect(first.errors, isEmpty);
        expect(first.outputs, hasLength(1));
        expect(first.outputs.single.symbols, isNotEmpty);
        expect(second.outputs, hasLength(1));
        expect(
          second.outputs.single.provenanceDigest,
          first.outputs.single.provenanceDigest,
          reason: 'a cache hit must republish the same snapshot identity',
        );
        expect(second.outputs.single.symbols, isNotEmpty);
        expect(second.outputs.single.graph, isNotNull);
        expect(
          second.outputs.single.graph!.nodes.map((node) => node.id),
          contains('route:endpoint.test'),
        );
        final cache = Directory('${tempDir.path}/.zuke/cache/dart');
        expect(cache.existsSync(), isTrue);
        final cacheFiles = cache.listSync().whereType<File>().toList();
        expect(cacheFiles, hasLength(1));
        final cacheJson = jsonDecode(cacheFiles.single.readAsStringSync());
        expect(
          (cacheJson['adapter'] as Map)['compatibilityId'],
          DartExtractor.compatibilityId,
        );
      },
    );

    test(
      'does not duplicate annotation-only providers when the cache is reused',
      () async {
        _writeAnnotationOnlyPackage(tempDir);
        File('${tempDir.path}/lib/app.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

@ProvidesControl(
  ['CTRL-CACHE-REVISION'],
  kind: ControlProviderKind.applicationValidator,
)
void provideControl() {}
''');
        final workspace = _workspace(tempDir);
        final service = ExtractionService();

        final first = await service.extract(workspace);
        expect(first.errors, isEmpty);
        final current = first.outputs.single;
        expect(
          current.symbols.where(
            (symbol) => symbol.kind == ExtractedSymbolKind.controlProvider,
          ),
          hasLength(1),
        );

        // The next extraction is served by the cache namespace. A stale cache
        // produced by the previous implementation would contain a synthetic
        // provider symbol as well as the annotation declaration.
        final second = await service.extract(workspace);
        expect(second.errors, isEmpty);
        final cached = second.outputs.single;
        final providers = cached.symbols.where(
          (symbol) => symbol.kind == ExtractedSymbolKind.controlProvider,
        );
        expect(providers, hasLength(1));
        expect(providers.single.symbolId, endsWith('#provideControl'));
      },
    );

    test(
      'excludes exactly the generated manifest paths from the source digest',
      () async {
        _writeAnnotationOnlyPackage(tempDir);
        final generated = Directory('${tempDir.path}/lib/src/generated')
          ..createSync(recursive: true);
        final contract = File('${generated.path}/feat_one_contracts.g.dart')
          ..writeAsStringSync('// generated contract v1\n');
        File('${tempDir.path}/lib/src/.zuke-generated.json').writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert({
            'files': [
              {'path': 'lib/src/generated/feat_one_contracts.g.dart', 'contentHash': 'unused'},
            ],
            'hash': 'unused',
          })}\n',
        );
        // A `.g.dart` from another generator is hand-maintained input, not a
        // Zuke artifact, and must stay in the digest.
        final freezed = File('${tempDir.path}/lib/src/analytics.freezed.dart')
          ..writeAsStringSync('// hand-maintained generated code v1\n');

        final workspace = WorkspaceDiscoveryResult(
          config: ZukeConfig(
            root: tempDir.path,
            contractOutput: 'lib/src/generated',
            workspaceTargets: {
              'backend': const WorkspaceTarget(
                id: 'backend',
                language: 'dart',
                framework: 'dart',
                packages: [
                  WorkspacePackage(id: 'test_pkg', path: '.', roots: ['lib']),
                ],
              ),
            },
          ),
          data: const MetadataExtractorResult(),
        );
        final service = ExtractionService();

        final first = await service.extract(workspace);
        expect(first.errors, isEmpty);
        final before = first.outputs.single.provenanceDigest;

        contract.writeAsStringSync('// generated contract v2\n');
        final regenerated = await service.extract(workspace);
        expect(regenerated.errors, isEmpty);
        expect(
          regenerated.outputs.single.provenanceDigest,
          before,
          reason:
              'a regenerated contract is already pinned by the contract '
              'digest and must not move the source digest',
        );

        freezed.writeAsStringSync('// hand-maintained generated code v2\n');
        final edited = await service.extract(workspace);
        expect(edited.errors, isEmpty);
        expect(
          edited.outputs.single.provenanceDigest,
          isNot(before),
          reason: 'a non-manifest .g.dart is real source and must be hashed',
        );
      },
    );

    test(
      'a regenerated contract misses the cache without moving the recorded digest',
      () async {
        _writeAnnotationOnlyPackage(tempDir);
        final generated = Directory('${tempDir.path}/lib/src/generated')
          ..createSync(recursive: true);
        final contract = File('${generated.path}/feat_one_contracts.g.dart')
          ..writeAsStringSync('// generated contract v1\n');
        File('${tempDir.path}/lib/src/.zuke-generated.json').writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert({
            'files': [
              {'path': 'lib/src/generated/feat_one_contracts.g.dart', 'contentHash': 'unused'},
            ],
            'hash': 'unused',
          })}\n',
        );
        final workspace = WorkspaceDiscoveryResult(
          config: ZukeConfig(
            root: tempDir.path,
            contractOutput: 'lib/src/generated',
            workspaceTargets: {
              'backend': const WorkspaceTarget(
                id: 'backend',
                language: 'dart',
                framework: 'dart',
                packages: [
                  WorkspacePackage(id: 'test_pkg', path: '.', roots: ['lib']),
                ],
              ),
            },
          ),
          data: const MetadataExtractorResult(),
        );
        final service = ExtractionService();
        int cacheEntries() => Directory(
          '${tempDir.path}/.zuke/cache/dart',
        ).listSync().whereType<File>().length;

        final first = await service.extract(workspace);
        expect(first.errors, isEmpty);
        final digest = first.outputs.single.provenanceDigest;
        final entriesAfterFirst = cacheEntries();
        expect(entriesAfterFirst, 1);

        // The provenance digest ignores the contract, so the recorded value is
        // stable...
        contract.writeAsStringSync('// generated contract v2\n');
        final regenerated = await service.extract(workspace);
        expect(regenerated.outputs.single.provenanceDigest, digest);
        // ...but extraction reads it, so the cache must not serve the old
        // symbols under a reused key.
        expect(
          cacheEntries(),
          greaterThan(entriesAfterFirst),
          reason:
              'a regenerated contract has to miss the extraction cache, or a '
              'later run reuses stale symbols and digests',
        );
      },
    );

    test('the published identity and the cache identity differ exactly where '
        'they should', () async {
      // The two digests are separate quantities, so this states the whole
      // contract in one place: the published identity ignores generated
      // files, the cache identity covers them, and nothing else moves.
      _writeAnnotationOnlyPackage(tempDir);
      final source = File('${tempDir.path}/lib/placeholder.dart');
      final generated = Directory('${tempDir.path}/lib/src/generated')
        ..createSync(recursive: true);
      final contract = File('${generated.path}/feat_one_contracts.g.dart')
        ..writeAsStringSync('// generated contract v1\n');
      File('${tempDir.path}/lib/src/.zuke-generated.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
          'files': [
            {'path': 'lib/src/generated/feat_one_contracts.g.dart', 'contentHash': 'unused'},
          ],
          'hash': 'unused',
        })}\n',
      );
      final workspace = WorkspaceDiscoveryResult(
        config: ZukeConfig(
          root: tempDir.path,
          contractOutput: 'lib/src/generated',
          workspaceTargets: {
            'backend': const WorkspaceTarget(
              id: 'backend',
              language: 'dart',
              framework: 'dart',
              packages: [
                WorkspacePackage(id: 'test_pkg', path: '.', roots: ['lib']),
              ],
            ),
          },
        ),
        data: const MetadataExtractorResult(),
      );
      final service = ExtractionService();
      final cacheDirectory = Directory('${tempDir.path}/.zuke/cache/dart');

      Future<({SourceSnapshotDigest? published, Set<String> cacheKeys})>
      snapshot() async {
        final result = await service.extract(workspace);
        expect(result.errors, isEmpty);
        return (
          published: result.outputs.single.provenanceDigest,
          cacheKeys: {
            for (final entry in cacheDirectory.listSync().whereType<File>())
              entry.uri.pathSegments.last,
          },
        );
      }

      final initial = await snapshot();
      expect(
        initial.published,
        isNotNull,
        reason: 'the service is the only publisher of a snapshot identity',
      );
      expect(initial.cacheKeys, hasLength(1));

      // The adapter's own read-digest and the published identity are
      // different quantities. Collapsing them is how the extraction cache and
      // the recorded digest came to disagree, so pin them apart.
      final output = (await service.extract(workspace)).outputs.single;
      expect(
        output.provenanceDigest!.value,
        isNot(output.inputDigest),
        reason: 'the published identity must not be the adapter read-digest',
      );

      // Nothing changed: neither identity moves.
      final unchanged = await snapshot();
      expect(unchanged.published, initial.published);
      expect(unchanged.cacheKeys, initial.cacheKeys);

      // Hand-written source is structure: both identities move.
      source.writeAsStringSync('const value = 2;');
      final sourceEdit = await snapshot();
      expect(sourceEdit.published, isNot(initial.published));
      expect(
        sourceEdit.cacheKeys,
        isNot(initial.cacheKeys),
        reason: 'a source edit must miss the cache',
      );

      // A manifest-declared generated file is derived, not source: only the
      // cache identity moves, so evidence and locks stay valid.
      contract.writeAsStringSync('// generated contract v2\n');
      final contractEdit = await snapshot();
      expect(
        contractEdit.published,
        sourceEdit.published,
        reason: 'regenerating a contract must not invalidate evidence',
      );
      expect(
        contractEdit.cacheKeys,
        isNot(sourceEdit.cacheKeys),
        reason: 'regenerating a contract must still miss the cache',
      );
    });

    test(
      'loads wrapped evidence and rejects duplicates and malformed files',
      () async {
        _writePackage(tempDir);
        final evidence = Directory('${tempDir.path}/evidence')..createSync();
        final record = EvidenceRecord(
          requirementId: 'RULE-TEST-001',
          evidenceType: 'domain-unit',
          target: 'backend',
          executionId: 'run-1',
          profile: 'pullRequest',
          digests: _digests(),
          candidateId: 'SCN-TEST-001',
          runnerId: 'unit-runner',
          runnerCompatibilityId: 'unit-runner-v1',
          sourcePackage: 'test_pkg',
          sourceAdapter: 'dart-source',
          sourceCompatibilityId: DartExtractor.compatibilityId,
        ).toJson();
        File(
          '${evidence.path}/a.json',
        ).writeAsStringSync(jsonEncode({'record': record}));
        File('${evidence.path}/b.json').writeAsStringSync(jsonEncode([record]));
        File('${evidence.path}/c.json').writeAsStringSync('{not-json');
        File('${evidence.path}/d.json').writeAsStringSync('"not-a-record"');

        final result = await ExtractionService().extract(_workspace(tempDir));

        expect(
          result.evidenceRecords,
          hasLength(1),
          reason: '${result.errors}',
        );
        expect(
          result.errors,
          containsAll([
            contains('Duplicate evidence executionId: run-1'),
            contains('Malformed evidence file'),
            contains('Evidence file is not a record or record list'),
          ]),
        );

        final replacementExtraction = await ExtractionService().extract(
          _workspace(tempDir),
          includeEvidence: false,
        );
        expect(replacementExtraction.evidenceRecords, isEmpty);
        expect(
          replacementExtraction.errors,
          isNot(anyElement(contains('evidence'))),
        );
      },
    );

    /// Build a workspace with either the default or a configured evidence path.
    WorkspaceDiscoveryResult evidenceWorkspace(
      Directory root, {
      String? evidenceOutput,
    }) {
      return WorkspaceDiscoveryResult(
        config: ZukeConfig(
          root: root.path,
          evidenceOutput: evidenceOutput,
          workspaceTargets: {
            'backend': const WorkspaceTarget(
              id: 'backend',
              language: 'dart',
              framework: 'dart',
              packages: [
                WorkspacePackage(id: 'backend', path: '.', roots: ['lib']),
              ],
            ),
          },
        ),
        data: const MetadataExtractorResult(),
      );
    }

    EvidenceRecord buildRecord(String requirementId, String executionId) =>
        EvidenceRecord(
          requirementId: requirementId,
          evidenceType: 'domain-unit',
          target: 'backend',
          executionId: executionId,
          profile: 'pullRequest',
          digests: _digests(),
          candidateId: 'SCN-TEST-001',
          runnerId: 'unit-runner',
          runnerCompatibilityId: 'unit-runner-v1',
          sourcePackage: 'test_pkg',
          sourceAdapter: 'dart-source',
          sourceCompatibilityId: DartExtractor.compatibilityId,
        );

    test('evidence published to the default location is readable', () {
      // The default must be a single value. When it was not, a workspace that
      // left `evidence.output` unset had `zuke test` publish to one directory
      // and every reader look in another, so the only symptom was "No execution
      // evidence records were observed" plus an unmet-evidence finding for every
      // requirement in the workspace.
      _writePackage(tempDir);
      final workspace = evidenceWorkspace(tempDir);
      expect(
        workspace.config.evidenceOutput,
        isNull,
        reason: 'guards the premise: this workspace configures no output',
      );

      final published = Directory(
        '${tempDir.path}/${ZukeConfig.defaultEvidenceOutput}',
      )..createSync(recursive: true);
      File('${published.path}/run.json').writeAsStringSync(
        jsonEncode({
          'record': buildRecord('RULE-TEST-001', 'run-default').toJson(),
        }),
      );

      expect(
        ExtractionService()
            .publishedEvidence(workspace)
            .map((record) => record.requirementId),
        contains('RULE-TEST-001'),
        reason: 'the write default and the read default must be the same path',
      );
    });

    test('records under the legacy .zuke/evidence path are still read', () {
      // A runner may declare its own `evidenceOutput`, and workspaces that
      // published there before the default was unified must not lose evidence.
      _writePackage(tempDir);
      final workspace = evidenceWorkspace(tempDir);
      final legacy = Directory('${tempDir.path}/.zuke/evidence')
        ..createSync(recursive: true);
      File('${legacy.path}/old.json').writeAsStringSync(
        jsonEncode({
          'record': buildRecord('RULE-LEGACY-001', 'run-legacy').toJson(),
        }),
      );

      expect(
        ExtractionService()
            .publishedEvidence(workspace)
            .map((record) => record.requirementId),
        contains('RULE-LEGACY-001'),
      );
    });

    test('current default evidence takes priority over legacy records', () {
      _writePackage(tempDir);
      final workspace = evidenceWorkspace(tempDir);
      final current = Directory(
        '${tempDir.path}/${ZukeConfig.defaultEvidenceOutput}',
      )..createSync(recursive: true);
      final legacy = Directory('${tempDir.path}/.zuke/evidence')
        ..createSync(recursive: true);
      File('${current.path}/run.json').writeAsStringSync(
        jsonEncode({
          'record': buildRecord('RULE-CURRENT-001', 'same-run').toJson(),
        }),
      );
      File('${legacy.path}/run.json').writeAsStringSync(
        jsonEncode({
          'record': buildRecord('RULE-OLD-001', 'same-run').toJson(),
        }),
      );

      expect(
        ExtractionService()
            .publishedEvidence(workspace)
            .map((record) => record.requirementId),
        ['RULE-CURRENT-001'],
      );
    });

    test('configured evidence path excludes legacy and trims whitespace', () {
      _writePackage(tempDir);
      final workspace = evidenceWorkspace(
        tempDir,
        evidenceOutput: '  custom/evidence  ',
      );
      expect(workspace.config.resolvedEvidenceOutput, 'custom/evidence');
      final configured = Directory('${tempDir.path}/custom/evidence')
        ..createSync(recursive: true);
      final legacy = Directory('${tempDir.path}/.zuke/evidence')
        ..createSync(recursive: true);
      File('${configured.path}/run.json').writeAsStringSync(
        jsonEncode({
          'record': buildRecord('RULE-CUSTOM-001', 'custom-run').toJson(),
        }),
      );
      File('${legacy.path}/run.json').writeAsStringSync(
        jsonEncode({
          'record': buildRecord('RULE-OLD-001', 'legacy-run').toJson(),
        }),
      );

      expect(
        ExtractionService()
            .publishedEvidence(workspace)
            .map((record) => record.requirementId),
        ['RULE-CUSTOM-001'],
      );
    });

    test(
      'feeds native Dart Frog topology into the proof extraction outputs',
      () async {
        final routes = Directory('${tempDir.path}/routes')
          ..createSync(recursive: true);
        File('${routes.path}/_middleware.dart').writeAsStringSync('''
typedef Handler = Object Function(Object);
Handler middleware(Handler handler) => handler;
''');
        File(
          '${routes.path}/index.dart',
        ).writeAsStringSync('Object onRequest(Object request) => Object();');
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
          'name: dart_frog_fixture\\nenvironment:\\n  sdk: ">=3.10.0 <4.0.0"\\n',
        );
        final workspace = WorkspaceDiscoveryResult(
          config: ZukeConfig(
            root: tempDir.path,
            workspaceTargets: {
              'backend': const WorkspaceTarget(
                id: 'backend',
                language: 'dart',
                framework: 'dart-frog',
                packages: [
                  WorkspacePackage(id: 'backend', path: '.', roots: ['routes']),
                ],
              ),
            },
          ),
          data: const MetadataExtractorResult(),
        );

        final result = await ExtractionService().extract(
          workspace,
          includeEvidence: false,
        );

        expect(result.topologyOutputs, hasLength(1));
        expect(
          result.topologyOutputs.single.nodes.any(
            (node) => node.kind == 'route',
          ),
          isTrue,
        );
        final topologyProjection = result.outputs.firstWhere(
          (output) => output.graph!.nodes.any(
            (node) => node.properties['topologyKind'] == 'route',
          ),
        );
        expect(
          topologyProjection.graph!.nodes.any(
            (node) => node.properties['topologyKind'] == 'route',
          ),
          isTrue,
        );
        expect(
          topologyProjection.inputDigest,
          matches(RegExp(r'^[a-f0-9]{64}$')),
        );
        expect(
          topologyProjection.inputDigest,
          isNot(equals(topologyProjection.adapter.compatibilityId)),
        );
      },
    );

    test('can limit extraction to the requested target', () async {
      _writePackage(tempDir);
      final workspace = WorkspaceDiscoveryResult(
        config: ZukeConfig(
          root: tempDir.path,
          workspaceTargets: {
            'backend': const WorkspaceTarget(
              id: 'backend',
              language: 'dart',
              framework: 'dart',
              packages: [
                WorkspacePackage(id: 'test_pkg', path: '.', roots: ['lib']),
              ],
            ),
            'missing': const WorkspaceTarget(
              id: 'missing',
              language: 'dart',
              framework: 'dart',
              packages: [
                WorkspacePackage(
                  id: 'missing_pkg',
                  path: 'missing',
                  roots: ['lib'],
                ),
              ],
            ),
          },
        ),
        data: const MetadataExtractorResult(),
      );

      final result = await ExtractionService().extract(
        workspace,
        includeEvidence: false,
        targetId: 'backend',
      );

      expect(result.errors, isEmpty);
      expect(result.outputs, hasLength(1));
      expect(result.outputs.single.packageName, 'test_pkg');
    });

    test('can extract only Dart Frog topology', () async {
      final routes = Directory('${tempDir.path}/routes')
        ..createSync(recursive: true);
      File('${routes.path}/_middleware.dart').writeAsStringSync('''
typedef Handler = Object Function(Object);
Handler middleware(Handler handler) => handler;
''');
      File(
        '${routes.path}/index.dart',
      ).writeAsStringSync('Object onRequest(Object request) => Object();');
      final evidence = Directory('${tempDir.path}/evidence')
        ..createSync(recursive: true);
      File('${evidence.path}/malformed.json').writeAsStringSync('{not-json');
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
        'name: dart_frog_topology_fixture\nenvironment:\n'
        '  sdk: ">=3.10.0 <4.0.0"\n',
      );
      final workspace = WorkspaceDiscoveryResult(
        config: ZukeConfig(
          root: tempDir.path,
          evidenceOutput: 'evidence',
          workspaceTargets: {
            'backend': const WorkspaceTarget(
              id: 'backend',
              language: 'dart',
              framework: 'dart-frog',
              packages: [
                WorkspacePackage(id: 'backend', path: '.', roots: ['routes']),
              ],
            ),
            'dart': const WorkspaceTarget(
              id: 'dart',
              language: 'dart',
              framework: 'dart',
              packages: [
                WorkspacePackage(id: 'dart', path: '.', roots: ['lib']),
              ],
            ),
          },
        ),
        data: const MetadataExtractorResult(),
      );

      final result = await ExtractionService().extract(
        workspace,
        targetId: 'backend',
        topologyOnly: true,
      );

      expect(result.errors, isEmpty);
      expect(result.outputs, isEmpty);
      expect(result.evidenceRecords, isEmpty);
      expect(result.topologyOutputs, hasLength(1));
      expect(
        result.topologyOutputs.single.nodes.any((node) => node.kind == 'route'),
        isTrue,
      );
    });

    test(
      'projects middleware initialization edges to annotated implementations',
      () async {
        final lib = Directory('${tempDir.path}/lib')
          ..createSync(recursive: true);
        final routes = Directory('${tempDir.path}/routes')
          ..createSync(recursive: true);
        File('${lib.path}/background.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';

@ImplementsRequirement(['RULE-TEST-001'])
class BackgroundWorker {
  static Object create() => Object();
}
''');
        File('${routes.path}/_middleware.dart').writeAsStringSync('''
import '../lib/background.dart';

class Handler {
  Handler use(Object middleware) => this;
}
Handler middleware(Handler handler) => handler.use(dependencies());
Handler dependencies() => BackgroundWorker.create() as Handler;
''');
        File(
          '${routes.path}/index.dart',
        ).writeAsStringSync('Object onRequest(Object request) => Object();');
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
          'name: extraction_fixture\\nenvironment:\\n'
          '  sdk: ">=3.10.0 <4.0.0"\\n',
        );
        final packageConfig = _workspacePackageConfig();
        final toolDirectory = Directory('${tempDir.path}/.dart_tool')
          ..createSync(recursive: true);
        final workspaceUri = packageConfig.parent.parent.uri.toString();
        final resolvedConfig = packageConfig.readAsStringSync().replaceAll(
          '"rootUri": "../',
          '"rootUri": "$workspaceUri',
        );
        File(
          '${toolDirectory.path}/package_config.json',
        ).writeAsStringSync(resolvedConfig);

        final result = await ExtractionService().extract(
          WorkspaceDiscoveryResult(
            config: ZukeConfig(
              root: tempDir.path,
              workspaceTargets: {
                'backend': const WorkspaceTarget(
                  id: 'backend',
                  language: 'dart',
                  framework: 'dart-frog',
                  packages: [
                    WorkspacePackage(
                      id: 'backend',
                      path: '.',
                      roots: ['lib', 'routes'],
                    ),
                  ],
                ),
              },
            ),
            data: const MetadataExtractorResult(),
          ),
          includeEvidence: false,
        );

        expect(result.errors, isEmpty);
        final projection = result.outputs.firstWhere(
          (output) =>
              output.graph?.edges.any(
                (edge) =>
                    edge.sourceId.contains('/middleware/') &&
                    edge.targetId.contains('#BackgroundWorker'),
              ) ??
              false,
        );
        expect(
          projection.graph!.edges.any(
            (edge) =>
                edge.sourceId.contains('/middleware/') &&
                edge.targetId.contains('#BackgroundWorker'),
          ),
          isTrue,
        );
      },
    );

    test('reports invalid target entries and missing package roots', () async {
      final workspace = WorkspaceDiscoveryResult(
        config: ZukeConfig(
          root: tempDir.path,
          workspaceTargets: {
            'dart': const WorkspaceTarget(
              id: 'dart',
              language: 'dart',
              framework: 'dart',
              packages: [
                WorkspacePackage(
                  id: 'missing',
                  path: 'missing',
                  roots: ['lib'],
                ),
              ],
            ),
          },
        ),
        data: const MetadataExtractorResult(),
      );

      final result = await ExtractionService().extract(workspace);

      expect(result.outputs, isEmpty);
      expect(result.errors.single, contains('target package not found'));
    });
  });
}

void _writePackage(Directory root) {
  final lib = Directory('${root.path}/lib')..createSync(recursive: true);
  File('${lib.path}/service.dart').writeAsStringSync('''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_http_runtime/zuke_http_runtime.dart';

@PresentsRequirement(['RULE-TEST-001'])
void present() {}

@VerifiesRequirement(
  ['RULE-TEST-001'],
  evidenceType: 'domain-unit',
  scenarioIds: ['SCN-TEST-001'],
)
void verify() {}

@ImplementsRequirement(['RULE-TEST-001'], variant: 'preview')
class Controller implements ZukeController {
  @ZukeBinding('controller.id', variant: 'preview')
  String get binding => id;

  @override
  String get id => 'controller';

  @override
  Future<ZukeHttpResponse> handle(ZukeHttpRequest request) async =>
      const ZukeHttpResponse(200);
}

@ProvidesControl(
  ['CTRL-TEST-001'],
  kind: ControlProviderKind.requestMiddleware,
  layer: EnforcementLayer.application,
  variant: 'preview',
)
class Middleware implements ZukeMiddleware {
  @override
  String get id => 'middleware';

  @override
  Future<ZukeHttpResponse?> handle(
    ZukeHttpRequest request,
    ZukeRequestHandler next,
  ) => next(request);
}

class Egress implements ZukePublicEgress {
  @override
  String get id => 'egress';

  @override
  Future<void> write(Object response) async {}
}

final application = ZukeHttpApplication(
  routes: [
    ZukeRouteRegistration(
      endpointId: 'endpoint.test',
      method: 'GET',
      path: '/test',
      middleware: [Middleware()],
      controller: Controller(),
      publicEgress: Egress(),
    ),
  ],
);
''');
  File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: extraction_fixture
environment:
  sdk: ">=3.10.0 <4.0.0"
''');
  final packageConfig = _workspacePackageConfig();
  final toolDirectory = Directory('${root.path}/.dart_tool')
    ..createSync(recursive: true);
  final workspaceUri = packageConfig.parent.parent.uri.toString();
  final resolvedConfig = packageConfig.readAsStringSync().replaceAll(
    '"rootUri": "../',
    '"rootUri": "$workspaceUri',
  );
  File(
    '${toolDirectory.path}/package_config.json',
  ).writeAsStringSync(resolvedConfig);
}

void _writeAnnotationOnlyPackage(Directory root) {
  final lib = Directory('${root.path}/lib')..createSync(recursive: true);
  File('${lib.path}/placeholder.dart').writeAsStringSync('const value = 1;');
  File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: extraction_fixture
environment:
  sdk: ">=3.10.0 <4.0.0"
''');
  final packageConfig = _workspacePackageConfig();
  final toolDirectory = Directory('${root.path}/.dart_tool')
    ..createSync(recursive: true);
  final workspaceUri = packageConfig.parent.parent.uri.toString();
  final resolvedConfig = packageConfig.readAsStringSync().replaceAll(
    '"rootUri": "../',
    '"rootUri": "$workspaceUri',
  );
  File(
    '${toolDirectory.path}/package_config.json',
  ).writeAsStringSync(resolvedConfig);
}

WorkspaceDiscoveryResult _workspace(Directory root) => WorkspaceDiscoveryResult(
  config: ZukeConfig(
    root: root.path,
    evidenceOutput: 'evidence',
    workspaceTargets: {
      'backend': const WorkspaceTarget(
        id: 'backend',
        language: 'dart',
        framework: 'dart',
        packages: [
          WorkspacePackage(id: 'test_pkg', path: '.', roots: ['lib']),
        ],
      ),
    },
  ),
  data: const MetadataExtractorResult(),
);

File _workspacePackageConfig() {
  var directory = Directory.current.absolute;
  while (true) {
    final packageConfig = File(
      '${directory.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}package_config.json',
    );
    if (packageConfig.existsSync() &&
        File(
          '${directory.path}${Platform.pathSeparator}melos.yaml',
        ).existsSync()) {
      return packageConfig;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate the workspace package config.');
    }
    directory = parent;
  }
}

Map<String, String> _digests() => {
  for (final key in const [
    'source',
    'contract',
    'mapping',
    'specificationIndex',
    'result',
  ])
    key: 'sha256:${List.filled(64, 'a').join()}',
};
