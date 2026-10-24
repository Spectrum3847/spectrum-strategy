import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/match_brief.dart';
import '../services/match_brief_storage.dart';
import '../services/match_brief_sync_service.dart';
import 'failed_write_tracker.dart';

class MatchBriefController extends ChangeNotifier {
  MatchBriefController({MatchBriefStorage? storage, this._syncService})
    : _storage = storage ?? SharedPreferencesMatchBriefStorage();

  final MatchBriefStorage _storage;
  final MatchBriefSyncService? _syncService;

  Future<void>? _bootstrapFuture;
  Future<void> _saveQueue = Future<void>.value();
  final List<MatchBrief> _briefs = <MatchBrief>[];

  final Map<String, MatchBrief> _confirmed = <String, MatchBrief>{};

  final Set<String> _unsyncedIds = <String>{};

  final Set<String> _rejectedIds = <String>{};

  bool _repushInFlight = false;
  bool _repushPending = false;

  final FailedWriteTracker failedWrites = FailedWriteTracker();

  bool _ready = false;
  StreamSubscription<List<MatchBrief>>? _remoteSubscription;
  StreamSubscription<MatchBriefSyncStatus>? _statusSubscription;
  MatchBriefSyncStatus _syncStatus = const MatchBriefSyncStatus(
    state: MatchBriefSyncState.signedOut,
  );

  bool get isReady => _ready;
  List<MatchBrief> get briefs => List<MatchBrief>.unmodifiable(_briefs);
  MatchBriefSyncStatus get syncStatus => _syncStatus;

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
    final loaded = await _storage.loadAll();
    _briefs
      ..clear()
      ..addAll(loaded);
    for (final brief in loaded) {
      _confirmed[brief.id] = brief;
    }
    _unsyncedIds
      ..clear()
      ..addAll(await _storage.loadPendingIds());
    _ready = true;
    notifyListeners();

    final sync = _syncService;
    if (sync == null) return;
    _statusSubscription = sync.statusStream.listen((status) {
      final previous = _syncStatus.state;
      _syncStatus = status;
      notifyListeners();

      if (!_repushInFlight &&
          status.state == MatchBriefSyncState.synced &&
          previous != MatchBriefSyncState.synced) {
        unawaited(_repushUnsynced());
      }
    });
    _remoteSubscription = sync.remoteBriefsStream.listen(_mergeRemote);
    _syncStatus = sync.status;
    try {
      await sync.initialize();
    } catch (_) {
      // Intentionally empty.
    }
    if (_syncStatus.state == MatchBriefSyncState.synced) {
      unawaited(_repushUnsynced());
    }
    notifyListeners();
  }

  MatchBrief briefFor(String eventKey, String matchId) {
    final id = MatchBrief.idFor(eventKey, matchId);
    return _briefs.firstWhere(
      (b) => b.id == id,
      orElse: () => MatchBrief(
        id: id,
        eventKey: eventKey,
        matchId: matchId,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
    );
  }

  Future<bool> save({
    required String eventKey,
    required String matchId,
    Map<int, String>? robotPlans,
    String? keyPoints,
    bool? ready,
  }) async {
    final id = MatchBrief.idFor(eventKey, matchId);
    final updated = briefFor(eventKey, matchId).copyWith(
      robotPlans: robotPlans,
      keyPoints: keyPoints,
      ready: ready,
      authorUid: _syncService?.currentUserUid ?? '',
      authorDisplayName: _syncService?.currentUserDisplayName ?? '',
      updatedAt: DateTime.now().toUtc(),
    );
    _put(updated);
    notifyListeners();

    final snapshot = MatchBrief.fromJson(updated.toJson());
    if (!await _enqueueSave(snapshot)) {
      if (identical(_briefs.where((b) => b.id == id).firstOrNull, updated)) {
        final confirmed = _confirmed[id];
        if (confirmed == null) {
          _briefs.removeWhere((b) => b.id == id);
        } else {
          _put(confirmed);
        }
      }
      notifyListeners();
      return false;
    }

    final sync = _syncService;
    if (sync != null) {
      _unsyncedIds.add(id);
      _persistPendingIds();
      unawaited(sync.push(snapshot));
    }
    return true;
  }

  void _put(MatchBrief brief) {
    final index = _briefs.indexWhere((b) => b.id == brief.id);
    if (index >= 0) {
      _briefs[index] = brief;
    } else {
      _briefs.add(brief);
    }
  }

  void _mergeRemote(List<MatchBrief> remote) {
    var changed = false;
    var pendingChanged = false;
    for (final incoming in remote) {
      final existing = _briefs.where((b) => b.id == incoming.id).firstOrNull;

      if (existing == null ||
          !incoming.updatedAt.isBefore(existing.updatedAt)) {
        if (_unsyncedIds.remove(incoming.id)) pendingChanged = true;
        _rejectedIds.remove(incoming.id);
      }
      if (existing == null || incoming.updatedAt.isAfter(existing.updatedAt)) {
        _put(incoming);
        unawaited(_enqueueSave(incoming));
        changed = true;
      }
    }
    if (pendingChanged) _persistPendingIds();
    if (changed) notifyListeners();
  }

  void _persistPendingIds() {
    final snapshot = _unsyncedIds.toSet();
    _saveQueue = _saveQueue
        .then((_) => _storage.savePendingIds(snapshot))
        .catchError(
          (Object e) => debugPrint('Match brief pending id save failed: $e'),
        );
  }

  Future<bool> _enqueueSave(MatchBrief brief) {
    final result = _saveQueue
        .then((_) => _storage.saveBrief(brief))
        .then(
          (_) {
            _confirmed[brief.id] = brief;
            if (failedWrites.recordSuccess()) notifyListeners();
            return true;
          },
          onError: (Object e) {
            debugPrint('Match brief save failed: $e');
            failedWrites.recordFailure();
            notifyListeners();
            return false;
          },
        );
    _saveQueue = result;
    return result;
  }

  Future<void> _repushUnsynced() async {
    if (_repushInFlight) {
      _repushPending = true;
      return;
    }
    _repushInFlight = true;
    try {
      do {
        _repushPending = false;
        final sync = _syncService;
        if (sync == null) return;
        final targetIds = _unsyncedIds.difference(_rejectedIds);
        if (targetIds.isEmpty) continue;

        await _saveQueue;
        for (final id in targetIds) {
          final brief = _briefs.where((b) => b.id == id).firstOrNull;
          if (brief == null) {
            if (_unsyncedIds.remove(id)) _persistPendingIds();
            continue;
          }
          await sync.push(MatchBrief.fromJson(brief.toJson()));

          if (sync.status.state == MatchBriefSyncState.synced) {
            _unsyncedIds.remove(id);
            _rejectedIds.remove(id);
            _persistPendingIds();
          } else if (sync.status.state == MatchBriefSyncState.rejected) {
            _rejectedIds.add(id);
          }
        }
      } while (_repushPending);
    } finally {
      _repushInFlight = false;
    }
  }

  @override
  void dispose() {
    _remoteSubscription?.cancel();
    _statusSubscription?.cancel();
    _syncService?.dispose();
    super.dispose();
  }
}
