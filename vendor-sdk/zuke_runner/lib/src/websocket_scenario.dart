import 'dart:async';
import 'dart:collection';

/// Portable transport boundary for deterministic WebSocket scenario tests.
abstract interface class WebSocketScenarioTransport {
  Stream<Object?> get messages;
  Future<void> send(Object? message);
  Future<void> close({int? code, String? reason});
}

typedef WebSocketScenarioSend = FutureOr<void> Function(Object? message);
typedef WebSocketScenarioClose =
    FutureOr<void> Function({int? code, String? reason});

final class CallbackWebSocketScenarioTransport
    implements WebSocketScenarioTransport {
  CallbackWebSocketScenarioTransport({
    required this.messages,
    required WebSocketScenarioSend send,
    required WebSocketScenarioClose close,
  }) : _send = send,
       _close = close;

  @override
  final Stream<Object?> messages;
  final WebSocketScenarioSend _send;
  final WebSocketScenarioClose _close;

  @override
  Future<void> send(Object? message) async => _send(message);

  @override
  Future<void> close({int? code, String? reason}) async =>
      _close(code: code, reason: reason);
}

final class InMemoryWebSocketScenarioTransport
    implements WebSocketScenarioTransport {
  InMemoryWebSocketScenarioTransport._()
    : _incoming = StreamController<Object?>.broadcast(sync: true) {
    _incoming.onListen = _flushPending;
  }

  final StreamController<Object?> _incoming;
  final List<Object?> _pending = [];
  InMemoryWebSocketScenarioTransport? _peer;
  bool _closed = false;

  static (
    InMemoryWebSocketScenarioTransport,
    InMemoryWebSocketScenarioTransport,
  )
  pair() {
    final first = InMemoryWebSocketScenarioTransport._();
    final second = InMemoryWebSocketScenarioTransport._();
    first._peer = second;
    second._peer = first;
    return (first, second);
  }

  @override
  Stream<Object?> get messages => _incoming.stream;

  @override
  Future<void> send(Object? message) async {
    if (_closed) throw const WebSocketScenarioClosed('Transport is closed.');
    final peer = _peer;
    if (peer == null || peer._closed) {
      throw const WebSocketScenarioClosed('Peer is closed.');
    }
    if (peer._incoming.hasListener) {
      peer._incoming.add(message);
    } else {
      peer._pending.add(message);
    }
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    if (_closed) return;
    _closed = true;
    await _incoming.close();
    final peer = _peer;
    if (peer != null && !peer._closed) {
      peer._closed = true;
      unawaited(peer._incoming.close());
    }
  }

  void _flushPending() {
    final pending = List<Object?>.from(_pending);
    _pending.clear();
    for (final message in pending) {
      _incoming.add(message);
    }
  }
}

class WebSocketScenarioException implements Exception {
  const WebSocketScenarioException(this.message);
  final String message;
  @override
  String toString() => 'WebSocketScenarioException: $message';
}

final class WebSocketScenarioTimeout extends WebSocketScenarioException {
  const WebSocketScenarioTimeout(Duration timeout)
    : super('No WebSocket message received within $timeout.');
}

final class WebSocketScenarioClosed extends WebSocketScenarioException {
  const WebSocketScenarioClosed(String message) : super(message);
}

