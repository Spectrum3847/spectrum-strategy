import 'dart:async';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_sync_service.dart';

class FakeScoutingSyncService implements ScoutingSyncService {
  FakeScoutingSyncService({
    ScoutingSyncState initialState = ScoutingSyncState.synced,
  }) {
    _status = ScoutingSyncStatus(state: initialState);
  }

  final StreamController<ScoutingSyncStatus> _statusController =
      StreamController<ScoutingSyncStatus>.broadcast();
  final StreamController<List<ScoutEntry>> _remoteController =
      StreamController<List<ScoutEntry>>.broadcast();

  ScoutingSyncStatus _status = const ScoutingSyncStatus(
    state: ScoutingSyncState.synced,
  );

  final List<ScoutEntry> pushed = <ScoutEntry>[];
  final List<ScoutEntry> deleted = <ScoutEntry>[];
  int initializeCalls = 0;
  int syncNowCalls = 0;

  bool simulateOutage = false;

  bool simulateRejection = false;

  @override
  Stream<ScoutingSyncStatus> get statusStream => _statusController.stream;

  @override
  ScoutingSyncStatus get status => _status;

  @override
  Stream<List<ScoutEntry>> get remoteEntriesStream => _remoteController.stream;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<ScoutingSyncStatus?> push(ScoutEntry entry) async {
    if (simulateRejection) {
      return _emitRejected('permission-denied: push rejected');
    }
    if (simulateOutage) {
      return _emitOffline('push failed');
    }
    pushed.add(entry);
    return _emitSynced();
  }

  @override
  Future<ScoutingSyncStatus?> delete(ScoutEntry entry) async {
    if (simulateRejection) {
      return _emitRejected('permission-denied: delete rejected');
    }
    if (simulateOutage) {
      return _emitOffline('delete failed');
    }
    deleted.add(entry);
    return _emitSynced();
  }

  ScoutingSyncStatus _emitOffline(String error) {
    final next = ScoutingSyncStatus(
      state: ScoutingSyncState.offline,
      error: error,
    );
    emitStatus(next);
    return next;
  }

  ScoutingSyncStatus _emitRejected(String error) {
    final next = ScoutingSyncStatus(
      state: ScoutingSyncState.rejected,
      error: error,
    );
    emitStatus(next);
    return next;
  }

  ScoutingSyncStatus _emitSynced() {
    const next = ScoutingSyncStatus(state: ScoutingSyncState.synced);
    emitStatus(next);
    return next;
  }

  @override
  Future<void> syncNow() async {
    syncNowCalls++;
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _remoteController.close();
  }

  void emitRemote(List<ScoutEntry> entries) {
    _remoteController.add(entries);
  }

  void emitStatus(ScoutingSyncStatus next) {
    _status = next;
    _statusController.add(next);
  }
}
