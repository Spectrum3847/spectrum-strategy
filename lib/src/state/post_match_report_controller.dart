import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/post_match_report.dart';
import '../services/analytics_service.dart';
import '../services/post_match_report_storage.dart';
import '../services/post_match_report_sync_service.dart';
import 'failed_write_tracker.dart';

class PostMatchReportController extends ChangeNotifier {
  PostMatchReportController({
    PostMatchReportStorage? storage,
    this._syncService,
    AnalyticsService? analytics,
  }) : _storage = storage ?? SharedPreferencesPostMatchReportStorage(),
       _analytics = analytics ?? const NoopAnalyticsService();

  final PostMatchReportStorage _storage;
  final PostMatchReportSyncService? _syncService;
  final AnalyticsService _analytics;

  Future<void>? _bootstrapFuture;
  Future<void> _saveQueue = Future<void>.value();
  final List<PostMatchReport> _reports = <PostMatchReport>[];

  final Map<String, int> _mutations = <String, int>{};

  final Map<String, PostMatchReport> _confirmed = <String, PostMatchReport>{};

  final Set<String> _unsyncedReportIds = <String>{};

  final Set<String> _rejectedIds = <String>{};

  bool _repushInFlight = false;
  bool _repushPending = false;

  final FailedWriteTracker failedWrites = FailedWriteTracker();

  bool _ready = false;
  StreamSubscription<List<PostMatchReport>>? _remoteSubscription;
  StreamSubscription<PostMatchReportSyncStatus>? _statusSubscription;
  PostMatchReportSyncStatus _syncStatus = const PostMatchReportSyncStatus(
    state: PostMatchReportSyncState.signedOut,
  );

  bool get isReady => _ready;
  List<PostMatchReport> get reports =>
      List<PostMatchReport>.unmodifiable(_reports);

  PostMatchReportSyncStatus get syncStatus => _syncStatus;

  String? get currentUserUid => _syncService?.currentUserUid;

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
    _reports
      ..clear()
      ..addAll(loaded);

    _unsyncedReportIds
      ..clear()
      ..addAll(await _storage.loadPendingIds());
    _ready = true;
    notifyListeners();