final class WebSocketScenarioDriver {
  WebSocketScenarioDriver(this.transport) {
    _subscription = transport.messages.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
    );
  }

  final WebSocketScenarioTransport transport;
  late final StreamSubscription<Object?> _subscription;
  final Queue<Object?> _messages = Queue<Object?>();
  final Queue<_PendingReceive> _receives = Queue<_PendingReceive>();
  bool _disposed = false;
  bool _remoteClosed = false;
  Object? _receiveError;

  Future<void> send(Object? message) async {
    _ensureOpen();
    await transport.send(message);
  }

  Future<void> sendOrdered(Iterable<Object?> messages) async {
    for (final message in messages) {
      await send(message);
    }
  }

  Future<Object?> receiveNext({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _ensureOpen();
    if (_messages.isNotEmpty) return _messages.removeFirst();
    if (_receiveError != null) {
      throw const WebSocketScenarioException('WebSocket receive failed.');
    }
    if (_remoteClosed) {
      throw const WebSocketScenarioClosed('The peer closed the connection.');
    }
    final pending = _PendingReceive(timeout);
    _receives.add(pending);
    try {
      return await pending.future;
    } on WebSocketScenarioTimeout {
      await dispose();
      rethrow;
    }
  }

  Future<List<Object?>> receiveOrdered(
    int count, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (count < 0) throw ArgumentError.value(count, 'count');
    final result = <Object?>[];
    for (var index = 0; index < count; index++) {
      result.add(await receiveNext(timeout: timeout));
    }
    return result;
  }

  Future<void> expectOrdered(
    Iterable<Object?> expected, {
    Duration timeout = const Duration(seconds: 5),
    bool Function(Object? actual, Object? expected)? equals,
  }) async {
    final expectedList = expected.toList(growable: false);
    final actual = await receiveOrdered(expectedList.length, timeout: timeout);
    final compare = equals ?? (actual, expected) => actual == expected;
    for (var index = 0; index < expectedList.length; index++) {
      if (!compare(actual[index], expectedList[index])) {
        throw const WebSocketScenarioException('Ordered message mismatch.');
      }
    }
  }

  Future<void> close({int? code, String? reason}) =>
      dispose(code: code, reason: reason);

  Future<void> dispose({int? code, String? reason}) async {
    if (_disposed) return;
    _disposed = true;
    for (final pending in _receives.toList()) {
      pending.completeError(
        const WebSocketScenarioClosed('Driver is disposed.'),
      );
    }
    _receives.clear();
    try {
      final closeFuture = transport.close(code: code, reason: reason);
      await _subscription.cancel();
      await closeFuture;
    } finally {
      _messages.clear();
    }
  }

  void _onMessage(Object? message) {
    if (_disposed) return;
    if (_receives.isNotEmpty) {
      _receives.removeFirst().complete(message);
    } else {
      _messages.add(message);
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    _receiveError = error;
    for (final pending in _receives.toList()) {
      pending.completeError(
        const WebSocketScenarioException('WebSocket receive failed.'),
      );
    }
    _receives.clear();
  }

  void _onDone() {
    if (_disposed) return;
    _remoteClosed = true;
    for (final pending in _receives.toList()) {
      pending.completeError(
        const WebSocketScenarioClosed('The peer closed the connection.'),
      );
    }
    _receives.clear();
  }

  void _ensureOpen() {
    if (_disposed) {
      throw const WebSocketScenarioClosed('Driver is disposed.');
    }
  }
}

final class _PendingReceive {
  _PendingReceive(Duration timeout) {
    _timer = Timer(
      timeout,
      () => completeError(WebSocketScenarioTimeout(timeout)),
    );
  }
  final Completer<Object?> _completer = Completer<Object?>();
  late final Timer _timer;
  Future<Object?> get future => _completer.future;
  void complete(Object? value) {
    if (_completer.isCompleted) return;
    _timer.cancel();
    _completer.complete(value);
  }

  void completeError(Object error) {
    if (_completer.isCompleted) return;
    _timer.cancel();
    _completer.completeError(error);
  }
}

final class RecordingWebSocketScenarioSink implements StreamSink<dynamic> {
  final List<Object?> _messages = [];
  List<Object?> get messages => List<Object?>.unmodifiable(_messages);
  List<Object?> get received => messages;
  @override
  void add(dynamic message) => _messages.add(message);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await stream.forEach(add);
  }

  @override
  Future<void> close() async {}
  @override
  Future<void> get done async {}
  void clear() => _messages.clear();
}
