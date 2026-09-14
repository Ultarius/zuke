import 'dart:io';

import 'websocket_scenario.dart';

/// Connects a VM test to a real WebSocket while preserving the portable
/// scenario-driver lifecycle and bounded receive behavior.
Future<WebSocketScenarioTransport> connectVmWebSocketScenario(
  Uri uri, {
  Map<String, dynamic>? headers,
}) async {
  final socket = await WebSocket.connect(uri.toString(), headers: headers);
  return CallbackWebSocketScenarioTransport(
    messages: socket.cast<Object?>(),
    send: socket.add,
    close: ({code, reason}) => socket.close(code, reason),
  );
}
