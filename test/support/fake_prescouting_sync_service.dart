import 'dart:async';

import 'package:spectrumstrategy/src/scouting/models/prescout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/prescouting_sync_service.dart';

class FakePrescoutingSyncService implements PrescoutingSyncService {
  FakePrescoutingSyncService({
    PrescoutingSyncState initialState = PrescoutingSyncState.synced,
    this._currentUserUid,
    this._currentUserDisplayName,
  }) {
    _status = PrescoutingSyncStatus(state: initialState);
  }

  final StreamController<PrescoutingSyncStatus> _statusController =
      StreamController<PrescoutingSyncStatus>.broadcast();
  final StreamController<List<PrescoutEntry>> _remoteController =
      StreamController<List<PrescoutEntry>>.broadcast();

  PrescoutingSyncStatus _status = const PrescoutingSyncStatus(
    state: PrescoutingSyncState.synced,
  );
  String? _currentUserUid;
  String? _currentUserDisplayName;

  final List<PrescoutEntry> pushed = <PrescoutEntry>[];
  final List<PrescoutEntry> deleted = <PrescoutEntry>[];
  int initializeCalls = 0;
  int syncNowCalls = 0;

  @override
  Stream<PrescoutingSyncStatus> get statusStream => _statusController.stream;

  @override
  PrescoutingSyncStatus get status => _status;

  @override
  Stream<List<PrescoutEntry>> get remoteEntriesStream =>
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
  Future<void> push(PrescoutEntry entry) async {
    pushed.add(entry);
  }

  @override
  Future<void> delete(PrescoutEntry entry) async {
    deleted.add(entry);
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

  void emitRemote(List<PrescoutEntry> entries) {
    _remoteController.add(entries);
  }

  void emitStatus(PrescoutingSyncStatus next) {
    _status = next;
    _statusController.add(next);
  }
}
