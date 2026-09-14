import 'package:web_socket_channel/web_socket_channel.dart';

import 'websocket_scenario.dart';

/// Adapts a browser or VM `web_socket_channel` connection to the portable
/// scenario driver. The channel implementation remains platform-owned.
WebSocketScenarioTransport channelWebSocketScenarioTransport(
  WebSocketChannel channel,
) => CallbackWebSocketScenarioTransport(
  messages: channel.stream.cast<Object?>(),
  send: channel.sink.add,
  close: ({code, reason}) => channel.sink.close(code, reason),
);
