class InFlightLocalWrites<T extends Object> {
  final Map<String, T?> _writes = <String, T?>{};

  bool _recording = false;

  bool get isRecording => _recording;

  void beginFetch() {
    _writes.clear();
    _recording = true;
  }

  void abandonFetch() {
    _writes.clear();
    _recording = false;
  }

  void recordPush(String id, T value) {
    if (_recording) {
      _writes[id] = value;
    }
  }

  void recordDelete(String id) {
    if (_recording) {
      _writes[id] = null;
    }
  }

  Map<String, T> resolve(Map<String, T> fetched) {
    for (final entry in _writes.entries) {
      final value = entry.value;
      if (value == null) {
        fetched.remove(entry.key);
      } else {
        fetched[entry.key] = value;
      }
    }
    _writes.clear();
    _recording = false;
    return fetched;
  }
}
