/// Supported application-facing optional runtime events and flags API.
library;

export 'package:zuke_annotations/zuke_annotations.dart';
export 'runner.dart';

/// Immutable runtime event emitted by a scenario.
class ZukeEvent {
  /// Stable event identifier.
  final String id;

  /// Governing rule identifier.
  final String ruleId;

  /// Structured event payload.
  final Map<String, Object?> payload;

  /// Creates a runtime event.
  const ZukeEvent({
    required this.id,
    required this.ruleId,
    this.payload = const {},
  });
}

/// In-memory event bus for one test execution.
class ZukeEventBus {
  final List<ZukeEvent> _events = [];

  /// Events emitted so far, in emission order.
  List<ZukeEvent> get events => List.unmodifiable(_events);

  /// Emits [event].
  void emit(ZukeEvent event) => _events.add(event);

  /// Removes all recorded events.
  void clear() => _events.clear();
}

/// Mutable feature-flag view used by a scenario runtime.
class ZukeFeatureFlags {
  final Map<String, bool> _values;

  /// Creates a flag view with optional initial [values].
  ZukeFeatureFlags([Map<String, bool>? values]) : _values = {...?values};

  /// Returns whether the flag [id] is enabled.
  bool isEnabled(String id) => _values[id] ?? false;

  /// Sets the enabled state of [id].
  void set(String id, bool enabled) => _values[id] = enabled;
}
