import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/dart_frog_adapter.dart';
import 'package:zuke_core/zuke_core.dart';

import 'support/temporary_directory.dart';

void main() {
  test('extracts resolved method guards and exact forwarding aliases only', () async {
    final root = Directory.systemTemp.createTempSync('zuke-http-methods-');
    addTearDown(() => deleteTemporaryDirectory(root));
    // Minimal semantic fixture: the URI and symbols model Dart Frog's API.
    final api = Directory('${root.path}/api/lib')..createSync(recursive: true);
    File('${api.path}/dart_frog.dart').writeAsStringSync('''
enum HttpMethod { get, post, head }
class Request { HttpMethod get method => HttpMethod.get; }
class RequestContext { Request get request => Request(); }
class Response { Response({int statusCode = 200}); }
''');
    File('${root.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'dart_frog',
              'rootUri': api.parent.uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.10',
            },
          ],
        }),
      );
    void route(String name, String body, {String imports = ''}) {
      File('${root.path}/routes/$name.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "import 'package:dart_frog/dart_frog.dart';\nimport 'dart:io';\n$imports\n$body",
        );
    }

    route('_middleware', 'Object middleware(Object handler) => handler;');
    route('get/index', '''
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  return Response();
}
''');
    route('post/index', '''
Response onRequest(RequestContext context) {
  if (HttpMethod.post != context.request.method) return Response(statusCode: 405);
  return Response();
}
''');
    route('multi/index', '''
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get && context.request.method != HttpMethod.head) {
    return Response(statusCode: 405);
  }
  return Response();
}
''');
    route('v1/get/index', '''
Response onRequest(RequestContext context) => original.onRequest(context);
''', imports: "import '../../get/index.dart' as original;");
    route('v2/get/index', '''
Response onRequest(RequestContext context) { return original.onRequest(context); }
''', imports: "import '../../v1/get/index.dart' as original;");
    route('wrong_context/index', '''
Response onRequest(RequestContext context) => original.onRequest(RequestContext());
''', imports: "import '../get/index.dart' as original;");
    route('unused/index', '''
Response unused(RequestContext context) {
  if (context.request.method != HttpMethod.get) return Response(statusCode: 405);
  return Response();
}
Response onRequest(RequestContext context) => Response();
''');
    route('not_rejected/index', '''
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) { Response(statusCode: 405); }
  return Response();
}
''');
    route('wrong_status/index', '''
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) return Response(statusCode: 200);
  return Response();
}
''');
    route('early_return/index', '''
Response onRequest(RequestContext context) {
  if (DateTime.now().second == 1) return Response();
  if (context.request.method != HttpMethod.get) return Response(statusCode: 405);
  return Response();
}
''');
    route(
      'cycle_a/index',
      'Response onRequest(RequestContext context) => other.onRequest(context);',
      imports: "import '../cycle_b/index.dart' as other;",
    );
    route(
      'cycle_b/index',
      'Response onRequest(RequestContext context) => other.onRequest(context);',
      imports: "import '../cycle_a/index.dart' as other;",
    );
    route('shadow/index', '''
enum HttpMethod { get }
class Request { HttpMethod get method => HttpMethod.get; }
class RequestContext { Request get request => Request(); }
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) return Response(statusCode: 405);
  return Response();
}
''');
    final output = await const DartFrogAdapter().extract(
      AdapterRequest(
        workspaceRoot: root.path,
        targetId: 'backend',
        packageId: 'backend',
        packageRoot: root.path,
        configuredRoots: ['routes'],
      ),
    );
    final methods = {
      for (final node in output.nodes.where((node) => node.kind == 'route'))
        node.attributes['route']: node.attributes['methods'],
    };
    expect(methods['/get'], ['GET']);
    expect(methods['/post'], ['POST']);
    expect(methods['/multi'], ['GET', 'HEAD']);
    expect(methods['/v1/get'], ['GET']);
    expect(methods['/v2/get'], ['GET']);
    for (final unknown in [
      'wrong_context',
      'unused',
      'not_rejected',
      'wrong_status',
      'early_return',
      'cycle_a',
      'cycle_b',
      'shadow',
    ]) {
      expect(methods.containsKey('/$unknown'), isTrue);
      expect(methods['/$unknown'], isNull, reason: unknown);
    }
  });
}
