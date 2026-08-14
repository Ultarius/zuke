import 'dart:io';

import 'package:zuke_cli/src/dart_extractor.dart';
import 'package:zuke_cli/src/generated/release_contract.dart';
import 'package:test/test.dart';

import '../support/temporary_directory.dart';

void main() {
  test('requires an explicit extraction target', () async {
    final root = Directory.systemTemp.createTempSync('dart-extractor-target-');
    addTearDown(() => deleteTemporaryDirectory(root));

    await expectLater(
      DartExtractor().extract(root.path),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('emits the matrix-owned Dart source compatibility identity', () {
    expect(DartExtractor.compatibilityId, releaseDartSourceCompatibilityId);
    expect(DartExtractor.compatibilityId, 'dart-source-package-v1');
    expect(
      DartExtractor().adapterInfo.compatibilityId,
      'dart-source-package-v1',
    );
  });

  test('DartExtractionResult stores fragments', () {
    final result = DartExtractionResult();
    expect(result.fragments, isEmpty);
    expect(result.errors, isEmpty);
  });

  test('AnnotationTarget stores source location', () {
    final target = AnnotationTarget(
      uri: 'lib/main.dart',
      offset: 0,
      length: 10,
      line: 1,
      column: 1,
      symbolName: 'main',
      kind: 'function',
    );
    expect(target.uri, 'lib/main.dart');
    expect(target.kind, 'function');
  });

  test(
    'extracts supported declarations and executable HTTP topology',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'dart-extractor-fixture-',
      );
      addTearDown(() => deleteTemporaryDirectory(root));
      final dartTool = Directory('${root.path}/.dart_tool')
        ..createSync(recursive: true);
      Directory currentDir = Directory.current.absolute;
      File? rootPackageConfig;
      while (currentDir.path != currentDir.parent.path) {
        final candidate = File(
          '${currentDir.path}/.dart_tool/package_config.json',
        );
        if (candidate.existsSync()) {
          rootPackageConfig = candidate;
          break;
        }
        currentDir = currentDir.parent;
      }
      if (rootPackageConfig != null) {
        final content = rootPackageConfig.readAsStringSync();
        final workspaceUri = currentDir.uri.toString();
        final resolvedContent = content.replaceAll(
          '"rootUri": "../',
          '"rootUri": "$workspaceUri',
        );
        File(
          '${dartTool.path}/package_config.json',
        ).writeAsStringSync(resolvedContent);
      }
      File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: dart_extractor_behavior_fixture
environment:
  sdk: '>=3.10.0 <4.0.0'
''');
      Directory('${root.path}/lib').createSync();
      File('${root.path}/lib/app.dart').writeAsStringSync(r'''
import 'package:zuke_annotations/zuke_annotations.dart';
import 'package:zuke_http_runtime/zuke_http_runtime.dart';

@ImplementsRequirement(['RULE-MIXIN'])
mixin RequirementMixin {}

@ImplementsRequirement(['RULE-EXTENSION-TYPE'])
extension type RequirementId(String value) {}

@PresentsRequirement(['RULE-PRESENTED'])
void presentRequirement() {}

@VerifiesRequirement(
  ['RULE-VERIFIED'],
  evidenceType: 'unit',
  target: 'backend',
  variant: 'preview',
  scenarioIds: ['SCN-VERIFIED'],
)
void verifyRequirement() {}

@ProvidesControl(
  ['CTRL-FUNCTION'],
  kind: ControlProviderKind.requestMiddleware,
  layer: EnforcementLayer.application,
)
void provideControl() {}

@ImplementsRequirement(['RULE-CONTROLLER'], variant: 'preview')
class Controller implements ZukeController {
  @ZukeBinding('controller.id', variant: 'preview')
  String get binding => id;

  @ZukeBinding('')
  String get emptyBinding => '';

  @override
  String get id => 'controller';

  @override
  Future<ZukeHttpResponse> handle(ZukeHttpRequest request) async =>
      const ZukeHttpResponse(200);
}

@ProvidesControl(
  ['CTRL-MIDDLEWARE'],
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

@ProvidesControl(
  ['CTRL-HANDLER'],
  kind: ControlProviderKind.publicErrorMapper,
  layer: EnforcementLayer.application,
)
class Handler implements ZukeErrorHandler {
  @override
  String get id => 'handler';

  @override
  Future<ZukeHttpResponse> handle(Object error, ZukeHttpRequest request) async =>
      const ZukeHttpResponse(500);
}

@ProvidesControl(
  ['CTRL-PROCESSOR'],
  kind: ControlProviderKind.telemetryProcessor,
  layer: EnforcementLayer.application,
)
class Processor implements ZukeLogProcessor {
  @override
  String get id => 'processor';

  @override
  Map<String, Object?> process(Map<String, Object?> event) => event;
}

class Egress implements ZukePublicEgress {
  @override
  String get id => 'egress';

  @override
  Future<void> write(Object response) async {}
}

class Sink implements ZukeLogSink {
  @override
  String get id => 'sink';

  @override
  void write(Map<String, Object?> event) {}
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
  failurePipelines: [
    ZukeFailurePipelineRegistration(
      sourceId: 'uncaught',
      handlers: [Handler()],
      publicEgress: Egress(),
    ),
  ],
  loggingPipelines: [
    ZukeLoggingPipelineRegistration(
      sourceId: 'request',
      processors: [Processor()],
      sink: Sink(),
    ),
  ],
);

@ImplementsRequirement([])
class EmptyRequirement {}

@ProvidesControl([])
class EmptyControl {}

@ImplementsRequirement(['RULE-UNSUPPORTED'])
enum UnsupportedEnum { value }

@PresentsRequirement(['RULE-UNSUPPORTED-FIELD'])
final unsupportedField = Object();

@VerifiesRequirement(['RULE-UNSUPPORTED-CLASS'])
class UnsupportedVerification {}
''');

      final output = await DartExtractor().extract(
        root.path,
        roots: ['lib'],
        target: 'backend',
      );

      expect(output.inputDigest, hasLength(64));
      expect(
        output.symbols.map((symbol) => symbol.kind),
        containsAll([
          'requirementBoundary',
          'presentationBoundary',
          'verificationBoundary',
          'controlProvider',
          'binding',
        ]),
      );
      expect(
        output.symbols
            .where((symbol) => symbol.kind == 'controlProvider')
            .expand((symbol) => symbol.controlIds),
        containsAll([
          'CTRL-FUNCTION',
          'CTRL-MIDDLEWARE',
          'CTRL-HANDLER',
          'CTRL-PROCESSOR',
        ]),
      );
      final targetedOutput = await DartExtractor().extract(
        root.path,
        roots: ['lib'],
        target: 'flutter',
      );
      expect(
        targetedOutput.symbols
            .where((symbol) => symbol.kind == 'controlProvider')
            .every((symbol) => symbol.target == 'flutter'),
        isTrue,
      );
      expect(output.graph, isNotNull);
      expect(
        output.graph!.nodes.map((node) => node.id),
        containsAll([
          'ingress:endpoint.test',
          'route:endpoint.test',
          'provider:Middleware',
          'implementation:Controller',
          'failure:uncaught',
          'provider:Handler',
          'sensitive:request',
          'provider:Processor',
          'sink:Sink',
        ]),
      );
      // Runtime registrations are authoritative for applications using
      // ZukeHttpApplication. Annotation-only declarations that are not part
      // of that runtime graph must not become isolated implementation or
      // provider paths and create false dominance failures.
      expect(
        output.graph!.nodes.map((node) => node.id),
        isNot(
          contains(
            'implementation:package:dart_extractor_behavior_fixture/app.dart#RequirementMixin',
          ),
        ),
      );
      expect(
        output.graph!.nodes.map((node) => node.id),
        isNot(
          contains(
            'provider:package:dart_extractor_behavior_fixture/app.dart#provideControl',
          ),
        ),
      );
      expect(
        output.diagnostics.map((diagnostic) => diagnostic.message),
        containsAll([
          contains('must be a non-empty constant list'),
          contains('requires constant control IDs'),
          contains('requires a constant binding ID'),
          contains('is not supported on enum declarations'),
          contains('is not supported on topLevelVariable declarations'),
          contains('is not supported on class declarations'),
        ]),
      );
    },
    // The analyzer loads a workspace package configuration. Under coverage on
    // the slower hosted runners that can legitimately take longer than the
    // default per-test timeout.
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('rejects invalid package roots and reports analyzer errors', () async {
    final root = Directory.systemTemp.createTempSync('dart-extractor-invalid-');
    addTearDown(() => deleteTemporaryDirectory(root));

    expect(
      () => DartExtractor().extract(root.path, target: 'backend'),
      throwsA(isA<FormatException>()),
    );

    File('${root.path}/pubspec.yaml').writeAsStringSync('environment: {}\n');
    expect(
      () => DartExtractor().extract(root.path, target: 'backend'),
      throwsA(isA<FormatException>()),
    );

    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: invalid_extractor_fixture
environment:
  sdk: '>=3.10.0 <4.0.0'
''');
    Directory('${root.path}/lib').createSync();
    File(
      '${root.path}/lib/broken.dart',
    ).writeAsStringSync('void broken( => missing;');
    final output = await DartExtractor().extract(
      root.path,
      roots: ['lib'],
      target: 'backend',
    );
    expect(output.diagnostics, isNotEmpty);
    expect(output.graph, isNull);
  });
}
