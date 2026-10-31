class FailedWriteTracker {
  FailedWriteTracker({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  int _unlandedCount = 0;
  DateTime? _lastFailureAt;

  int get unlandedCount => _unlandedCount;

  DateTime? get lastFailureAt => _lastFailureAt;

  bool get hasFailures => _unlandedCount > 0;

  void recordFailure() {
    _unlandedCount++;
    _lastFailureAt = _clock();
  }

  bool recordSuccess() {
    if (_unlandedCount == 0) return false;
    _unlandedCount = 0;
    _lastFailureAt = null;
    return true;
  }
}
