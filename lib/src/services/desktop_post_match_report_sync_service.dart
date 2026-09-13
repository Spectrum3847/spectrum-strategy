import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/post_match_report.dart';
import 'desktop_poll_backoff.dart';
import 'pending_push_queue.dart';
import 'post_match_report_storage.dart';
import 'post_match_report_sync_service.dart';
import 'spectrum_auth_service.dart';

class DesktopPostMatchReportSyncService implements PostMatchReportSyncService {
  DesktopPostMatchReportSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
    this._storage,
    PendingPushQueue? pendingPushQueue,
  }) : _clock = clock ?? DateTime.now,
       _queue = pendingPushQueue ?? PendingPushQueue();

  static const String _collection = 'postMatchReports';

  static const Duration _cursorOverlap = Duration(minutes: 2);

  static const int _fullSyncEveryPolls = 10;

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final DateTime Function() _clock;
  final PostMatchReportStorage? _storage;
  final PendingPushQueue _queue;

  DateTime? _cursor;

  int _pollsSinceFullSync = 0;

  final StreamController<PostMatchReportSyncStatus> _statusController =
      StreamController<PostMatchReportSyncStatus>.broadcast();
  final StreamController<List<PostMatchReport>> _remoteController =
      StreamController<List<PostMatchReport>>.broadcast();

  PostMatchReportSyncStatus _status = const PostMatchReportSyncStatus(
    state: PostMatchReportSyncState.signedOut,
  );
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );

  @override
  Stream<PostMatchReportSyncStatus> get statusStream =>
      _statusController.stream;

  @override
  PostMatchReportSyncStatus get status => _status;

  @override
  Stream<List<PostMatchReport>> get remoteReportsStream =>
      _remoteController.stream;

  @override
  String? get currentUserUid => _authService.currentUser?.uid;

  @override
  String? get currentUserDisplayName => _authService.currentUser?.displayName;

  @override
  Future<void> initialize() async {
    _authSubscription = _authService.snapshotStream.listen(_onAuthChanged);
    _onAuthChanged(_authService.snapshot);
  }

  void _onAuthChanged(SpectrumAuthSnapshot snapshot) {
    if (snapshot.state == SpectrumAuthState.signedIn) {
      _emit(
        const PostMatchReportSyncStatus(
          state: PostMatchReportSyncState.syncing,
        ),
      );
      unawaited(_syncNow());
      _pollScheduler.start(_syncNow);
    } else {
      _pollScheduler.cancel();
      _emit(
        const PostMatchReportSyncStatus(
          state: PostMatchReportSyncState.signedOut,
        ),
      );
    }
  }

  @override
  Future<void> push(PostMatchReport report) async {
    if (_authService.currentUser == null) {
      return;
    }
    try {
      await _firestore.setDocument('$_collection/${report.id}', {
        ...report.toJson(),

        'updatedAtTs': report.updatedAt.toUtc(),
      });
      await _queue.clear(_collection, report.id);

      if (_cursor == null || report.updatedAt.toUtc().isAfter(_cursor!)) {
        _cursor = report.updatedAt.toUtc();
      }
      _emitSynced();
    } catch (error) {
      await _queue.mark(_collection, report.id);
      _emitFailure(error);
    }
  }

  Future<void> _syncChain = Future<void>.value();

  Future<void> _syncNow() {
    final next = _syncChain
        .then((_) => _flushPending())
        .then((_) => _syncOnce());
    _syncChain = next.catchError((_) {});
    return next;
  }

  Future<void> _flushPending() async {
    final storage = _storage;
    if (storage == null) return;
    final ids = await _queue.pending(_collection);
    if (ids.isEmpty) return;
    final all = await storage.loadAll();
    for (final id in ids) {
      final report = all.where((r) => r.id == id).firstOrNull;
      if (report == null) {
        await _queue.clear(_collection, id);
        continue;
      }
      await push(report);
    }
  }

  Future<void> _syncOnce() async {
    if (_authService.currentUser == null) {
      _emit(
        const PostMatchReportSyncStatus(
          state: PostMatchReportSyncState.signedOut,
        ),
      );
      return;
    }
    try {
      final isFullSync =
          _cursor == null || _pollsSinceFullSync >= _fullSyncEveryPolls - 1;
      final List<fc.Document> docs;
      if (isFullSync) {
        docs = await _firestore.listDocuments(_collection);
      } else {
        docs = await _firestore.runQuery(
          _collection,
          filters: [
            fc.FieldFilter(
              'updatedAtTs',
              'GREATER_THAN_OR_EQUAL',
              _cursor!.subtract(_cursorOverlap),
            ),
          ],
        );
      }
      if (isFullSync) {
        _pollsSinceFullSync = 0;
      } else {
        _pollsSinceFullSync++;
      }
      final reports = <PostMatchReport>[];
      for (final doc in docs) {
        final decoded = _decode(doc);
        if (decoded == null) {
          continue;
        }
        reports.add(decoded);

        final serverTs = doc.fields['updatedAtTs'];
        if (serverTs is DateTime) {
          final ts = serverTs.toUtc();
          if (_cursor == null || ts.isAfter(_cursor!)) {
            _cursor = ts;
          }
        }
      }
      _cursor ??= _clock().toUtc();
      if (!_remoteController.isClosed) {
        _remoteController.add(reports);
      }
      _emitSynced();
    } catch (error) {
      _emitFailure(error);
    }
  }

  @override
  Future<void> dispose() async {
    _pollScheduler.cancel();
    await _authSubscription?.cancel();
    await _statusController.close();
    await _remoteController.close();
  }

  PostMatchReport? _decode(fc.Document doc) {
    try {
      final report = PostMatchReport.fromJson(doc.fields);

      final ts = doc.fields['updatedAtTs'];
      if (ts is DateTime) {
        return report.copyWith(updatedAt: ts.toUtc());
      }
      return report;
    } catch (_) {
      return null;
    }
  }

  void _emitSynced() {
    _pollScheduler.onSuccess();
    _emit(
      PostMatchReportSyncStatus(
        state: PostMatchReportSyncState.synced,
        lastSyncedAt: _clock(),
      ),
    );
  }

  void _emitFailure(Object error) {
    _pollScheduler.onFailure();

    if (error is fc.FirestoreApiException &&
        (error.statusCode == 403 || error.statusCode == 401)) {
      _emit(
        const PostMatchReportSyncStatus(
          state: PostMatchReportSyncState.noAccess,
        ),
      );
      return;
    }
    _emit(
      PostMatchReportSyncStatus(
        state: PostMatchReportSyncState.offline,
        lastSyncedAt: _status.lastSyncedAt,
      ),
    );
  }

  void _emit(PostMatchReportSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }
}
