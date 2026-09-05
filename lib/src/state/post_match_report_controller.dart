import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/post_match_report.dart';
import '../services/post_match_report_storage.dart';
import '../services/post_match_report_sync_service.dart';
import 'failed_write_tracker.dart';

class PostMatchReportController extends ChangeNotifier {
  PostMatchReportController({
    PostMatchReportStorage? storage,
    this._syncService,
  }) : _storage = storage ?? SharedPreferencesPostMatchReportStorage();

  final PostMatchReportStorage _storage;
  final PostMatchReportSyncService? _syncService;

  Future<void>? _bootstrapFuture;
  Future<void> _saveQueue = Future<void>.value();
  final List<PostMatchReport> _reports = <PostMatchReport>[];

  final Map<String, int> _mutations = <String, int>{};

  final Map<String, PostMatchReport> _confirmed = <String, PostMatchReport>{};

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
    _ready = true;
    notifyListeners();

    final sync = _syncService;
    if (sync != null) {
      _statusSubscription = sync.statusStream.listen((status) {
        _syncStatus = status;
        notifyListeners();
      });
      _remoteSubscription = sync.remoteReportsStream.listen(_mergeRemote);
      _syncStatus = sync.status;
      try {
        await sync.initialize();
      } catch (_) {}
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

    final sync = _syncService;
    if (sync != null) {
      unawaited(sync.push(snapshot));
    }
    return true;
  }

  Future<void> _mergeRemote(List<PostMatchReport> remote) async {
    var changed = false;
    for (final incoming in remote) {
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
    if (changed) {
      notifyListeners();
    }
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
