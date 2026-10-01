import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:statbotics_client/statbotics_client.dart';

import '../../services/analytics_service.dart';
import '../../services/match_id_resolver.dart';
import '../../state/failed_write_tracker.dart';
import '../models/accuracy_alert.dart';
import '../models/scout_entry.dart';
import '../models/scout_schedule.dart';
import '../services/accuracy_alert_service.dart';
import '../services/scouting_storage.dart';
import '../services/scouting_sync_service.dart';

enum ScanImportResult { imported, duplicate }

class ScoutingController extends ChangeNotifier {
  ScoutingController({
    ScoutingStorage? storage,
    this._syncService,
    this._alertService,
    AnalyticsService? analytics,
  }) : _storage = storage ?? SharedPreferencesScoutingStorage(),
       _analytics = analytics ?? const NoopAnalyticsService();

  final ScoutingStorage _storage;
  final ScoutingSyncService? _syncService;
  final AccuracyAlertService? _alertService;

  final AnalyticsService _analytics;
  Future<void>? _bootstrapFuture;
  Future<void> _saveQueue = Future<void>.value();
  final List<ScoutEntry> _entries = <ScoutEntry>[];

  final Set<String> _remoteSyncedIds = <String>{};

  final Set<String> _rejectedIds = <String>{};

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

  bool _repushInFlight = false;
  bool _repushPending = false;

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
        final previousState = _syncStatus.state;
        _syncStatus = status;
        notifyListeners();

        if (!_repushInFlight &&
            status.state == ScoutingSyncState.synced &&
            previousState != ScoutingSyncState.synced) {
          unawaited(_repushUnsynced());
        }
      });
      _remoteSubscription = sync.remoteEntriesStream.listen(_mergeRemote);
      _syncStatus = sync.status;
      try {
        await sync.initialize();
      } catch (_) {
        // Intentionally empty.
      }

      if (_syncStatus.state == ScoutingSyncState.synced) {
        unawaited(_repushUnsynced());
      }
    }

    final alerts = _alertService;
    if (alerts != null) {
      _alertSubscription = alerts.alertsStream.listen((_) {
        notifyListeners();
      });
      try {
        await alerts.initialize();
      } catch (_) {
        // Intentionally empty.
      }
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
    _analytics.capture('scout_entry_saved');
    final sync = _syncService;
    if (sync != null) {
      unawaited(
        sync.push(snapshot).then((status) {
          _recordSyncOutcome(snapshot.id, status);
        }),
      );
    }
    return true;
  }

  Future<void> backfillMatchKeys(Iterable<StatboticsMatch> matches) async {
    if (matches.isEmpty) return;
    final resolver = MatchIdResolver(matches);

    final unresolved = _entries
        .where((entry) => entry.tbaMatchKey == null)
        .toList(growable: false);
    for (final entry in unresolved) {
      final typed = entry.fieldValues['matchNumber']?.toString().trim() ?? '';
      if (typed.isEmpty) continue;
      final station = entry.fieldValues['robot']?.toString().trim() ?? '';
      final match = resolver.resolveWithTiebreak(
        typed,
        station: station,
        teamNumber: entry.teamNumber,
      );
      if (match == null) continue;
      await saveEntry(entry.copyWith(tbaMatchKey: match.key));
    }
  }

  static String stationOf(Map<String, dynamic> fieldValues) {
    final robot = fieldValues['robot']?.toString().trim() ?? '';
    if (robot.isNotEmpty) return robot;
    for (final value in fieldValues.values) {
      if (value is Map) {
        final position = value['robotPosition']?.toString().trim() ?? '';
        if (position.isNotEmpty) return position;
      }
    }
    return '';
  }

  int? nextMatchNumberFor({
    required String station,
    required Iterable<StatboticsMatch> schedule,
  }) {
    final qualMatches = schedule.where((m) => m.compLevel == 'qm').toList();
    if (qualMatches.isEmpty) return null;
    final numberByKey = <String, int>{
      for (final m in qualMatches) m.key.toLowerCase(): m.matchNumber,
    };
    final numbers = qualMatches.map((m) => m.matchNumber).toSet().toList()
      ..sort();

    final wanted = ScoutSchedule.normalizeStation(station);

    if (wanted == null) return null;
    final stationsByNumber = <int, Set<String>>{};
    final savedForStation = <int>{};
    for (final entry in _entries) {
      final key = entry.tbaMatchKey?.toLowerCase();
      if (key == null) continue;
      final n = numberByKey[key];
      if (n == null) continue;
      final entryStation = ScoutSchedule.normalizeStation(
        stationOf(entry.fieldValues),
      );

      if (entryStation == null) continue;
      stationsByNumber.putIfAbsent(n, () => <String>{}).add(entryStation);
      if (entryStation == wanted) savedForStation.add(n);
    }

    int? floor;
    for (final MapEntry(key: n, value: stations) in stationsByNumber.entries) {
      final corroborated = stations.length >= 2;
      if ((corroborated || savedForStation.contains(n)) &&
          (floor == null || n > floor)) {
        floor = n;
      }
    }

    if (floor == null) return numbers.first;
    for (final n in numbers) {
      if (n >= floor && !savedForStation.contains(n)) return n;
    }
    return null;
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
      unawaited(
        sync.delete(existing).then((status) {
          _recordSyncOutcome(id, status);
        }),
      );
    }
    return true;
  }

  void _recordSyncOutcome(String id, ScoutingSyncStatus? status) {
    if (status == null) return;
    if (status.state == ScoutingSyncState.rejected) {
      _rejectedIds.add(id);
      failedWrites.recordFailure();
      _analytics.capture('sync_failed');
      notifyListeners();
    } else if (status.state == ScoutingSyncState.synced) {
      _rejectedIds.remove(id);
      if (failedWrites.recordSuccess()) notifyListeners();
      _analytics.capture('sync_succeeded');
    }
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

      _rejectedIds.remove(incoming.id);
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

  Future<void> _repushUnsynced() async {
    if (_repushInFlight) {
      _repushPending = true;
      return;
    }
    _repushInFlight = true;
    try {
      do {
        _repushPending = false;
        final sync = _syncService;
        if (sync == null) return;

        final targetIds = _entries
            .where(
              (entry) =>
                  !_remoteSyncedIds.contains(entry.id) &&
                  !_rejectedIds.contains(entry.id),
            )
            .map((entry) => entry.id)
            .toSet();
        if (targetIds.isEmpty) continue;

        await _saveQueue;
        for (final id in targetIds) {
          final index = _entries.indexWhere((entry) => entry.id == id);
          if (index < 0) continue;
          final snapshot = ScoutEntry.fromJson(_entries[index].toJson());
          _recordSyncOutcome(id, await sync.push(snapshot));
        }
      } while (_repushPending);
    } finally {
      _repushInFlight = false;
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
