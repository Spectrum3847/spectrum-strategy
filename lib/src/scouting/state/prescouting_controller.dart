import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../state/failed_write_tracker.dart';
import '../models/prescout_entry.dart';
import '../services/prescouting_storage.dart';
import '../services/prescouting_sync_service.dart';

class PrescoutingController extends ChangeNotifier {
  PrescoutingController({PrescoutingStorage? storage, this._syncService})
    : _storage = storage ?? SharedPreferencesPrescoutingStorage();

  final PrescoutingStorage _storage;
  final PrescoutingSyncService? _syncService;

  Future<void>? _bootstrapFuture;
  Future<void> _saveQueue = Future<void>.value();
  final List<PrescoutEntry> _entries = <PrescoutEntry>[];

  final Set<String> _remoteSyncedIds = <String>{};

  final Map<String, int> _mutations = <String, int>{};

  final Map<String, PrescoutEntry> _confirmed = <String, PrescoutEntry>{};

  String? _lastError;

  final FailedWriteTracker failedWrites = FailedWriteTracker();
  bool _ready = false;
  StreamSubscription<List<PrescoutEntry>>? _remoteSubscription;
  StreamSubscription<PrescoutingSyncStatus>? _statusSubscription;
  PrescoutingSyncStatus _syncStatus = const PrescoutingSyncStatus(
    state: PrescoutingSyncState.signedOut,
  );

  bool get isReady => _ready;
  List<PrescoutEntry> get entries => List<PrescoutEntry>.unmodifiable(_entries);

  String? get lastError => _lastError;

  void clearLastError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  PrescoutingSyncService? get syncService => _syncService;
  PrescoutingSyncStatus get syncStatus => _syncStatus;

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
    _entries
      ..clear()
      ..addAll(loaded);
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
      _remoteSubscription = sync.remoteEntriesStream.listen(_mergeRemote);
      _syncStatus = sync.status;
      try {
        await sync.initialize();
      } catch (_) {}
    }
  }

  List<PrescoutEntry> entriesForTeam(int teamNumber) {
    return _entries
        .where((e) => e.teamNumber == teamNumber)
        .toList(growable: false);
  }

  Future<bool> saveEntry(PrescoutEntry entry) async {
    final sync = _syncService;

    final stamped = entry.copyWith(
      updatedAt: DateTime.now().toUtc(),
      authorUid: entry.authorUid.isEmpty
          ? sync?.currentUserUid ?? entry.authorUid
          : entry.authorUid,
      authorDisplayName: entry.authorDisplayName.isEmpty
          ? sync?.currentUserDisplayName ?? entry.authorDisplayName
          : entry.authorDisplayName,
    );
    final index = _entries.indexWhere((existing) => existing.id == stamped.id);
    final mutation = _nextMutation(stamped.id);
    if (index >= 0) {
      _entries[index] = stamped;
    } else {
      _entries.add(stamped);
    }
    final snapshot = PrescoutEntry.fromJson(stamped.toJson());
    final saved = _enqueueSave(snapshot);
    notifyListeners();
    if (!await saved) {
      _rollback(
        stamped.id,
        mutation,
        'Could not save the prescout entry for team ${stamped.teamNumber}.',
      );
      return false;
    }
    if (sync != null) {
      unawaited(sync.push(snapshot));
    }
    return true;
  }

  Future<bool> deleteEntry(String id) async {
    final existing = _entries.firstWhere(
      (entry) => entry.id == id,
      orElse: () => _placeholderEntry,
    );
    if (identical(existing, _placeholderEntry)) return true;
    final mutation = _nextMutation(id);
    _entries.removeWhere((entry) => entry.id == id);
    final deleted = _enqueueDelete(id);

    final wasSynced = _remoteSyncedIds.remove(id);
    if (wasSynced) {
      _persistSyncedIds();
    }
    notifyListeners();
    if (!await deleted) {
      if (wasSynced) {
        _remoteSyncedIds.add(id);
        _persistSyncedIds();
      }
      _rollback(
        id,
        mutation,
        'Could not delete the prescout entry for team ${existing.teamNumber}.',
      );
      return false;
    }
    final sync = _syncService;
    if (sync != null) {
      unawaited(sync.delete(existing));
    }
    return true;
  }

  Future<void> syncNow() async {
    await _syncService?.syncNow();
  }

  Future<void> _mergeRemote(List<PrescoutEntry> remote) async {
    var changed = false;
    var syncedChanged = false;
    final remoteIds = <String>{};
    for (final incoming in remote) {
      remoteIds.add(incoming.id);
      if (_remoteSyncedIds.add(incoming.id)) {
        syncedChanged = true;
      }

      _confirmed[incoming.id] = incoming;
      final index = _entries.indexWhere((local) => local.id == incoming.id);
      if (index < 0) {
        _nextMutation(incoming.id);
        _entries.add(incoming);
        _enqueueSave(incoming);
        changed = true;
        continue;
      }
      final existing = _entries[index];
      if (incoming.updatedAt.isAfter(existing.updatedAt)) {
        _nextMutation(incoming.id);
        _entries[index] = incoming;
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
      final before = _entries.length;
      _entries.removeWhere((entry) => entry.id == id);
      if (_entries.length != before) {
        _nextMutation(id);
        _enqueueDelete(id);
        changed = true;
      }
    }
    if (syncedChanged) {
      _persistSyncedIds();
    }
    if (changed) {
      notifyListeners();
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
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (confirmed == null) {
      if (index >= 0) _entries.removeAt(index);
    } else if (index >= 0) {
      _entries[index] = confirmed;
    } else {
      _entries.add(confirmed);
    }
    notifyListeners();
  }

  Future<bool> _enqueueSave(PrescoutEntry entry) {
    final result = _saveQueue
        .then((_) => _storage.saveEntry(entry))
        .then(
          (_) {
            _confirmed[entry.id] = entry;
            if (failedWrites.recordSuccess()) notifyListeners();
            return true;
          },
          onError: (Object e) {
            debugPrint('Prescout entry save failed: $e');
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
        .then((_) => _storage.deleteEntry(id))
        .then(
          (_) {
            _confirmed.remove(id);
            if (failedWrites.recordSuccess()) notifyListeners();
            return true;
          },
          onError: (Object e) {
            debugPrint('Prescout entry delete failed: $e');
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
          (Object e) => debugPrint('Prescout synced-id save failed: $e'),
        );
  }

  static final PrescoutEntry _placeholderEntry = PrescoutEntry(
    id: '__missing__',
    teamNumber: 0,
  );

  @override
  void dispose() {
    _remoteSubscription?.cancel();
    _statusSubscription?.cancel();
    _syncService?.dispose();
    super.dispose();
  }
}
