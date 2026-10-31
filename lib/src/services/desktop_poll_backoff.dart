import 'dart:async';

Duration pollDelayFor(Duration pollInterval, int consecutiveFailures) {
  if (consecutiveFailures <= 0) return pollInterval;
  final multiplier = 1 << (consecutiveFailures - 1).clamp(0, 4);
  return pollInterval * multiplier;
}

class DesktopPollScheduler {
  DesktopPollScheduler(this.pollInterval);

  final Duration pollInterval;

  int _consecutiveFailures = 0;
  Timer? _timer;

  int _generation = 0;

  Duration get currentDelay => pollDelayFor(pollInterval, _consecutiveFailures);

  void start(FutureOr<void> Function() tick) {
    cancel();
    _scheduleNext(tick);
  }

  void _scheduleNext(FutureOr<void> Function() tick) {
    final generation = _generation;
    _timer = Timer(currentDelay, () async {
      await tick();
      if (generation == _generation) _scheduleNext(tick);
    });
  }

  void onSuccess() => _consecutiveFailures = 0;

  void onFailure() => _consecutiveFailures++;

  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }
}
