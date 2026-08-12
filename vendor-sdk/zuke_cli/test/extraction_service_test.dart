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
        );
        final digest1 = output1.inputDigest;

        File('${srcDir.path}/math.dart').writeAsStringSync('const a = 2;');
        final output2 = await DartExtractor().extract(
          tempDir.path,
          roots: ['lib'],
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
      );
      final digest1 = output1.inputDigest;

      File(
        '${constantsDir.path}/values.dart',
      ).writeAsStringSync('const baseValue = 20;\n');
      final output2 = await DartExtractor().extract(
        tempDir.path,
        roots: ['lib'],
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
      'loads wrapped evidence and rejects duplicates and malformed files',
      () async {
        _writePackage(tempDir);
        final evidence = Directory('${tempDir.path}/evidence')..createSync();
        final record = SemanticEvidenceRecord(
          requirementId: 'RULE-TEST-001',
          evidenceType: 'domain-unit',
          target: 'backend',
          executionId: 'run-1',
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
            targetsConfig: {
              'backend': {
                'language': 'dart',
                'framework': 'dart-frog',
                'packages': [
                  {
                    'id': 'backend',
                    'path': '.',
                    'roots': ['routes'],
                  },
                ],
              },
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
      },
    );

    test('reports invalid target entries and missing package roots', () async {
      final workspace = WorkspaceDiscoveryResult(
        config: ZukeConfig(
          root: tempDir.path,
          targetsConfig: {
            'ignored-language': {'language': 'typescript'},
            'not-a-map': 'invalid',
            'dart': {
              'language': 'dart',
              'packages': [
                'invalid',
                {'path': 42},
                {'path': 'missing'},
              ],
            },
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
  target: 'backend',
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

WorkspaceDiscoveryResult _workspace(Directory root) => WorkspaceDiscoveryResult(
  config: ZukeConfig(
    root: root.path,
    evidenceOutput: 'evidence',
    targetsConfig: {
      'backend': {
        'language': 'dart',
        'packages': [
          {
            'path': '.',
            'roots': ['lib'],
          },
        ],
      },
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
