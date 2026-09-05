import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/trex_trait_report.dart';
import 'desktop_poll_backoff.dart';
import 'pending_push_queue.dart';
import 'spectrum_auth_service.dart';
import 'trex_trait_report_storage.dart';
import 'trex_trait_report_sync_service.dart';

class DesktopTrexTraitReportSyncService implements TrexTraitReportSyncService {
  DesktopTrexTraitReportSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    this._storage,
    PendingPushQueue? pendingPushQueue,
    DateTime Function()? clock,
  }) : _queue = pendingPushQueue ?? PendingPushQueue(),
       _clock = clock ?? DateTime.now;

  static const String _collection = 'trexTraitReports';

  static const Duration _cursorOverlap = Duration(minutes: 2);

  static const int _fullSyncEveryPolls = 10;

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final TrexTraitReportStorage? _storage;
  final PendingPushQueue _queue;
  final DateTime Function() _clock;
  int _pendingWrites = 0;

  DateTime? _cursor;

  int _pollsSinceFullSync = 0;

  final StreamController<TrexTraitReportSyncStatus> _statusController =
      StreamController<TrexTraitReportSyncStatus>.broadcast();
  final StreamController<List<TrexTraitReport>> _remoteController =
      StreamController<List<TrexTraitReport>>.broadcast();

  TrexTraitReportSyncStatus _status = const TrexTraitReportSyncStatus(
    state: TrexTraitReportSyncState.signedOut,
  );
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );

  @override
  Stream<TrexTraitReportSyncStatus> get statusStream =>
      _statusController.stream;

  @override
  TrexTraitReportSyncStatus get status => _status;

  @override
  Stream<List<TrexTraitReport>> get remoteReportsStream =>
      _remoteController.stream;

  @override
  Future<void> initialize() async {
    await _syncPendingCount();
    _authSubscription = _authService.snapshotStream.listen(_onAuthChanged);
    _onAuthChanged(_authService.snapshot);
  }

  void _onAuthChanged(SpectrumAuthSnapshot snapshot) {
    if (snapshot.state == SpectrumAuthState.signedIn) {
      _startPolling();
    } else {
      _pollScheduler.cancel();
      _emit(
        const TrexTraitReportSyncStatus(
          state: TrexTraitReportSyncState.signedOut,
        ),
      );
    }
  }

  void _startPolling() {
    _emit(
      const TrexTraitReportSyncStatus(state: TrexTraitReportSyncState.syncing),
    );
    unawaited(syncNow());
    _pollScheduler.start(syncNow);
  }

  @override
  Future<void> push(TrexTraitReport report) async {
    final user = _authService.currentUser;
    if (user == null) return;
    final stamped = report.copyWith(
      authorUid: report.authorUid.isEmpty ? user.uid : report.authorUid,
      authorDisplayName: report.authorDisplayName.isEmpty
          ? user.displayName
          : report.authorDisplayName,
    );
    try {
      await _firestore.setDocument('$_collection/${stamped.id}', {
        ...stamped.toJson(),
        'updatedAtTs': stamped.updatedAt.toUtc(),
      });
      await _queue.clear(_collection, stamped.id);
      if (_cursor == null || stamped.updatedAt.toUtc().isAfter(_cursor!)) {
        _cursor = stamped.updatedAt.toUtc();
      }
      await _syncPendingCount();
      _emitSynced();
    } catch (error) {
      await _queue.mark(_collection, stamped.id);
      await _syncPendingCount();
      _emitFailure(error);
    }
  }

  Future<void> _syncChain = Future<void>.value();

  @override
  Future<void> syncNow() {
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
    await _syncPendingCount();
  }

  Future<void> _syncPendingCount() async {
    _pendingWrites = await _queue.count(_collection);
  }

  Future<void> _syncOnce() async {
    if (_authService.currentUser == null) {
      _emit(
        const TrexTraitReportSyncStatus(
          state: TrexTraitReportSyncState.signedOut,
        ),
      );
      return;
    }
    try {
      final isFullSync =
          _cursor == null || _pollsSinceFullSync >= _fullSyncEveryPolls - 1;
      final List<fc.Document> docs;
      if (isFullSync) {
        docs = await _firestore.runQuery(_collection);
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
      final reports = <TrexTraitReport>[];
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
      if (!_remoteController.isClosed) _remoteController.add(reports);
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

  TrexTraitReport? _decode(fc.Document doc) {
    try {
      final report = TrexTraitReport.fromJson(doc.fields);
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
      TrexTraitReportSyncStatus(
        state: TrexTraitReportSyncState.synced,
        lastSyncedAt: DateTime.now(),
      ),
    );
  }

  void _emitFailure(Object error) {
    _pollScheduler.onFailure();
    if (error is fc.FirestoreApiException &&
        (error.statusCode == 403 || error.statusCode == 401)) {
      _emit(
        TrexTraitReportSyncStatus(
          state: TrexTraitReportSyncState.noAccess,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.message,
        ),
      );
      return;
    }
    _emit(
      TrexTraitReportSyncStatus(
        state: TrexTraitReportSyncState.offline,
        lastSyncedAt: _status.lastSyncedAt,
        error: error.toString(),
      ),
    );
  }

  void _emit(TrexTraitReportSyncStatus next) {
    _status = TrexTraitReportSyncStatus(
      state: next.state,
      lastSyncedAt: next.lastSyncedAt,
      error: next.error,
      pendingWrites: _pendingWrites,
    );
    if (!_statusController.isClosed) _statusController.add(_status);
  }
}
