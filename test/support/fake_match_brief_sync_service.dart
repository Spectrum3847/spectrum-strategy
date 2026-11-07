import 'dart:async';

import 'package:spectrumstrategy/src/models/match_brief.dart';
import 'package:spectrumstrategy/src/services/match_brief_sync_service.dart';

class FakeMatchBriefSyncService implements MatchBriefSyncService {
  FakeMatchBriefSyncService({this.uid = 'lead-uid', this.displayName = 'Lead'});

  final String uid;
  final String displayName;

  final _statusController = StreamController<MatchBriefSyncStatus>.broadcast();
  final _remoteController = StreamController<List<MatchBrief>>.broadcast();

  MatchBriefSyncStatus _status = const MatchBriefSyncStatus(
    state: MatchBriefSyncState.synced,
  );

  final List<MatchBrief> pushes = <MatchBrief>[];

  @override
  Stream<MatchBriefSyncStatus> get statusStream => _statusController.stream;

  @override
  MatchBriefSyncStatus get status => _status;

  @override
  Stream<List<MatchBrief>> get remoteBriefsStream => _remoteController.stream;

  @override
  String? get currentUserUid => uid;

  @override
  String? get currentUserDisplayName => displayName;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> push(MatchBrief brief) async {
    pushes.add(brief);
    _status = const MatchBriefSyncStatus(state: MatchBriefSyncState.synced);
    _statusController.add(_status);
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _remoteController.close();
  }

  void emitRemote(List<MatchBrief> briefs) => _remoteController.add(briefs);
}