    final sync = _syncService;
    if (sync != null) {
      _statusSubscription = sync.statusStream.listen((status) {
        final previousState = _syncStatus.state;
        _syncStatus = status;
        notifyListeners();

        if (!_repushInFlight &&
            status.state == PostMatchReportSyncState.synced &&
            previousState != PostMatchReportSyncState.synced) {
          unawaited(_repushUnsynced());
        }
      });
      _remoteSubscription = sync.remoteReportsStream.listen(_mergeRemote);
      _syncStatus = sync.status;
      try {
        await sync.initialize();
      } catch (_) {
        // Intentionally empty.
      }

      if (_syncStatus.state == PostMatchReportSyncState.synced) {
        unawaited(_repushUnsynced());
      }

      notifyListeners();
    }
  }

  PostMatchReport reportFor(String eventKey, String matchId) {
    final id = PostMatchReport.idFor(eventKey, matchId);
    return _reports.firstWhere(
      (r) => r.id == id,
      orElse: () => PostMatchReport(
        id: id,
        eventKey: eventKey,
        matchId: matchId,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
    );
  }

  List<PostMatchReport> reportsForEvent(String eventKey) =>
      _reports.where((r) => r.eventKey == eventKey).toList(growable: false);

  Future<bool> save({
    required String eventKey,
    required String matchId,
    required String auto,
    required String teleop,
    required String endgame,
    required String notes,
  }) async {
    final id = PostMatchReport.idFor(eventKey, matchId);
    final updated = PostMatchReport(
      id: id,
      eventKey: eventKey,
      matchId: matchId,
      auto: auto,
      teleop: teleop,
      endgame: endgame,
      notes: notes,
      authorUid: _syncService?.currentUserUid ?? '',
      authorDisplayName: _syncService?.currentUserDisplayName ?? '',
      updatedAt: DateTime.now().toUtc(),
    );
    final mutation = _nextMutation(id);
    final index = _reports.indexWhere((r) => r.id == id);
    if (index >= 0) {
      _reports[index] = updated;
    } else {
      _reports.add(updated);
    }
    notifyListeners();

    final snapshot = PostMatchReport.fromJson(updated.toJson());
    final saved = await _enqueueSave(snapshot);
    if (!saved) {
      _rollback(id, mutation);
      return false;
    }

    _analytics.capture('post_match_report_saved');
    final sync = _syncService;
    if (sync != null) {
      _unsyncedReportIds.add(id);
      _persistPendingIds();
      unawaited(sync.push(snapshot));
    }
    return true;
  }

  Future<void> _mergeRemote(List<PostMatchReport> remote) async {
    var changed = false;
    var pendingChanged = false;
    for (final incoming in remote) {
      if (_unsyncedReportIds.remove(incoming.id)) {
        pendingChanged = true;
      }
      _rejectedIds.remove(incoming.id);
      final index = _reports.indexWhere((local) => local.id == incoming.id);
      if (index < 0) {
        _nextMutation(incoming.id);
        _reports.add(incoming);
        _enqueueSave(incoming);
        changed = true;
        continue;
      }
      final existing = _reports[index];
      if (incoming.updatedAt.isAfter(existing.updatedAt)) {
        _nextMutation(incoming.id);
        _reports[index] = incoming;
        _enqueueSave(incoming);
        changed = true;
      }
    }
    if (pendingChanged) {
      _persistPendingIds();
    }
    if (changed) {
      notifyListeners();
    }
  }

  void _persistPendingIds() {
    final snapshot = _unsyncedReportIds.toSet();
    _saveQueue = _saveQueue
        .then((_) => _storage.savePendingIds(snapshot))
        .catchError(
          (Object e) =>
              debugPrint('Post match report pending id save failed: $e'),
        );
  }

  Future<bool> _enqueueSave(PostMatchReport report) {
    final result = _saveQueue
        .then((_) => _storage.saveReport(report))
        .then(
          (_) {
            _confirmed[report.id] = report;
            if (failedWrites.recordSuccess()) notifyListeners();
            return true;
          },
          onError: (Object e) {
            debugPrint('Post match report save failed: $e');
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
        final targetIds = _unsyncedReportIds.difference(_rejectedIds);
        if (targetIds.isEmpty) continue;

        await _saveQueue;
        for (final id in targetIds) {
          final index = _reports.indexWhere((report) => report.id == id);
          if (index < 0) {
            if (_unsyncedReportIds.remove(id)) {
              _persistPendingIds();
            }
            continue;
          }
          final snapshot = PostMatchReport.fromJson(_reports[index].toJson());
          await sync.push(snapshot);

          if (sync.status.state == PostMatchReportSyncState.synced) {
            _unsyncedReportIds.remove(id);
            _rejectedIds.remove(id);
            _persistPendingIds();
          } else if (sync.status.state == PostMatchReportSyncState.rejected) {
            _rejectedIds.add(id);
          }
        }
      } while (_repushPending);
    } finally {
      _repushInFlight = false;
    }
  }

  int _nextMutation(String id) {
    final next = (_mutations[id] ?? 0) + 1;
    _mutations[id] = next;
    return next;
  }

  void _rollback(String id, int mutation) {
    if (_mutations[id] != mutation) {
      notifyListeners();
      return;
    }
    final confirmed = _confirmed[id];
    final index = _reports.indexWhere((r) => r.id == id);
    if (confirmed == null) {
      if (index >= 0) _reports.removeAt(index);
    } else if (index >= 0) {
      _reports[index] = confirmed;
    } else {
      _reports.add(confirmed);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _remoteSubscription?.cancel();
    _statusSubscription?.cancel();
    _syncService?.dispose();
    super.dispose();
  }
}
