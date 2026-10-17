import 'dart:async';

import 'package:spectrumstrategy/src/models/trex_team_list.dart';
import 'package:spectrumstrategy/src/services/trex_team_list_sync_service.dart';

class FakeTRexTeamListSyncService implements TRexTeamListSyncService {
  FakeTRexTeamListSyncService({this.uid = 'uid-1', this.displayName = 'Lead'});

  final String uid;
  final String displayName;

  final _teamList = StreamController<TRexTeamList>.broadcast();

  final List<TRexTeamList> pushes = <TRexTeamList>[];

  Object? failNextPush;

  bool disposed = false;
  bool initialized = false;

  @override
  Stream<TRexTeamList> get teamListStream => _teamList.stream;

  @override
  String? get currentUserUid => uid;

  @override
  String? get currentUserDisplayName => displayName;

  TRexTeamList stored = TRexTeamList(
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  @override
  Future<void> initialize() async {
    initialized = true;
    _teamList.add(stored);
  }

  @override
  Future<void> push(TRexTeamList teamList) async {
    final failure = failNextPush;
    if (failure != null) {
      failNextPush = null;
      throw failure;
    }
    pushes.add(teamList);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _teamList.close();
  }

  void emit(TRexTeamList teamList) => _teamList.add(teamList);
}

class LaggyTRexTeamListSyncService extends FakeTRexTeamListSyncService {
  int _pushes = 0;

  @override
  Future<void> push(TRexTeamList teamList) async {
    final isFirst = _pushes++ == 0;
    if (isFirst) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return super.push(teamList);
  }
}
