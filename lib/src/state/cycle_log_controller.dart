import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/cycle_log.dart';
import '../services/cycle_log_storage.dart';
import '../theme/strategy_palette.dart';
import 'failed_write_tracker.dart';

class CycleLogController extends ChangeNotifier {
  CycleLogController({CycleLogStorage? storage})
    : _storage = storage ?? SharedPreferencesCycleLogStorage();

  final CycleLogStorage _storage;

  final Map<String, CycleLog> _logs = <String, CycleLog>{};
  Future<void>? _bootstrapFuture;
  Future<void> _saveQueue = Future<void>.value();

  final FailedWriteTracker failedWrites = FailedWriteTracker();
  bool _ready = false;

  bool get isReady => _ready;

  List<CycleLog> get logs => List<CycleLog>.unmodifiable(_logs.values);

  CycleLog? logFor(String matchKey, int team) =>
      _logs[CycleLog.keyFor(matchKey, team)];

  Future<void> bootstrap() {
    return _bootstrapFuture ??= _bootstrap().onError<Object>((
      error,
      stackTrace,
    ) {
      _bootstrapFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _bootstrap() async {
    for (final log in await _storage.loadAll()) {
      _logs[log.key] = log;
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> appendEvent(String matchKey, int team, CycleEvent event) {
    final key = CycleLog.keyFor(matchKey, team);
    final existing = _logs[key] ?? CycleLog(matchKey: matchKey, team: team);
    final updated = existing.copyWith(
      events: <CycleEvent>[...existing.events, event],
    );
    _logs[key] = updated;
    final persist = _persist(updated);
    notifyListeners();
    return persist;
  }

  Future<void> recordEvent({
    required String matchKey,
    required int team,
    required CycleEventKind kind,
    required int offsetMs,
    required StrategyPhase phase,
  }) {
    return appendEvent(
      matchKey,
      team,
      CycleEvent(kind: kind, offsetMs: offsetMs, phase: phase),
    );
  }

  Future<void> clearLog(String matchKey, int team) {
    final key = CycleLog.keyFor(matchKey, team);
    if (_logs.remove(key) == null) return Future<void>.value();
    final done = _enqueue(() => _storage.delete(key));
    notifyListeners();
    return done;
  }

  Future<void> _persist(CycleLog log) {
    final snapshot = CycleLog.fromJson(log.toJson());
    return _enqueue(() => _storage.save(snapshot));
  }

  Future<void> _enqueue(Future<void> Function() op) {
    _saveQueue = _saveQueue
        .then((_) => op())
        .then((_) {
          if (failedWrites.recordSuccess()) notifyListeners();
        })
        .catchError((Object e) {
          debugPrint('Cycle log save failed: $e');
          failedWrites.recordFailure();
          notifyListeners();
        });
    return _saveQueue;
  }
}
