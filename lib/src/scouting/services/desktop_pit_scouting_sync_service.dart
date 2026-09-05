import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../../services/desktop_poll_backoff.dart';
import '../../services/in_flight_local_writes.dart';
import '../../services/pending_push_queue.dart';
import '../../services/spectrum_auth_service.dart';
import '../models/pit_scout_entry.dart';
import 'pit_scouting_storage.dart';
import 'pit_scouting_sync_service.dart';

class DesktopPitScoutingSyncService implements PitScoutingSyncService {
  DesktopPitScoutingSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
    this._storage,
    PendingPushQueue? pendingPushQueue,
  }) : _clock = clock ?? DateTime.now,
       _queue = pendingPushQueue ?? PendingPushQueue();

  static const String _deletedCollection = 'pitScoutEntries_deleted';

  static const Duration _cursorOverlap = Duration(minutes: 2);

  static const int _fullSyncEveryPolls = 10;

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final DateTime Function() _clock;
  final PitScoutingStorage? _storage;
  final PendingPushQueue _queue;

  final Map<String, PitScoutEntry> _cache = <String, PitScoutEntry>{};

  final InFlightLocalWrites<PitScoutEntry> _inFlightWrites =
      InFlightLocalWrites<PitScoutEntry>();

  DateTime? _cursor;

  int _pollsSinceFullSync = 0;

  final StreamController<PitScoutingSyncStatus> _statusController =
      StreamController<PitScoutingSyncStatus>.broadcast();
  final StreamController<List<PitScoutEntry>> _remoteController =
      StreamController<List<PitScoutEntry>>.broadcast();

  PitScoutingSyncStatus _status = const PitScoutingSyncStatus(
    state: PitScoutingSyncState.signedOut,
  );
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );

  @override
  Stream<PitScoutingSyncStatus> get statusStream => _statusController.stream;

  @override
  PitScoutingSyncStatus get status => _status;

  @override
  Stream<List<PitScoutEntry>> get remoteEntriesStream =>
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
      _emit(const PitScoutingSyncStatus(state: PitScoutingSyncState.syncing));
      unawaited(syncNow());
      _pollScheduler.start(syncNow);
    } else {
      _pollScheduler.cancel();

      _cache.clear();
      _cursor = null;
      _emit(const PitScoutingSyncStatus(state: PitScoutingSyncState.signedOut));
    }
  }

  @override
  Future<void> push(PitScoutEntry entry) async {
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
      await _firestore.setDocument('pitScoutEntries/${stamped.id}', {
        ...stamped.toRemoteJson(),

        'updatedAtTs': stamped.updatedAt.toUtc(),
      });
      await _queue.clear('pitScoutEntries', stamped.id);
      _cache[stamped.id] = stamped;

      _inFlightWrites.recordPush(stamped.id, stamped);
      final ts = stamped.updatedAt.toUtc();
      if (_cursor == null || ts.isAfter(_cursor!)) {
        _cursor = ts;
      }
      _emitSynced();
    } catch (error) {
      await _queue.mark('pitScoutEntries', stamped.id);
      _emitFailure(error);
    }
  }

  @override
  Future<void> delete(PitScoutEntry entry) => _deleteById(entry.id);

  Future<void> _deleteById(String id) async {
    if (_authService.currentUser == null) {
      return;
    }

    try {
      await _firestore.deleteDocument('pitScoutEntries/$id');
      await _queue.clear(_deletedCollection, id);

      await _queue.clear('pitScoutEntries', id);

      _cache.remove(id);

      _inFlightWrites.recordDelete(id);
      _emitSynced();
    } catch (error) {
      await _queue.mark(_deletedCollection, id);
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
    final ids = await _queue.pending('pitScoutEntries');
    if (ids.isEmpty) return;
    final all = await storage.loadAll();
    for (final id in ids) {
      final entry = all.where((e) => e.id == id).firstOrNull;
      if (entry == null) {
        await _queue.clear('pitScoutEntries', id);
        continue;
      }
      await push(entry);
    }
  }

  Future<void> _syncOnce() async {
    if (_authService.currentUser == null) {
      _emit(const PitScoutingSyncStatus(state: PitScoutingSyncState.signedOut));
      return;
    }

    final isFullSync =
        _cursor == null || _pollsSinceFullSync >= _fullSyncEveryPolls - 1;

    _inFlightWrites.beginFetch();
    try {
      final docs = isFullSync
          ? await _firestore.listDocuments('pitScoutEntries')
          : await _firestore.runQuery(
              'pitScoutEntries',
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
          ? <String, PitScoutEntry>{}
          : Map<String, PitScoutEntry>.of(_cache);
      for (final doc in docs) {
        final entry = _decode(doc);
        if (entry == null) continue;
        next[entry.id] = entry;
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
    _pollScheduler.cancel();
    await _authSubscription?.cancel();
    await _statusController.close();
    await _remoteController.close();
  }

  PitScoutEntry? _decode(fc.Document doc) {
    try {
      final entry = PitScoutEntry.fromJson(doc.fields);

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
      PitScoutingSyncStatus(
        state: PitScoutingSyncState.synced,
        lastSyncedAt: _clock(),
      ),
    );
  }

  void _emitFailure(Object error) {
    _pollScheduler.onFailure();

    if (error is fc.FirestoreApiException &&
        (error.statusCode == 403 || error.statusCode == 401)) {
      _emit(
        PitScoutingSyncStatus(
          state: PitScoutingSyncState.noAccess,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.message,
        ),
      );
      return;
    }
    _emit(
      PitScoutingSyncStatus(
        state: PitScoutingSyncState.offline,
        lastSyncedAt: _status.lastSyncedAt,
        error: error.toString(),
      ),
    );
  }

  void _emit(PitScoutingSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }
}
