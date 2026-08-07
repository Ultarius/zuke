import 'dart:async';

import 'package:zuke_cli/zuke_cli.dart';
import 'package:test/test.dart';

void main() {
  test('debounces changes and queues only one follow-up run', () async {
    final changes = StreamController<Object?>();
    final shutdown = StreamController<Object?>();
    final scheduler = _ManualScheduler();
    final runs = <Completer<int>>[];
    final coordinator = WatchCoordinator(
      changes: changes.stream,
      shutdown: shutdown.stream,
      schedule: scheduler.schedule,
      runOnce: () {
        final run = Completer<int>();
        runs.add(run);
        return run.future;
      },
    );

    final runFuture = coordinator.run();
    await _settle();
    expect(runs, hasLength(1));
    runs.removeAt(0).complete(0);
    await _settle();

    changes.add(null);
    changes.add(null);
    changes.add(null);
    await _settle();
    expect(scheduler.pending, hasLength(1));
    scheduler.fireLatest();
    await _settle();
    expect(runs, hasLength(1));

    changes.add(null);
    await _settle();
    scheduler.fireLatest();
    changes.add(null);
    await _settle();
    scheduler.fireLatest();
    expect(runs, hasLength(1));
    runs.removeAt(0).complete(0);
    await _settle();
    expect(runs, hasLength(1));
    runs.removeAt(0).complete(0);
    await _settle();

    shutdown.add(null);
    await expectLater(runFuture, completion(0));
    await changes.close();
    await shutdown.close();
  });

  test('uses default timer schedule when schedule is omitted', () async {
    final changes = StreamController<Object?>();
    final shutdown = StreamController<Object?>();
    final coordinator = WatchCoordinator(
      changes: changes.stream,
      shutdown: shutdown.stream,
      debounce: const Duration(milliseconds: 1),
      runOnce: () async => 0,
    );

    final runFuture = coordinator.run();
    await _settle();
    changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    shutdown.add(null);
    await expectLater(runFuture, completion(0));
    await changes.close();
    await shutdown.close();
  });
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final class _ManualScheduler {
  final List<_ManualTimer> pending = [];

  WatchTimer schedule(Duration _, void Function() callback) {
    late final _ManualTimer timer;
    timer = _ManualTimer(callback, () => pending.remove(timer));
    pending.add(timer);
    return timer;
  }

  void fireLatest() {
    final timer = pending.last;
    pending.remove(timer);
    timer.fire();
  }
}

final class _ManualTimer implements WatchTimer {
  _ManualTimer(this.callback, this._onCancel);
  final void Function() callback;
  final void Function() _onCancel;
  var _cancelled = false;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }

  void fire() {
    if (!_cancelled) callback();
  }
}
