import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../state/failed_write_tracker.dart';
import '../models/scout_shift_schedule.dart';
import '../services/scout_shift_sync_service.dart';

class ScoutShiftController extends ChangeNotifier {
  ScoutShiftController({required this.syncService});

  final ScoutShiftSyncService syncService;

  Future<void> _saveQueue = Future<void>.value();

  final FailedWriteTracker failedWrites = FailedWriteTracker();

  StreamSubscription<ScoutShiftSchedule?>? _sub;

  String _eventKey = '';
  ScoutShiftSchedule? _schedule;
  bool _loading = false;
  Object? _error;

  String get eventKey => _eventKey;

  ScoutShiftSchedule? get schedule => _schedule;
  bool get loading => _loading;
  Object? get error => _error;

  Future<void> watchEvent(String eventKey) async {
    final trimmed = eventKey.trim();
    if (trimmed == _eventKey && _sub != null) return;

    await _saveQueue;

    _eventKey = trimmed;
    _schedule = null;
    _loading = trimmed.isNotEmpty;
    _error = null;
    notifyListeners();

    await _sub?.cancel();
    _sub = syncService.scheduleStream.listen(
      (schedule) {
        _schedule = schedule;
        _loading = false;
        notifyListeners();
      },
      onError: (Object error) {
        _loading = false;
        _error = error;
        notifyListeners();
      },
    );
    await syncService.watch(trimmed);
  }

  Future<void> generate({
    required int matchCount,
    required List<ScoutShiftRosterEntry> roster,
  }) {
    if (_eventKey.isEmpty) return Future<void>.value();

    final authorUid = syncService.currentUserUid ?? '';
    final authorDisplayName = syncService.currentUserDisplayName ?? '';
    final generated = ScoutShiftSchedule.generate(
      eventKey: _eventKey,
      matchCount: matchCount,
      roster: roster,
      authorUid: authorUid,
      authorDisplayName: authorDisplayName,
    );
    _schedule = generated;
    notifyListeners();

    if (authorUid.isEmpty) return Future<void>.value();

    final snapshot = ScoutShiftSchedule.fromJson(generated.toJson());
    return _enqueue(() => syncService.push(snapshot));
  }

  Future<void> editCell({
    required int col,
    required int match,
    required String text,
    required ScheduleCellColor? color,
  }) {
    final current = _schedule;
    if (current == null) return Future<void>.value();
    final updated = current.withCellEdit(
      col: col,
      match: match,
      text: text,
      color: color,
    );
    return _apply(updated);
  }

  Future<void> renameColumn(int col, String name, {String? uid}) {
    final current = _schedule;
    if (current == null) return Future<void>.value();
    return _apply(current.withRenamedColumn(col, name, uid: uid));
  }

  Future<void> _apply(ScoutShiftSchedule updated) {
    _schedule = updated;
    notifyListeners();

    final authorUid = syncService.currentUserUid ?? '';
    if (authorUid.isEmpty) return Future<void>.value();

    final snapshot = ScoutShiftSchedule.fromJson(updated.toJson());
    return _enqueue(() => syncService.push(snapshot));
  }

  Future<void> _enqueue(Future<void> Function() op) {
    _saveQueue = _saveQueue
        .then((_) => op())
        .then((_) {
          if (failedWrites.recordSuccess()) notifyListeners();
        })
        .catchError((Object error) {
          debugPrint('Scout shift save failed: $error');
          failedWrites.recordFailure();
          notifyListeners();
        });
    return _saveQueue;
  }

  @override
  void dispose() {
    _sub?.cancel();
    syncService.dispose();
    super.dispose();
  }
}
