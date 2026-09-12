import 'dart:async';

import 'package:test/test.dart';
import 'package:zuke_runner/zuke_runner.dart';

void main() {
  test('in-memory transport preserves ordering and supports replies', () async {
    final (clientTransport, serverTransport) =
        InMemoryWebSocketScenarioTransport.pair();
    final client = WebSocketScenarioDriver(clientTransport);
    final server = WebSocketScenarioDriver(serverTransport);
    addTearDown(client.dispose);
    addTearDown(server.dispose);

    await client.sendOrdered(['hello', 'world']);
    await server.expectOrdered(['hello', 'world']);
    await server.send('ack');
    expect(await client.receiveNext(), 'ack');
  });

  test('timeout disposes the driver and rejects late sends', () async {
    final (transport, _) = InMemoryWebSocketScenarioTransport.pair();
    final driver = WebSocketScenarioDriver(transport);

    await expectLater(
      driver.receiveNext(timeout: const Duration(milliseconds: 1)),
      throwsA(isA<WebSocketScenarioTimeout>()),
    );
    await expectLater(
      driver.send('late'),
      throwsA(isA<WebSocketScenarioClosed>()),
    );
    await driver.dispose();
  });

  test('callback transport converts errors without leaking payloads', () async {
    final controller = StreamController<Object?>();
    final transport = CallbackWebSocketScenarioTransport(
      messages: controller.stream,
      send: (_) {},
      close: ({code, reason}) => controller.close(),
    );
    final driver = WebSocketScenarioDriver(transport);
    addTearDown(driver.dispose);
    final pending = driver.receiveNext();
    controller.addError(StateError('private payload'));
    await expectLater(
      pending,
      throwsA(
        predicate(
          (Object error) =>
              error is WebSocketScenarioException &&
              !error.toString().contains('private payload'),
        ),
      ),
    );
  });
}
