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
  Future<void> push(ScoutEntry entry) async {
    if (simulateRejection) {
      _emitRejected('permission-denied: push rejected');
      return;
    }
    if (simulateOutage) {
      _emitOffline('push failed');
      return;
    }
    pushed.add(entry);
    _emitSynced();
  }

  @override
  Future<void> delete(ScoutEntry entry) async {
    if (simulateRejection) {
      _emitRejected('permission-denied: delete rejected');
      return;
    }
    if (simulateOutage) {
      _emitOffline('delete failed');
      return;
    }
    deleted.add(entry);
    _emitSynced();
  }

  void _emitOffline(String error) {
    emitStatus(
      ScoutingSyncStatus(state: ScoutingSyncState.offline, error: error),
    );
  }

  void _emitRejected(String error) {
    emitStatus(
      ScoutingSyncStatus(state: ScoutingSyncState.rejected, error: error),
    );
  }

  void _emitSynced() {
    emitStatus(const ScoutingSyncStatus(state: ScoutingSyncState.synced));
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
