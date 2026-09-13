class InFlightLocalWrites<T extends Object> {
  final Map<String, T?> _writes = <String, T?>{};

  final Map<String, int> _completedTokens = <String, int>{};

  final Map<String, _OutstandingWrite<T>> _outstanding =
      <String, _OutstandingWrite<T>>{};

  int _nextToken = 0;

  bool _recording = false;

  int _session = 0;

  int _fetchSession = 0;

  String? _sessionUid;
  bool _sessionUidSeen = false;

  bool get isRecording => _recording;

  void beginFetch() {
    _writes.clear();
    _completedTokens.clear();
    _recording = true;
    _fetchSession = _session;
  }

  void syncSession(String? uid) {
    if (_sessionUidSeen && uid == _sessionUid) {
      return;
    }
    _sessionUid = uid;
    _sessionUidSeen = true;
    endSession();
  }

  void endSession() {
    _session++;
    _writes.clear();
    _completedTokens.clear();
    _outstanding.clear();
    _recording = false;
  }

  void abandonFetch() {
    _writes.clear();
    _completedTokens.clear();
    _recording = false;
  }

  void recordPush(String id, T value, int token) {
    if (_recording) {
      _recordCompleted(id, token, value);
    }
  }

  void recordDelete(String id, int token) {
    if (_recording) {
      _recordCompleted(id, token, null);
    }
  }

  void _recordCompleted(String id, int token, T? value) {
    final current = _completedTokens[id];
    if (current == null || token > current) {
      _writes[id] = value;
      _completedTokens[id] = token;
    }
  }

  int beginPush(String id, T value) => _begin(id, value);

  int beginDelete(String id) => _begin(id, null);

  int _begin(String id, T? value) {
    final token = ++_nextToken;
    _outstanding[id] = _OutstandingWrite<T>(token, value);
    return token;
  }

  void endWrite(String id, int token) {
    if (_outstanding[id]?.token == token) {
      _outstanding.remove(id);
    }
  }

  bool isOpen(String id, int token) => _outstanding[id]?.token == token;

  Map<String, T>? resolve(Map<String, T> fetched) {
    final stale = _fetchSession != _session;
    if (stale) {
      _writes.clear();
      _completedTokens.clear();
      _recording = false;
      return null;
    }
    for (final entry in _outstanding.entries) {
      _apply(fetched, entry.key, entry.value.value);
    }
    for (final entry in _writes.entries) {
      _apply(fetched, entry.key, entry.value);
    }
    _writes.clear();
    _completedTokens.clear();
    _recording = false;
    return fetched;
  }

  static void _apply<T extends Object>(
    Map<String, T> into,
    String id,
    T? value,
  ) {
    if (value == null) {
      into.remove(id);
    } else {
      into[id] = value;
    }
  }
}

class _OutstandingWrite<T extends Object> {
  const _OutstandingWrite(this.token, this.value);

  final int token;
  final T? value;
}
