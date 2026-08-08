/// Supported application-facing optional runtime events and flags API.
library;

export 'package:zuke_annotations/zuke_annotations.dart';
export 'runner.dart';

class ZukeEvent {
  final String id;
  final String ruleId;
  final Map<String, Object?> payload;

  const ZukeEvent({
    required this.id,
    required this.ruleId,
    this.payload = const {},
  });
}

class ZukeEventBus {
  final List<ZukeEvent> _events = [];
  List<ZukeEvent> get events => List.unmodifiable(_events);

  void emit(ZukeEvent event) => _events.add(event);

  void clear() => _events.clear();
}

class ZukeFeatureFlags {
  final Map<String, bool> _values;

  ZukeFeatureFlags([Map<String, bool>? values]) : _values = {...?values};

  bool isEnabled(String id) => _values[id] ?? false;

  void set(String id, bool enabled) => _values[id] = enabled;
}
