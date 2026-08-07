import 'dart:async';

abstract interface class WatchTimer {
  void cancel();
}

typedef WatchSchedule =
    WatchTimer Function(Duration delay, void Function() callback);

final class WatchCoordinator {
  WatchCoordinator({
    required this.changes,
    required this.shutdown,
    required this.runOnce,
    WatchSchedule? schedule,
    this.debounce = const Duration(milliseconds: 250),
  }) : _schedule = schedule ?? _defaultSchedule;

  final Stream<Object?> changes;
  final Stream<Object?> shutdown;
  final Future<int> Function() runOnce;
  final WatchSchedule _schedule;
  final Duration debounce;

  Future<int> run() async {
    var exitCode = 0;
    var running = false;
    var queued = false;
    var stopping = false;
    WatchTimer? timer;
    final done = Completer<void>();

    Future<void> execute() async {
      if (running) {
        queued = true;
        return;
      }
      running = true;
      do {
        queued = false;
        exitCode = await runOnce();
      } while (queued && !stopping);
      running = false;
      if (stopping && !done.isCompleted) done.complete();
    }

    void scheduleRun() {
      timer?.cancel();
      timer = _schedule(debounce, () {
        if (!stopping) unawaited(execute());
      });
    }

    final changesSubscription = changes.listen((_) => scheduleRun());
    final shutdownSubscription = shutdown.listen((_) {
      stopping = true;
      timer?.cancel();
      if (!running && !done.isCompleted) done.complete();
    });
    await execute();
    await done.future;
    timer?.cancel();
    await changesSubscription.cancel();
    await shutdownSubscription.cancel();
    return exitCode;
  }
}

WatchTimer _defaultSchedule(Duration delay, void Function() callback) =>
    _TimerAdapter(Timer(delay, callback));

final class _TimerAdapter implements WatchTimer {
  _TimerAdapter(this._timer);
  final Timer _timer;
  @override
  void cancel() => _timer.cancel();
}
