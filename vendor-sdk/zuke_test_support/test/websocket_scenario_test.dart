import 'package:test/test.dart';
import 'package:zuke_test_support/zuke_test_support.dart';

void main() {
  test('in-memory transport preserves ordered messages', () async {
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

  test('receive timeout disposes the driver and rejects late sends', () async {
    final (clientTransport, _) = InMemoryWebSocketScenarioTransport.pair();
    final client = WebSocketScenarioDriver(clientTransport);

    await expectLater(
      client.receiveNext(timeout: const Duration(milliseconds: 1)),
      throwsA(isA<WebSocketScenarioTimeout>()),
    );
    await expectLater(
      client.send('late'),
      throwsA(isA<WebSocketScenarioClosed>()),
    );
    await client.dispose();
  });

  test('recording sink is deterministic and clearable', () {
    final sink = RecordingWebSocketScenarioSink();
    sink.add({'type': 'hello'});
    sink.add({'type': 'world'});
    expect(sink.messages, [
      {'type': 'hello'},
      {'type': 'world'},
    ]);
    sink.clear();
    expect(sink.messages, isEmpty);
  });
}
