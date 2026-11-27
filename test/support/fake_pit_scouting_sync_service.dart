import 'dart:async';

import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_scouting_sync_service.dart';

class FakePitScoutingSyncService implements PitScoutingSyncService {
  FakePitScoutingSyncService({
    PitScoutingSyncState initialState = PitScoutingSyncState.synced,
    this._currentUserUid,
    this._currentUserDisplayName,
  }) {
    _status = PitScoutingSyncStatus(state: initialState);
  }

  final StreamController<PitScoutingSyncStatus> _statusController =
      StreamController<PitScoutingSyncStatus>.broadcast();
  final StreamController<List<PitScoutEntry>> _remoteController =
      StreamController<List<PitScoutEntry>>.broadcast();

  PitScoutingSyncStatus _status = const PitScoutingSyncStatus(
    state: PitScoutingSyncState.synced,
  );
  String? _currentUserUid;
  String? _currentUserDisplayName;

  final List<PitScoutEntry> pushed = <PitScoutEntry>[];
  final List<PitScoutEntry> deleted = <PitScoutEntry>[];
  int initializeCalls = 0;
  int syncNowCalls = 0;

  bool simulateOutage = false;

  bool simulateRejection = false;

  @override
  Stream<PitScoutingSyncStatus> get statusStream => _statusController.stream;

  @override
  PitScoutingSyncStatus get status => _status;

  @override
  Stream<List<PitScoutEntry>> get remoteEntriesStream =>
      _remoteController.stream;

  @override
  String? get currentUserUid => _currentUserUid;

  @override
  String? get currentUserDisplayName => _currentUserDisplayName;

  void setCurrentUser({String? uid, String? displayName}) {
    _currentUserUid = uid;
    _currentUserDisplayName = displayName;
  }

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> push(PitScoutEntry entry) async {
    if (simulateRejection) {
      emitStatus(
        const PitScoutingSyncStatus(
          state: PitScoutingSyncState.rejected,
          error: 'permission-denied: push rejected',
        ),
      );
      return;
    }
    if (simulateOutage) {
      emitStatus(
        const PitScoutingSyncStatus(
          state: PitScoutingSyncState.offline,
          error: 'push failed',
        ),
      );
      return;
    }
    pushed.add(entry);
    emitStatus(const PitScoutingSyncStatus(state: PitScoutingSyncState.synced));
  }

  @override
  Future<void> delete(PitScoutEntry entry) async {
    if (simulateRejection) {
      emitStatus(
        const PitScoutingSyncStatus(
          state: PitScoutingSyncState.rejected,
          error: 'permission-denied: delete rejected',
        ),
      );
      return;
    }
    if (simulateOutage) {
      emitStatus(
        const PitScoutingSyncStatus(
          state: PitScoutingSyncState.offline,
          error: 'delete failed',
        ),
      );
      return;
    }
    deleted.add(entry);
    emitStatus(const PitScoutingSyncStatus(state: PitScoutingSyncState.synced));
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

  void emitRemote(List<PitScoutEntry> entries) {
    _remoteController.add(entries);
  }

  void emitStatus(PitScoutingSyncStatus next) {
    _status = next;
    _statusController.add(next);
  }
}
