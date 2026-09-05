import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../../services/desktop_poll_backoff.dart';
import '../../services/in_flight_local_writes.dart';
import '../../services/pending_push_queue.dart';
import '../../services/spectrum_auth_service.dart';
import '../models/scout_entry.dart';
import 'scouting_storage.dart';
import 'scouting_sync_service.dart';

class DesktopScoutingSyncService implements ScoutingSyncService {
  DesktopScoutingSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
    this._storage,
    PendingPushQueue? pendingPushQueue,
  }) : _clock = clock ?? DateTime.now,
       _queue = pendingPushQueue ?? PendingPushQueue();

  static const String _deletedCollection = 'scoutEntries_deleted';

  static const Duration _cursorOverlap = Duration(minutes: 2);

  static const int _fullSyncEveryPolls = 10;

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final DateTime Function() _clock;
  final ScoutingStorage? _storage;
  final PendingPushQueue _queue;
  int _pendingWrites = 0;

  final Map<String, ScoutEntry> _cache = <String, ScoutEntry>{};

  final InFlightLocalWrites<ScoutEntry> _inFlightWrites =
      InFlightLocalWrites<ScoutEntry>();

  DateTime? _cursor;

  int _pollsSinceFullSync = 0;

  final StreamController<ScoutingSyncStatus> _statusController =
      StreamController<ScoutingSyncStatus>.broadcast();
  final StreamController<List<ScoutEntry>> _remoteController =
      StreamController<List<ScoutEntry>>.broadcast();

  ScoutingSyncStatus _status = const ScoutingSyncStatus(
    state: ScoutingSyncState.signedOut,
  );
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );

  @override
  Stream<ScoutingSyncStatus> get statusStream => _statusController.stream;

  @override
  ScoutingSyncStatus get status => _status;

  @override
  Stream<List<ScoutEntry>> get remoteEntriesStream => _remoteController.stream;

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
      _stopPolling();
      _emit(const ScoutingSyncStatus(state: ScoutingSyncState.signedOut));
    }
  }

  void _startPolling() {
    _emit(const ScoutingSyncStatus(state: ScoutingSyncState.syncing));

    unawaited(syncNow());
    _pollScheduler.start(syncNow);
  }

  void _stopPolling() {
    _pollScheduler.cancel();
  }

  @override
  Future<void> push(ScoutEntry entry) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }

    final stamped = entry.copyWith(
      authorUid: entry.authorUid.isEmpty ? user.uid : entry.authorUid,
      authorDisplayName: entry.authorDisplayName.isEmpty
          ? user.displayName
          : entry.authorDisplayName,
    );

    await _queue.clear(_deletedCollection, stamped.id);
    try {
      await _firestore.setDocument('scoutEntries/${stamped.id}', {
        ...stamped.toJson(),

        'updatedAtTs': stamped.updatedAt.toUtc(),
      });

      _cache[stamped.id] = stamped;

      _inFlightWrites.recordPush(stamped.id, stamped);
      if (_cursor == null || stamped.updatedAt.isAfter(_cursor!)) {
        _cursor = stamped.updatedAt;
      }
      await _queue.clear('scoutEntries', stamped.id);
      await _syncPendingCount();
      _emitSynced();
    } catch (error) {
      await _queue.mark('scoutEntries', stamped.id);
      await _syncPendingCount();
      _emitFailure(error);
    }
  }

  @override
  Future<void> delete(ScoutEntry entry) => _deleteById(entry.id);

  Future<void> _deleteById(String id) async {
    if (_authService.currentUser == null) {
      return;
    }

    try {
      await _firestore.deleteDocument('scoutEntries/$id');

      _cache.remove(id);

      _inFlightWrites.recordDelete(id);
      await _queue.clear(_deletedCollection, id);

      await _queue.clear('scoutEntries', id);
      await _syncPendingCount();
      _emitSynced();
    } catch (error) {
      await _queue.mark(_deletedCollection, id);
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
    for (final id in await _queue.pending(_deletedCollection)) {
      await _deleteById(id);
    }

    final storage = _storage;
    if (storage == null) return;
    final ids = await _queue.pending('scoutEntries');
    if (ids.isEmpty) return;
    final all = await storage.loadAll();
    for (final id in ids) {
      final entry = all.where((e) => e.id == id).firstOrNull;
      if (entry == null) {
        await _queue.clear('scoutEntries', id);
        continue;
      }

      await push(entry);
    }
    await _syncPendingCount();
  }

  Future<void> _syncPendingCount() async {
    _pendingWrites =
        await _queue.count('scoutEntries') +
        await _queue.count(_deletedCollection);
  }

  Future<void> _syncOnce() async {
    if (_authService.currentUser == null) {
      _emit(const ScoutingSyncStatus(state: ScoutingSyncState.signedOut));
      return;
    }

    final isFullSync =
        _cursor == null || _pollsSinceFullSync >= _fullSyncEveryPolls - 1;

    _inFlightWrites.beginFetch();
    try {
      final List<fc.Document> docs;
      if (isFullSync) {
        final yearStart = DateTime.utc(_clock().year).toIso8601String();
        docs = await _firestore.runQuery(
          'scoutEntries',
          filters: [
            fc.FieldFilter('updatedAt', 'GREATER_THAN_OR_EQUAL', yearStart),
          ],
        );
      } else {
        docs = await _firestore.runQuery(
          'scoutEntries',
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

      final next = isFullSync
          ? <String, ScoutEntry>{}
          : Map<String, ScoutEntry>.of(_cache);
      for (final doc in docs) {
        final entry = _decode(doc);
        if (entry == null) continue;
        next[entry.id] = entry;

        final serverTimestamp = doc.fields['updatedAtTs'];
        if (serverTimestamp is DateTime) {
          final serverTs = serverTimestamp.toUtc();
          if (_cursor == null || serverTs.isAfter(_cursor!)) {
            _cursor = serverTs;
          }
        }
      }

      _cursor ??= _clock().toUtc();
      _cache
        ..clear()
        ..addAll(_inFlightWrites.resolve(next));
      if (!_remoteController.isClosed) {
        _remoteController.add(_cache.values.toList(growable: false));
      }
      _emitSynced();
    } catch (error) {
      _inFlightWrites.abandonFetch();
      _emitFailure(error);
    }
  }

  @override
  Future<void> dispose() async {
    _stopPolling();
    await _authSubscription?.cancel();
    await _statusController.close();
    await _remoteController.close();
  }

  ScoutEntry? _decode(fc.Document doc) {
    try {
      final entry = ScoutEntry.fromJson(doc.fields);

      final ts = doc.fields['updatedAtTs'];
      if (ts is DateTime) {
        return entry.copyWith(updatedAt: ts.toUtc());
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  void _emitSynced() {
    _pollScheduler.onSuccess();
    _emit(
      ScoutingSyncStatus(
        state: ScoutingSyncState.synced,
        lastSyncedAt: _clock(),
      ),
    );
  }

  void _emitFailure(Object error) {
    _pollScheduler.onFailure();

    if (error is fc.FirestoreApiException &&
        (error.statusCode == 403 || error.statusCode == 401)) {
      _emit(
        ScoutingSyncStatus(
          state: ScoutingSyncState.noAccess,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.message,
        ),
      );
      return;
    }
    _emit(
      ScoutingSyncStatus(
        state: ScoutingSyncState.offline,
        lastSyncedAt: _status.lastSyncedAt,
        error: error.toString(),
      ),
    );
  }

  void _emit(ScoutingSyncStatus next) {
    _status = ScoutingSyncStatus(
      state: next.state,
      lastSyncedAt: next.lastSyncedAt,
      error: next.error,
      pendingWrites: _pendingWrites,
    );
    if (!_statusController.isClosed) {
      _statusController.add(_status);
    }
  }
}
