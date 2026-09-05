import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/pick_list.dart';
import '../services/pick_list_storage.dart';
import '../services/pick_list_sync_service.dart';
import 'failed_write_tracker.dart';

class PickListController extends ChangeNotifier {
  PickListController({
    PickListStorage? storage,
    this._syncService,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) : _storage = storage ?? SharedPreferencesPickListStorage(),
       _idGenerator = idGenerator ?? (() => const Uuid().v4()),
       _clock = clock ?? DateTime.now;

  final PickListStorage _storage;
  final PickListSyncService? _syncService;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  List<PickList> _lists = <PickList>[];

  final Set<String> _remoteSyncedIds = <String>{};
  Future<void>? _bootstrapFuture;
  Future<void> _saveQueue = Future<void>.value();
  bool _ready = false;
  StreamSubscription<List<PickList>>? _remoteSubscription;
  StreamSubscription<PickListSyncStatus>? _statusSubscription;
  PickListSyncStatus _syncStatus = const PickListSyncStatus(
    state: PickListSyncState.signedOut,
  );

  final Map<String, int> _mutations = <String, int>{};

  final Map<String, PickList> _confirmed = <String, PickList>{};

  String? _lastError;

  final FailedWriteTracker failedWrites = FailedWriteTracker();

  List<PickList> get lists => List<PickList>.unmodifiable(_lists);

  String? get lastError => _lastError;

  void clearLastError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  bool get isReady => _ready;
  PickListSyncStatus get syncStatus => _syncStatus;
  String? get currentUserUid => _syncService?.currentUserUid;
  String? get currentUserDisplayName => _syncService?.currentUserDisplayName;

  PickList? byId(String id) {
    for (final list in _lists) {
      if (list.id == id) return list;
    }
    return null;
  }

  Future<void> bootstrap() {
    return _bootstrapFuture ??= _bootstrap();
  }

  Future<void> _bootstrap() async {
    _lists = await _storage.loadAll();
    _remoteSyncedIds
      ..clear()
      ..addAll(await _storage.loadSyncedIds());
    _ready = true;
    notifyListeners();

    final sync = _syncService;
    if (sync != null) {
      _statusSubscription = sync.statusStream.listen((status) {
        _syncStatus = status;
        notifyListeners();
      });
      _remoteSubscription = sync.remoteListsStream.listen(_mergeRemote);
      _syncStatus = sync.status;
      try {
        await sync.initialize();
      } catch (_) {}
    }
  }

  Future<PickList?> create(String name) async {
    final trimmed = name.trim();
    final list = PickList(
      id: _idGenerator(),
      name: trimmed.isEmpty ? 'Untitled list' : trimmed,
      teamNumbers: const <int>[],
      updatedAt: _clock(),
      authorUid: _syncService?.currentUserUid ?? '',
      authorDisplayName: _syncService?.currentUserDisplayName ?? '',
    );
    final mutation = _nextMutation(list.id);
    _lists = <PickList>[list, ..._lists];
    notifyListeners();
    final snapshot = PickList.fromJson(list.toJson());
    final saved = _enqueueSave(snapshot);
    await _saveQueue;
    if (!await saved) {
      _lastError = 'Could not create "${list.name}".';
      if (_mutations[list.id] == mutation) {
        _lists = _lists.where((l) => l.id != list.id).toList();
      }
      notifyListeners();
      return null;
    }
    unawaited(_syncService?.push(snapshot));
    return list;
  }

  Future<void> rename(String id, String name) {
    final trimmed = name.trim();
    return _mutate(id, (l) => trimmed.isEmpty ? l : l.copyWith(name: trimmed));
  }

  Future<void> addTeam(String id, int team) {
    return _mutate(
      id,
      (l) => l.teamNumbers.contains(team)
          ? l
          : l.copyWith(teamNumbers: <int>[...l.teamNumbers, team]),

      pushOverride: (snapshot) =>
          _syncService?.pushTeamAdd(snapshot, team) ?? Future<void>.value(),
    );
  }

  Future<void> removeTeam(String id, int team) {
    return _mutate(
      id,
      (l) => l.copyWith(
        teamNumbers: l.teamNumbers.where((t) => t != team).toList(),
      ),
      pushOverride: (snapshot) =>
          _syncService?.pushTeamRemove(snapshot, team) ?? Future<void>.value(),
    );
  }

  Future<void> reorder(String id, int oldIndex, int newIndex) {
    return _mutate(id, (l) {
      final teams = <int>[...l.teamNumbers];
      if (oldIndex < 0 || oldIndex >= teams.length) return l;
      final moved = teams.removeAt(oldIndex);
      final target = newIndex.clamp(0, teams.length);
      teams.insert(target, moved);
      return l.copyWith(teamNumbers: teams);
    });
  }

  Future<bool> delete(String id) async {
    final removed = _lists.firstWhere(
      (l) => l.id == id,
      orElse: () => _missingList,
    );

    if (identical(removed, _missingList)) return true;
    final mutation = _nextMutation(id);
    _lists = _lists.where((l) => l.id != id).toList();
    notifyListeners();
    final deleted = _enqueueDelete(id);

    final wasSynced = _remoteSyncedIds.remove(id);
    if (wasSynced) {
      _persistSyncedIds();
    }
    await _saveQueue;
    if (!await deleted) {
      if (wasSynced) {
        _remoteSyncedIds.add(id);

        _persistSyncedIds();
      }
      _rollback(id, mutation, 'Could not delete "${removed.name}".');
      return false;
    }
    final sync = _syncService;
    if (sync != null) {
      unawaited(sync.delete(removed));
    }
    return true;
  }

  Future<void> _mutate(
    String id,
    PickList Function(PickList) update, {
    Future<void> Function(PickList snapshot)? pushOverride,
  }) async {
    final index = _lists.indexWhere((l) => l.id == id);
    if (index < 0) return;
    final before = _lists[index];

    final now = _clock();
    final stamp = now.isAfter(before.updatedAt)
        ? now
        : before.updatedAt.add(const Duration(milliseconds: 1));
    final updated = update(before).copyWith(updatedAt: stamp);
    final mutation = _nextMutation(id);
    _lists = <PickList>[..._lists]..[index] = updated;
    notifyListeners();
    final snapshot = PickList.fromJson(updated.toJson());
    final saved = _enqueueSave(snapshot);
    await _saveQueue;
    if (!await saved) {
      _rollback(id, mutation, 'Could not save "${before.name}".');
      return;
    }
    if (pushOverride != null) {
      unawaited(pushOverride(snapshot));
    } else {
      unawaited(_syncService?.push(snapshot));
    }
  }

  int _nextMutation(String id) {
    final next = (_mutations[id] ?? 0) + 1;
    _mutations[id] = next;
    return next;
  }

  void _rollback(String id, int mutation, String message) {
    _lastError = message;
    if (_mutations[id] != mutation) {
      notifyListeners();
      return;
    }
    final confirmed = _confirmed[id];
    final index = _lists.indexWhere((l) => l.id == id);
    if (confirmed == null) {
      if (index >= 0) {
        _lists = _lists.where((l) => l.id != id).toList();
      }
    } else if (index >= 0) {
      _lists = <PickList>[..._lists]..[index] = confirmed;
    } else {
      _lists = <PickList>[..._lists, confirmed];
    }
    notifyListeners();
  }

  Future<bool> _enqueueSave(PickList list) {
    final result = _saveQueue
        .then((_) => _storage.save(list))
        .then(
          (_) {
            _confirmed[list.id] = list;
            if (failedWrites.recordSuccess()) notifyListeners();
            return true;
          },
          onError: (Object e) {
            debugPrint('Pick list save failed: $e');
            failedWrites.recordFailure();
            notifyListeners();
            return false;
          },
        );
    _saveQueue = result;
    return result;
  }

  Future<bool> _enqueueDelete(String id) {
    final result = _saveQueue
        .then((_) => _storage.delete(id))
        .then(
          (_) {
            _confirmed.remove(id);
            if (failedWrites.recordSuccess()) notifyListeners();
            return true;
          },
          onError: (Object e) {
            debugPrint('Pick list delete failed: $e');
            failedWrites.recordFailure();
            notifyListeners();
            return false;
          },
        );
    _saveQueue = result;
    return result;
  }

  void _persistSyncedIds() {
    final snapshot = _remoteSyncedIds.toSet();
    _saveQueue = _saveQueue
        .then((_) => _storage.saveSyncedIds(snapshot))
        .catchError(
          (Object e) => debugPrint('Pick list synced-id save failed: $e'),
        );
  }

  void _mergeRemote(List<PickList> remote) {
    var changed = false;
    var syncedChanged = false;
    final remoteIds = <String>{};
    for (final incoming in remote) {
      remoteIds.add(incoming.id);
      if (_remoteSyncedIds.add(incoming.id)) {
        syncedChanged = true;
      }

      _confirmed[incoming.id] = incoming;
      final index = _lists.indexWhere((local) => local.id == incoming.id);
      if (index < 0) {
        _nextMutation(incoming.id);
        _lists = <PickList>[..._lists, incoming];
        _enqueueSave(incoming);
        changed = true;
        continue;
      }
      final existing = _lists[index];

      final acceptable = !incoming.updatedAt.isBefore(existing.updatedAt);
      if (acceptable && !_sameContent(incoming, existing)) {
        _nextMutation(incoming.id);
        _lists = <PickList>[..._lists]..[index] = incoming;
        _enqueueSave(incoming);
        changed = true;
      }
    }

    final removedRemotely = _remoteSyncedIds
        .where((id) => !remoteIds.contains(id))
        .toList(growable: false);
    for (final id in removedRemotely) {
      _remoteSyncedIds.remove(id);
      syncedChanged = true;
      _confirmed.remove(id);
      final before = _lists.length;

      _nextMutation(id);
      _lists = _lists.where((l) => l.id != id).toList();
      if (_lists.length != before) {
        _enqueueDelete(id);
        changed = true;
      }
    }
    if (syncedChanged) {
      _persistSyncedIds();
    }
    if (changed) {
      _lists = <PickList>[..._lists]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      notifyListeners();
    }
  }

  static bool _sameContent(PickList a, PickList b) {
    return a.name == b.name &&
        a.authorUid == b.authorUid &&
        a.authorDisplayName == b.authorDisplayName &&
        listEquals(a.teamNumbers, b.teamNumbers);
  }

  Future<void> syncNow() async => _syncService?.syncNow();

  static final PickList _missingList = PickList(
    id: '__missing__',
    name: '',
    teamNumbers: const <int>[],
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  void dispose() {
    _remoteSubscription?.cancel();
    _statusSubscription?.cancel();
    _syncService?.dispose();
    super.dispose();
  }
}
