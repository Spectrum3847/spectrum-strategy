import 'dart:async';

import 'package:spectrumstrategy/src/models/pick_list.dart';
import 'package:spectrumstrategy/src/services/pick_list_sync_service.dart';

class FakePickListSyncService implements PickListSyncService {
  FakePickListSyncService({
    PickListSyncState initialState = PickListSyncState.synced,
    this._currentUserUid,
    this._currentUserDisplayName,
  }) {
    _status = PickListSyncStatus(state: initialState);
  }

  final StreamController<PickListSyncStatus> _statusController =
      StreamController<PickListSyncStatus>.broadcast();
  final StreamController<List<PickList>> _remoteController =
      StreamController<List<PickList>>.broadcast();

  PickListSyncStatus _status = const PickListSyncStatus(
    state: PickListSyncState.synced,
  );
  String? _currentUserUid;
  String? _currentUserDisplayName;

  final List<PickList> pushed = <PickList>[];
  final List<PickList> deleted = <PickList>[];
  final List<(PickList, int)> teamAdds = <(PickList, int)>[];
  final List<(PickList, int)> teamRemoves = <(PickList, int)>[];
  int initializeCalls = 0;
  int syncNowCalls = 0;

  @override
  Stream<PickListSyncStatus> get statusStream => _statusController.stream;

  @override
  PickListSyncStatus get status => _status;

  @override
  Stream<List<PickList>> get remoteListsStream => _remoteController.stream;

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
  Future<void> push(PickList list) async {
    pushed.add(list);
  }

  @override
  Future<void> pushTeamAdd(PickList list, int team) async {
    teamAdds.add((list, team));
  }

  @override
  Future<void> pushTeamRemove(PickList list, int team) async {
    teamRemoves.add((list, team));
  }

  @override
  Future<void> delete(PickList list) async {
    deleted.add(list);
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

  void emitRemote(List<PickList> lists) {
    if (!_remoteController.isClosed) {
      _remoteController.add(lists);
    }
  }

  void emitStatus(PickListSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }
}
