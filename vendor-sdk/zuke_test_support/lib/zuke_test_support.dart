/// Shared deterministic test-fixture utilities for the Zuke SDK.
library;

export 'src/temporary_directory.dart';

/// Compatibility export for repository tests. New consumer tests should use
/// package:zuke_runner directly; this package remains unpublished support.
export 'package:zuke_runner/testing.dart'
    show
        CallbackWebSocketScenarioTransport,
        InMemoryWebSocketScenarioTransport,
        RecordingWebSocketScenarioSink,
        WebSocketScenarioClosed,
        WebSocketScenarioDriver,
        WebSocketScenarioException,
        WebSocketScenarioSend,
        WebSocketScenarioClose,
        WebSocketScenarioTimeout,
        WebSocketScenarioTransport;
