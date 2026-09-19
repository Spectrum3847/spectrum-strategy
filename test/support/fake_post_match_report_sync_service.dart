import 'dart:async';

import 'package:spectrumstrategy/src/models/post_match_report.dart';
import 'package:spectrumstrategy/src/services/post_match_report_sync_service.dart';

class FakePostMatchReportSyncService implements PostMatchReportSyncService {
  FakePostMatchReportSyncService({
    this.uid = 'uid-1',
    this.displayName = 'Lead',
    PostMatchReportSyncState initialState = PostMatchReportSyncState.synced,
  }) {
    _status = PostMatchReportSyncStatus(state: initialState);
  }

  final String uid;
  final String displayName;

  final _statusController =
      StreamController<PostMatchReportSyncStatus>.broadcast();
  final _remoteController = StreamController<List<PostMatchReport>>.broadcast();

  PostMatchReportSyncStatus _status = const PostMatchReportSyncStatus(
    state: PostMatchReportSyncState.synced,
  );

  final List<PostMatchReport> pushes = <PostMatchReport>[];

  Object? failNextPush;

  bool disposed = false;
  int initializeCalls = 0;

  @override
  Stream<PostMatchReportSyncStatus> get statusStream =>
      _statusController.stream;

  @override
  PostMatchReportSyncStatus get status => _status;

  @override
  Stream<List<PostMatchReport>> get remoteReportsStream =>
      _remoteController.stream;

  @override
  String? get currentUserUid => uid;

  @override
  String? get currentUserDisplayName => displayName;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> push(PostMatchReport report) async {
    final failure = failNextPush;
    if (failure != null) {
      failNextPush = null;
      throw failure;
    }
    pushes.add(report);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _statusController.close();
    await _remoteController.close();
  }

  void emitRemote(List<PostMatchReport> reports) =>
      _remoteController.add(reports);

  void emitStatus(PostMatchReportSyncStatus next) {
    _status = next;
    _statusController.add(next);
  }
}
