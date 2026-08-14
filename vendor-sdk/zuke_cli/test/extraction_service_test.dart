import 'dart:convert';
import 'dart:io';

import 'package:zuke_cli/src/dart_extractor.dart';
import 'package:zuke_cli/src/ir.dart';
import 'package:test/test.dart';
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
          'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <3.11.0"\n',
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
        'name: test_pkg\nenvironment:\n  sdk: ">=3.10.0 <3.11.0"\n',
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
          second.outputs.single.inputDigest,
          first.outputs.single.inputDigest,
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
          current.symbols.where((symbol) => symbol.kind == 'controlProvider'),
          hasLength(1),
        );

        // The next extraction is served by the cache namespace. A stale cache
        // produced by the previous implementation would contain a synthetic
        // provider symbol as well as the annotation declaration.
        final second = await service.extract(workspace);
        expect(second.errors, isEmpty);
        final cached = second.outputs.single;
        final providers = cached.symbols.where(
          (symbol) => symbol.kind == 'controlProvider',
        );
        expect(providers, hasLength(1));
        expect(providers.single.symbolId, endsWith('#provideControl'));
      },
    );

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
          'name: dart_frog_fixture\\nenvironment:\\n  sdk: \">=3.10.0 <3.11.0\"\\n',
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
