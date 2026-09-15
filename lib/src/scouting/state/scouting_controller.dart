import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../state/failed_write_tracker.dart';
import '../models/accuracy_alert.dart';
import '../models/scout_entry.dart';
import '../services/accuracy_alert_service.dart';
import '../services/scouting_storage.dart';
import '../services/scouting_sync_service.dart';

enum ScanImportResult { imported, duplicate }

class ScoutingController extends ChangeNotifier {
  ScoutingController({
    ScoutingStorage? storage,
    this._syncService,
    this._alertService,
  }) : _storage = storage ?? SharedPreferencesScoutingStorage();

  final ScoutingStorage _storage;
  final ScoutingSyncService? _syncService;
  final AccuracyAlertService? _alertService;
  Future<void>? _bootstrapFuture;
  Future<void> _saveQueue = Future<void>.value();
  final List<ScoutEntry> _entries = <ScoutEntry>[];

  final Set<String> _remoteSyncedIds = <String>{};

  final Map<String, int> _mutations = <String, int>{};

  final Map<String, ScoutEntry> _confirmed = <String, ScoutEntry>{};

  String? _lastError;

  final FailedWriteTracker failedWrites = FailedWriteTracker();
  bool _ready = false;
  StreamSubscription<List<ScoutEntry>>? _remoteSubscription;
  StreamSubscription<ScoutingSyncStatus>? _statusSubscription;
  StreamSubscription<List<AccuracyAlert>>? _alertSubscription;
  ScoutingSyncStatus _syncStatus = const ScoutingSyncStatus(
    state: ScoutingSyncState.signedOut,
  );

  int _entriesRevision = 0;
  int get entriesRevision => _entriesRevision;

  bool get isReady => _ready;
  List<ScoutEntry> get entries => List<ScoutEntry>.unmodifiable(_entries);
  ScoutingSyncService? get syncService => _syncService;
  ScoutingSyncStatus get syncStatus => _syncStatus;

  String? get lastError => _lastError;

  void clearLastError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  List<AccuracyAlert> get pendingAlerts =>
      _alertService?.pendingAlerts ?? const <AccuracyAlert>[];

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
    _entriesRevision++;
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

    final alerts = _alertService;
    if (alerts != null) {
      _alertSubscription = alerts.alertsStream.listen((_) {
        notifyListeners();
      });
      try {
        await alerts.initialize();
      } catch (_) {}
    }
  }

  List<ScoutEntry> entriesForMatch(String matchId) {
    return _entries.where((entry) => entry.matchId == matchId).toList();
  }

  ScoutEntry? findEntry({required String matchId, required int teamNumber}) {
    for (final entry in _entries) {
      if (entry.matchId == matchId && entry.teamNumber == teamNumber) {
        return entry;
      }
    }
    return null;
  }

  Future<bool> saveEntry(ScoutEntry entry) async {
    final stamped = entry.copyWith(updatedAt: DateTime.now().toUtc());
    final index = _entries.indexWhere((existing) => existing.id == stamped.id);
    final mutation = _nextMutation(stamped.id);
    if (index >= 0) {
      _entries[index] = stamped;
    } else {
      _entries.add(stamped);
    }
    final snapshot = ScoutEntry.fromJson(stamped.toJson());
    final saved = _enqueueSave(snapshot);
    _entriesRevision++;
    notifyListeners();
    if (!await saved) {
      _rollback(
        stamped.id,
        mutation,
        'Could not save the entry for team ${stamped.teamNumber}.',
      );
      return false;
    }
    final sync = _syncService;
    if (sync != null) {
      unawaited(sync.push(snapshot));
    }
    return true;
  }

  Future<ScanImportResult> importScannedEntry(ScoutEntry entry) async {
    final signature = entry.contentSignature;
    final isDuplicate = _entries.any((e) => e.contentSignature == signature);
    if (isDuplicate) {
      return ScanImportResult.duplicate;
    }
    await saveEntry(entry.copyWith(id: 'scan-${_stableHash(signature)}'));
    return ScanImportResult.imported;
  }

  static String _stableHash(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
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
    _entriesRevision++;
    notifyListeners();
    if (!await deleted) {
      if (wasSynced) {
        _remoteSyncedIds.add(id);
        _persistSyncedIds();
      }
      _rollback(
        id,
        mutation,
        'Could not delete the entry for team ${existing.teamNumber}.',
      );
      return false;
    }
    final sync = _syncService;
    if (sync != null) {
      unawaited(sync.delete(existing));
    }
    return true;
  }

  Future<void> saveNow() async {
    await _saveQueue;
  }

  Future<void> syncNow() async {
    await _syncService?.syncNow();
  }

  Future<void> acknowledgeAlert(String entryId) async {
    await _alertService?.acknowledge(entryId);
  }

  void _mergeRemote(List<ScoutEntry> remote) {
    var changed = false;
    var syncedChanged = false;
    final remoteIds = <String>{};

    final toSave = <ScoutEntry>[];
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
        toSave.add(incoming);
        changed = true;
        continue;
      }
      final existing = _entries[index];
      if (incoming.updatedAt.isAfter(existing.updatedAt)) {
        _nextMutation(incoming.id);
        _entries[index] = incoming;
        toSave.add(incoming);
        changed = true;
      }
    }
    if (toSave.isNotEmpty) {
      _enqueueSaveMany(toSave);
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
      _entriesRevision++;
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
    _entriesRevision++;
    notifyListeners();
  }

  Future<bool> _enqueueSave(ScoutEntry entry) {
    final result = _saveQueue
        .then((_) => _storage.saveEntry(entry))
        .then(
          (_) {
            _confirmed[entry.id] = entry;
            if (failedWrites.recordSuccess()) notifyListeners();
            return true;
          },
          onError: (Object e) {
            debugPrint('Scout entry save failed: $e');
            failedWrites.recordFailure();
            notifyListeners();
            return false;
          },
        );
    _saveQueue = result;
    return result;
  }

  Future<bool> _enqueueSaveMany(List<ScoutEntry> entries) {
    final result = _saveQueue
        .then((_) => _storage.saveEntries(entries))
        .then(
          (_) {
            for (final entry in entries) {
              _confirmed[entry.id] = entry;
            }
            if (failedWrites.recordSuccess()) notifyListeners();
            return true;
          },
          onError: (Object e) {
            debugPrint('Scout entry batch save failed: $e');
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
            debugPrint('Scout entry delete failed: $e');
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
          (Object e) => debugPrint('Scout synced-id save failed: $e'),
        );
  }

  static final ScoutEntry _placeholderEntry = ScoutEntry(
    id: '__missing__',
    matchId: '',
    teamNumber: 0,
  );

  @override
  void dispose() {
    _remoteSubscription?.cancel();
    _statusSubscription?.cancel();
    _alertSubscription?.cancel();
    _syncService?.dispose();
    _alertService?.dispose();
    super.dispose();
  }
}
