import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'helpers/eligible_workspace.dart';
import '../lib/src/openapi_contract.dart';
import 'support/temporary_directory.dart';

void main() {
  test('normalizes the OpenAPI root path without dropping the slash', () async {
    final root = Directory.systemTemp.createTempSync('zuke-openapi-');
    addTearDown(() => deleteTemporaryDirectory(root));
    await createEligibleWorkspace(root);
    final document = File('${root.path}/openapi.yaml')
      ..writeAsStringSync('''
openapi: 3.0.0
info: {title: test, version: 1.0.0}
paths:
  /: 
    get: {}
''');

    final report = await const OpenApiContractVerifier().verify(
      root: root,
      openApi: document,
    );

    expect(report.openapiOperations, contains('GET /'));
    expect(report.openapiOperations, isNot(contains('GET ')));
    expect(report.toJson()['schemaAndAuthorizationChecked'], isFalse);
  });

  test('verifies resolved WebSocket handshakes and rejects contract drift', () async {
    final root = Directory.systemTemp.createTempSync('zuke-openapi-ws-');
    addTearDown(() => deleteTemporaryDirectory(root));
    await createEligibleWorkspace(root);
    final config = File('${root.path}/zuke.yaml');
    config.writeAsStringSync(
      config
          .readAsStringSync()
          .replaceFirst('framework: dart', 'framework: dart-frog')
          .replaceFirst('roots: [lib]', 'roots: [routes]'),
    );

    // Analyzer fixture for the public API identity. Runtime upgrade behavior
    // belongs to dart_frog_web_socket; this tests Zuke's resolved-symbol contract.
    final api = Directory('${root.path}/fixture_socket/lib')
      ..createSync(recursive: true);
    File('${api.path}/dart_frog_web_socket.dart').writeAsStringSync('''
Object webSocketHandler(Object callback) => Object();
''');
    final packageFile = File('${root.path}/.dart_tool/package_config.json');
    final packages =
        jsonDecode(packageFile.readAsStringSync()) as Map<String, dynamic>;
    (packages['packages'] as List).add({
      'name': 'dart_frog_web_socket',
      'rootUri': api.parent.uri.toString(),
      'packageUri': 'lib/',
      'languageVersion': '3.10',
    });
    packageFile.writeAsStringSync(jsonEncode(packages));
    void route(String name, String source) {
      File('${root.path}/routes/$name.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(source);
    }

    route('_middleware', 'Object middleware(Object handler) => handler;');
    route('socket/index', '''
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart' as ws;
Object get onRequest => ws.webSocketHandler(() {});
''');
    route('v1/socket/index', '''
import '../../socket/index.dart' as socket;
Object get onRequest => socket.onRequest;
''');
    route('stream/index', '''
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart';
final onRequest = webSocketHandler(() {});
''');
    route('ordinary/index', '''
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart';
Object unused() => webSocketHandler(() {});
Object onRequest(Object request) => Object();
''');
    final document = File('${root.path}/openapi.yaml');
    Future<OpenApiContractReport> verify(String paths) {
      document.writeAsStringSync('openapi: 3.1.0\npaths:\n$paths');
      return const OpenApiContractVerifier().verify(
        root: root,
        openApi: document,
        targetId: 'backend',
      );
    }

    const aliases =
        '  /v1/socket:\n    get: {}\n  /ordinary:\n    get: {}\n  /stream:\n    get: {}\n';
    final aligned = await verify('  /socket:\n    get: {}\n$aliases');
    expect(aligned.passed, isFalse, reason: 'Unknown HTTP methods fail closed');
    expect(aligned.topologyOperations, {
      'GET /socket',
      'GET /v1/socket',
      'GET /stream',
    });
    expect(aligned.unknownMethodTopology, {'/ordinary'});
    expect(aligned.toJson()['methodCompleteness'], isFalse);

    final wrongMethod = await verify('  /socket:\n    post: {}\n$aliases');
    expect(wrongMethod.passed, isFalse);
    expect(wrongMethod.missing, {'POST /socket'});
    expect(wrongMethod.extra, {'GET /socket'});

    final undocumented = await verify(aliases);
    expect(undocumented.passed, isFalse);
    expect(undocumented.extra, {'GET /socket'});
    final stale = await verify(
      '  /socket:\n    get: {}\n  /removed:\n    get: {}\n$aliases',
    );
    expect(stale.passed, isFalse);
    expect(stale.missing, {'GET /removed'});
    File('${root.path}/routes/ordinary/index.dart').deleteSync();
    final complete = await verify(
      '  /socket:\n    get: {}\n${aliases.replaceFirst('  /ordinary:\n    get: {}\n', '')}',
    );
    expect(complete.passed, isTrue);
    expect(complete.toJson()['methodCompleteness'], isTrue);
  });
}
