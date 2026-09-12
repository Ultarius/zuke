import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zuke_runner/vm_testing.dart';

void main() {
  test('VM adapter exchanges ordered messages with a local socket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final connected = Completer<void>();
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      connected.complete();
      socket.listen((message) => socket.add('reply:$message'));
    });

    final transport = await connectVmWebSocketScenario(
      Uri.parse('ws://${server.address.host}:${server.port}'),
    );
    final driver = WebSocketScenarioDriver(transport);
    addTearDown(driver.dispose);
    await driver.send('hello');
    await connected.future.timeout(const Duration(seconds: 2));
    expect(
      await driver.receiveNext(timeout: const Duration(seconds: 2)),
      'reply:hello',
    );
  });
}
