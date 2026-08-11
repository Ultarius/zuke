import 'dart:io';

import 'package:adapter_sdk/adapter_sdk.dart';
import 'package:test/test.dart';
import 'package:zuke_adapter_dart_frog/zuke_adapter_dart_frog.dart';

void main() {
  test('extracts routes, websocket boundaries, and incoming middleware order', () async {
    final root = await Directory.systemTemp.createTemp('zuke-dart-frog-');
    addTearDown(() => root.delete(recursive: true));
    final routes = Directory('${root.path}/routes')..createSync(recursive: true);
    File('${routes.path}/_middleware.dart').writeAsStringSync('''
Handler middleware(Handler handler) => handler
  .use(dependencies())
  .use(authGuard())
  .use(requestLogging());
''');
    File('${routes.path}/index.dart').writeAsStringSync('Response onRequest(Request request) => Response();');
    final game = Directory('${routes.path}/game')..createSync();
    File('${game.path}/index.dart').writeAsStringSync('webSocketHandler((channel, protocol) {});');
    final admin = Directory('${routes.path}/admin')..createSync();
    File('${admin.path}/index.dart').writeAsStringSync('Response onRequest(Request request) => Response();');

    final output = await const DartFrogAdapter().extract(
      AdapterRequest(
        workspaceRoot: root.path,
        targetId: 'backend',
        packageId: 'backend',
        packageRoot: root.path,
        configuredRoots: ['lib', 'routes'],
      ),
    );

    expect(output.completeness.routeRegistration, CompletenessStatus.complete);
    expect(output.nodes.any((node) => node.kind == 'websocket-route'), isTrue);
    final middleware = output.nodes.where((node) => node.kind == 'middleware').toList();
    expect(middleware.map((node) => node.name), ['requestLogging', 'authGuard', 'dependencies']);
    expect(
      output.nodes.map((node) => node.id).toSet(),
      hasLength(output.nodes.length),
    );
  });
}
