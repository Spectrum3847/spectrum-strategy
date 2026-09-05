import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/pick_list.dart';
import 'desktop_poll_backoff.dart';
import 'in_flight_local_writes.dart';
import 'pending_push_queue.dart';
import 'pick_list_storage.dart';
import 'pick_list_sync_service.dart';
import 'spectrum_auth_service.dart';

class _PendingTeamOp {
  const _PendingTeamOp({
    required this.team,
    required this.isAdd,
    required this.updatedAt,
  });

  final int team;
  final bool isAdd;
  final DateTime updatedAt;
}

class DesktopPickListSyncService implements PickListSyncService {
  DesktopPickListSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
    this._storage,
    PendingPushQueue? pendingPushQueue,
  }) : _clock = clock ?? DateTime.now,
       _queue = pendingPushQueue ?? PendingPushQueue();

  static const String _deletedCollection = 'pickLists_deleted';

  static const Duration _cursorOverlap = Duration(minutes: 2);

  static const int _fullSyncEveryPolls = 10;

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final DateTime Function() _clock;
  final PickListStorage? _storage;
  final PendingPushQueue _queue;

  final Map<String, PickList> _cache = <String, PickList>{};

  final InFlightLocalWrites<PickList> _inFlightWrites =
      InFlightLocalWrites<PickList>();

  DateTime? _cursor;

  int _pollsSinceFullSync = 0;

  final Map<String, List<_PendingTeamOp>> _pendingTeamOps =
      <String, List<_PendingTeamOp>>{};

  final StreamController<PickListSyncStatus> _statusController =
      StreamController<PickListSyncStatus>.broadcast();
  final StreamController<List<PickList>> _remoteController =
      StreamController<List<PickList>>.broadcast();

  PickListSyncStatus _status = const PickListSyncStatus(
    state: PickListSyncState.signedOut,
  );
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );

  @override
  Stream<PickListSyncStatus> get statusStream => _statusController.stream;

  @override
  PickListSyncStatus get status => _status;

  @override
  Stream<List<PickList>> get remoteListsStream => _remoteController.stream;

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
      _emit(const PickListSyncStatus(state: PickListSyncState.syncing));
      unawaited(syncNow());
      _pollScheduler.start(syncNow);
    } else {
      _pollScheduler.cancel();

      _cache.clear();
      _cursor = null;
      _emit(const PickListSyncStatus(state: PickListSyncState.signedOut));
    }
  }

  @override
  Future<void> push(PickList list) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }

    final stamped = list.copyWith(
      authorUid: list.authorUid.isEmpty ? user.uid : list.authorUid,
      authorDisplayName: list.authorDisplayName.isEmpty
          ? user.displayName
          : list.authorDisplayName,
    );

    await _queue.clear(_deletedCollection, stamped.id);
    try {
      await _firestore.setDocument('pickLists/${stamped.id}', {
        ...stamped.toJson(),

        'updatedAtTs': stamped.updatedAt.toUtc(),
      });
      await _queue.clear('pickLists', stamped.id);
      _cache[stamped.id] = stamped;

      _inFlightWrites.recordPush(stamped.id, stamped);
      final ts = stamped.updatedAt.toUtc();
      if (_cursor == null || ts.isAfter(_cursor!)) {
        _cursor = ts;
      }
      _emitSynced();
    } catch (error) {
      await _queue.mark('pickLists', stamped.id);
      _emitFailure(error);
    }
  }

  @override
  Future<void> pushTeamAdd(PickList list, int team) {
    return _pushTeamOp(list, team: team, isAdd: true);
  }

  @override
  Future<void> pushTeamRemove(PickList list, int team) {
    return _pushTeamOp(list, team: team, isAdd: false);
  }

  Future<void> _pushTeamOp(
    PickList list, {
    required int team,
    required bool isAdd,
  }) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }

    await _queue.clear(_deletedCollection, list.id);
    try {
      await _commitTeamOp(
        list.id,
        team: team,
        isAdd: isAdd,
        updatedAt: list.updatedAt,
      );
      await _queue.clear('pickLists', list.id);

      final cached = _cache[list.id];
      if (cached != null) {
        final teams = isAdd
            ? (cached.teamNumbers.contains(team)
                  ? cached.teamNumbers
                  : [...cached.teamNumbers, team])
            : cached.teamNumbers.where((t) => t != team).toList();
        final updated = cached.copyWith(
          teamNumbers: teams,
          updatedAt: list.updatedAt,
        );
        _cache[list.id] = updated;

        _inFlightWrites.recordPush(list.id, updated);
      }
      final ts = list.updatedAt.toUtc();
      if (_cursor == null || ts.isAfter(_cursor!)) {
        _cursor = ts;
      }
      _emitSynced();
    } on fc.FirestoreApiException catch (error) {
      if (error.isNotFound) {
        await push(list);
        return;
      }
      _queueTeamOp(
        list.id,
        team: team,
        isAdd: isAdd,
        updatedAt: list.updatedAt,
      );
      await _queue.mark('pickLists', list.id);
      _emitFailure(error);
    } catch (error) {
      _queueTeamOp(
        list.id,
        team: team,
        isAdd: isAdd,
        updatedAt: list.updatedAt,
      );
      await _queue.mark('pickLists', list.id);
      _emitFailure(error);
    }
  }

  Future<void> _commitTeamOp(
    String listId, {
    required int team,
    required bool isAdd,
    required DateTime updatedAt,
  }) {
    return _firestore.commitUpdate(
      'pickLists/$listId',
      fields: {
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'updatedAtTs': updatedAt.toUtc(),
      },
      appendMissingElements: isAdd
          ? {
              'teamNumbers': [team],
            }
          : const {},
      removeAllFromArray: isAdd
          ? const {}
          : {
              'teamNumbers': [team],
            },
      mustExist: true,
    );
  }

  void _queueTeamOp(
    String listId, {
    required int team,
    required bool isAdd,
    required DateTime updatedAt,
  }) {
    _pendingTeamOps
        .putIfAbsent(listId, () => <_PendingTeamOp>[])
        .add(_PendingTeamOp(team: team, isAdd: isAdd, updatedAt: updatedAt));
  }

  @override
  Future<void> delete(PickList list) => _deleteById(list.id);

  Future<void> _deleteById(String id) async {
    if (_authService.currentUser == null) {
      return;
    }

    _pendingTeamOps.remove(id);
    await _queue.clear('pickLists', id);
    try {
      await _firestore.deleteDocument('pickLists/$id');
      await _queue.clear(_deletedCollection, id);

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
    final ids = await _queue.pending('pickLists');
    if (ids.isEmpty) return;
    final all = await storage.loadAll();
    for (final id in ids) {
      if (await _flushTeamOps(id)) continue;
      final list = all.where((l) => l.id == id).firstOrNull;
      if (list == null) {
        await _queue.clear('pickLists', id);
        continue;
      }
      await push(list);
    }
  }

  Future<bool> _flushTeamOps(String id) async {
    final ops = _pendingTeamOps[id];
    if (ops == null || ops.isEmpty) return false;
    while (ops.isNotEmpty) {
      final op = ops.first;
      try {
        await _commitTeamOp(
          id,
          team: op.team,
          isAdd: op.isAdd,
          updatedAt: op.updatedAt,
        );
        ops.removeAt(0);
      } on fc.FirestoreApiException catch (error) {
        if (error.isNotFound) {
          _pendingTeamOps.remove(id);
          return false;
        }
        _emitFailure(error);
        return true;
      } catch (error) {
        _emitFailure(error);
        return true;
      }
    }
    _pendingTeamOps.remove(id);
    await _queue.clear('pickLists', id);
    _emitSynced();
    return true;
  }

  Future<void> _syncOnce() async {
    if (_authService.currentUser == null) {
      _emit(const PickListSyncStatus(state: PickListSyncState.signedOut));
      return;
    }

    final isFullSync =
        _cursor == null || _pollsSinceFullSync >= _fullSyncEveryPolls - 1;

    _inFlightWrites.beginFetch();
    try {
      final docs = isFullSync
          ? await _firestore.listDocuments('pickLists')
          : await _firestore.runQuery(
              'pickLists',
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
          ? <String, PickList>{}
          : Map<String, PickList>.of(_cache);
      for (final doc in docs) {
        final list = _decode(doc);
        if (list == null) continue;
        next[list.id] = list;
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

  PickList? _decode(fc.Document doc) {
    try {
      final list = PickList.fromJson(doc.fields);

      final ts = doc.fields['updatedAtTs'];
      if (ts is DateTime) {
        return list.copyWith(updatedAt: ts.toUtc());
      }
      return list;
    } catch (_) {
      return null;
    }
  }

  void _emitSynced() {
    _pollScheduler.onSuccess();
    _emit(
      PickListSyncStatus(
        state: PickListSyncState.synced,
        lastSyncedAt: _clock(),
      ),
    );
  }

  void _emitFailure(Object error) {
    _pollScheduler.onFailure();

    if (error is fc.FirestoreApiException &&
        (error.statusCode == 403 || error.statusCode == 401)) {
      _emit(
        PickListSyncStatus(
          state: PickListSyncState.noAccess,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.message,
        ),
      );
      return;
    }
    _emit(
      PickListSyncStatus(
        state: PickListSyncState.offline,
        lastSyncedAt: _status.lastSyncedAt,
        error: error.toString(),
      ),
    );
  }

  void _emit(PickListSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }
}
