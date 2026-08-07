import 'package:zuke_runner/runtime.dart';
import 'package:test/test.dart';

void main() {
  test('ZukeEventBus emits and stores events', () {
    final bus = ZukeEventBus();
    bus.emit(ZukeEvent(id: 'evt-1', ruleId: 'RULE-001'));
    expect(bus.events, hasLength(1));
    expect(bus.events.first.id, 'evt-1');
  });

  test('ZukeEventBus clear removes all events', () {
    final bus = ZukeEventBus();
    bus.emit(ZukeEvent(id: 'evt-1', ruleId: 'RULE-001'));
    bus.clear();
    expect(bus.events, isEmpty);
  });

  test('ZukeFeatureFlags defaults to disabled', () {
    final flags = ZukeFeatureFlags();
    expect(flags.isEnabled('unknown'), isFalse);
  });

  test('ZukeFeatureFlags set and check enabled', () {
    final flags = ZukeFeatureFlags();
    flags.set('FEAT-001', true);
    expect(flags.isEnabled('FEAT-001'), isTrue);
  });

  test('ZukeEvent payload defaults to empty map', () {
    final event = ZukeEvent(id: 'evt-1', ruleId: 'RULE-001');
    expect(event.payload, isEmpty);
  });
}
