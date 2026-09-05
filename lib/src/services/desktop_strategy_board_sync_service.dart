import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/strategy_session.dart';
import 'desktop_poll_backoff.dart';
import 'in_flight_local_writes.dart';
import 'match_directory.dart';
import 'pending_push_queue.dart';
import 'spectrum_auth_service.dart';
import 'strategy_board_sync_service.dart';

class DesktopStrategyBoardSyncService implements StrategyBoardSyncService {
  DesktopStrategyBoardSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
    this._directory,
    PendingPushQueue? pendingPushQueue,
  }) : _clock = clock ?? DateTime.now,
       _queue = pendingPushQueue ?? PendingPushQueue();

  static const String _collection = 'strategyBoards';

  static const String _deleteCollection = 'strategyBoards_deleted';

  static const Duration _cursorOverlap = Duration(minutes: 2);

  static const int _fullSyncEveryPolls = 10;

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final DateTime Function() _clock;

  final MatchDirectory? _directory;

  final PendingPushQueue _queue;

  final Map<String, StrategySession> _cache = <String, StrategySession>{};

  final InFlightLocalWrites<StrategySession> _inFlightWrites =
      InFlightLocalWrites<StrategySession>();

  DateTime? _cursor;

  int _pollsSinceFullSync = 0;

  final StreamController<StrategyBoardSyncStatus> _statusController =
      StreamController<StrategyBoardSyncStatus>.broadcast();
  final StreamController<List<StrategySession>> _remoteController =
      StreamController<List<StrategySession>>.broadcast();

  StrategyBoardSyncStatus _status = const StrategyBoardSyncStatus(
    state: StrategyBoardSyncState.signedOut,
  );
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );

  @override
  Stream<StrategyBoardSyncStatus> get statusStream => _statusController.stream;

  @override
  StrategyBoardSyncStatus get status => _status;

  @override
  Stream<List<StrategySession>> get remoteBoardsStream =>
      _remoteController.stream;

  @override
  Future<void> initialize() async {
    _authSubscription = _authService.snapshotStream.listen(_onAuthChanged);
    _onAuthChanged(_authService.snapshot);
  }

  void _onAuthChanged(SpectrumAuthSnapshot snapshot) {
    if (snapshot.state == SpectrumAuthState.signedIn) {
      _emit(
        const StrategyBoardSyncStatus(state: StrategyBoardSyncState.syncing),
      );
      unawaited(syncNow());
      _pollScheduler.start(syncNow);
    } else {
      _pollScheduler.cancel();

      _cache.clear();
      _cursor = null;
      _emitRemote(<StrategySession>[]);
      _emit(
        const StrategyBoardSyncStatus(state: StrategyBoardSyncState.signedOut),
      );
    }
  }

  @override
  Future<void> push(StrategySession session) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }
    try {
      final json = prepareBoardPayload(
        session,
        user.uid,
        user.displayName,
        session.updatedAt.toUtc(),
      );
      await _firestore.setDocument('$_collection/${session.id}', json);
      await _queue.clear(_collection, session.id);
      final stamped = StrategySession.fromJson(session.toJson());
      stamped.updatedAt = session.updatedAt.toUtc();
      _cache[stamped.id] = stamped;

      _inFlightWrites.recordPush(stamped.id, stamped);
      final ts = stamped.updatedAt.toUtc();
      if (_cursor == null || ts.isAfter(_cursor!)) {
        _cursor = ts;
      }
      _emitSynced();
    } catch (error) {
      await _queue.mark(_collection, session.id);
      _emitFailure(error);
    }
  }

  @override
  Future<void> delete(StrategySession session) async {
    if (_authService.currentUser == null) {
      return;
    }
    try {
      await _firestore.deleteDocument('$_collection/${session.id}');
      await _queue.clear(_deleteCollection, session.id);

      await _queue.clear(_collection, session.id);

      _cache.remove(session.id);

      _inFlightWrites.recordDelete(session.id);
      _emitSynced();
    } catch (error) {
      await _queue.mark(_deleteCollection, session.id);
      _emitFailure(error);
    }
  }

  Future<void> _syncChain = Future<void>.value();

  @override
  Future<void> syncNow() {
    final next = _syncChain.then((_) => _syncOnce());
    _syncChain = next.catchError((_) {});
    return next;
  }

  Future<void> _syncOnce() async {
    if (_authService.currentUser == null) {
      _emit(
        const StrategyBoardSyncStatus(state: StrategyBoardSyncState.signedOut),
      );
      return;
    }

    await _retryPending();

    final isFullSync =
        _cursor == null || _pollsSinceFullSync >= _fullSyncEveryPolls - 1;

    _inFlightWrites.beginFetch();
    try {
      final docs = isFullSync
          ? await _firestore.listDocuments(_collection)
          : await _firestore.runQuery(
              _collection,
              filters: [
                fc.FieldFilter(
                  'updatedAtTs',
                  'GREATER_THAN_OR_EQUAL',
                  _cursor!.subtract(_cursorOverlap),
                ),
              ],
            );
      if (isFullSync) {
        _pollsSinceFullSync = 0;
      } else {
        _pollsSinceFullSync++;
      }

      final next = isFullSync
          ? <String, StrategySession>{}
          : Map<String, StrategySession>.of(_cache);
      for (final doc in docs) {
        final board = _decode(doc);
        if (board == null) continue;
        next[board.id] = board;
        final serverTs = doc.fields['updatedAtTs'];
        if (serverTs is DateTime) {
          final ts = serverTs.toUtc();
          if (_cursor == null || ts.isAfter(_cursor!)) {
            _cursor = ts;
          }
        }
      }
      _cursor ??= _clock().toUtc();
      _cache
        ..clear()
        ..addAll(_inFlightWrites.resolve(next));
      _emitRemote(_cache.values.toList(growable: false));
      _emitSynced();
    } catch (error) {
      _inFlightWrites.abandonFetch();
      _emitFailure(error);
    }
  }

  Future<void> _retryPending() async {
    final deletes = await _queue.pending(_deleteCollection);
    for (final id in deletes) {
      await delete(StrategySession.create(id: id));
    }

    final directory = _directory;
    if (directory == null) return;
    final ids = await _queue.pending(_collection);
    if (ids.isEmpty) return;
    for (final id in ids) {
      final session = await directory.loadMatch(id);
      if (session == null) {
        await _queue.clear(_collection, id);
        continue;
      }
      await push(session);
    }
  }

  @override
  Future<void> dispose() async {
    _pollScheduler.cancel();
    await _authSubscription?.cancel();
    await _statusController.close();
    await _remoteController.close();
  }

  StrategySession? _decode(fc.Document doc) {
    try {
      final session = StrategySession.fromJson(doc.fields);
      final ts = doc.fields['updatedAtTs'];
      if (ts is DateTime) {
        session.updatedAt = ts.toUtc();
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  void _emitSynced() {
    _pollScheduler.onSuccess();
    _emit(
      StrategyBoardSyncStatus(
        state: StrategyBoardSyncState.synced,
        lastSyncedAt: _clock(),
      ),
    );
  }

  void _emitFailure(Object error) {
    _pollScheduler.onFailure();
    if (error is fc.FirestoreApiException &&
        (error.statusCode == 403 || error.statusCode == 401)) {
      _cache.clear();
      _cursor = null;
      _emitRemote(<StrategySession>[]);
      _emit(
        StrategyBoardSyncStatus(
          state: StrategyBoardSyncState.noAccess,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.message,
        ),
      );
      return;
    }
    _emit(
      StrategyBoardSyncStatus(
        state: StrategyBoardSyncState.offline,
        lastSyncedAt: _status.lastSyncedAt,
        error: error.toString(),
      ),
    );
  }

  void _emit(StrategyBoardSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void _emitRemote(List<StrategySession> boards) {
    if (!_remoteController.isClosed) {
      _remoteController.add(boards);
    }
  }
}
