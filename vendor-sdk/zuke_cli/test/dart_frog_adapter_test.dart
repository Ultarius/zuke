import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_cli/src/dart_frog_adapter.dart';
import 'package:zuke_core/zuke_core.dart';

void main() {
  test(
    'extracts route topology and reverses resolved middleware chains',
    () async {
      final root = await Directory.systemTemp.createTemp('zuke-dart-frog-');
      addTearDown(() => root.delete(recursive: true));
      final routes = Directory('${root.path}/routes')
        ..createSync(recursive: true);
      File('${routes.path}/_middleware.dart').writeAsStringSync('''
typedef Handler = Object Function(Object);
Handler dependencies() => (_) => Object();
Handler authGuard() => (_) => Object();
Handler requestLogging() => (_) => Object();
Handler middleware(Handler handler) => handler
  // .use(fakeComment())
  .use(dependencies())
  .use(authGuard())
  .use(requestLogging());
const decoy = '.use(notMiddleware())';
''');
      File(
        '${routes.path}/index.dart',
      ).writeAsStringSync('Object onRequest(Object request) => Object();');

      final output = await const DartFrogAdapter().extract(
        AdapterRequest(
          workspaceRoot: root.path,
          targetId: 'backend',
          packageId: 'backend',
          packageRoot: root.path,
          configuredRoots: ['lib', 'routes'],
        ),
      );

      expect(
        output.completeness.routeRegistration,
        CompletenessStatus.complete,
      );
      final middleware = output.nodes
          .where((node) => node.kind == 'middleware')
          .toList();
      expect(middleware.map((node) => node.name), [
        'requestLogging',
        'authGuard',
        'dependencies',
      ]);
      expect(
        output.nodes.map((node) => node.id).toSet(),
        hasLength(output.nodes.length),
      );
    },
  );

  test('does not classify a shadowed websocket handler as Dart Frog', () async {
    final root = await Directory.systemTemp.createTemp('zuke-dart-frog-');
    addTearDown(() => root.delete(recursive: true));
    final routes = Directory('${root.path}/routes')
      ..createSync(recursive: true);
    File(
      '${routes.path}/_middleware.dart',
    ).writeAsStringSync('Object middleware(Object handler) => handler;');
    final game = Directory('${routes.path}/game')..createSync();
    File('${game.path}/index.dart').writeAsStringSync('''
Object webSocketHandler(Object callback) => Object();
final handler = webSocketHandler(() {});
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

    expect(output.nodes.any((node) => node.kind == 'websocket-route'), isFalse);
    expect(
      output.nodes.any(
        (node) => node.attributes['transport'] == 'indeterminate',
      ),
      isTrue,
    );
    expect(
      output.diagnostics.map((diagnostic) => diagnostic.code),
      contains('ZK-DART-FROG-WS-002'),
    );
  });

  test('links a resolved RequestContext.read type to the route', () async {
    final root = await Directory.systemTemp.createTemp('zuke-dart-frog-');
    addTearDown(() => root.delete(recursive: true));
    final routes = Directory('${root.path}/routes')
      ..createSync(recursive: true);
    File('${routes.path}/_middleware.dart').writeAsStringSync('''
typedef Handler = Object Function(Object);
Handler middleware(Handler handler) => handler;
''');
    File('${routes.path}/index.dart').writeAsStringSync('''
class RequestContext {
  T read<T>() => throw UnimplementedError();
}

class CreateLobbyUseCase {}

final context = RequestContext();

Object onRequest(Object request) {
  context.read<CreateLobbyUseCase>();
  return Object();
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

    final route = output.nodes.singleWhere((node) => node.kind == 'route');
    expect(
      route.attributes['implementationTypes'],
      contains('CreateLobbyUseCase'),
    );
    expect(route.attributes['transportResolved'], isTrue);
  });
}
