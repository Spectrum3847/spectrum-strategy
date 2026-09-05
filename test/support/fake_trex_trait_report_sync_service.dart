import 'dart:async';

import 'package:spectrumstrategy/src/models/trex_trait_report.dart';
import 'package:spectrumstrategy/src/services/trex_trait_report_sync_service.dart';

class FakeTrexTraitReportSyncService implements TrexTraitReportSyncService {
  FakeTrexTraitReportSyncService({
    TrexTraitReportSyncState initialState = TrexTraitReportSyncState.synced,
  }) {
    _status = TrexTraitReportSyncStatus(state: initialState);
  }

  final StreamController<TrexTraitReportSyncStatus> _statusController =
      StreamController<TrexTraitReportSyncStatus>.broadcast();
  final StreamController<List<TrexTraitReport>> _remoteController =
      StreamController<List<TrexTraitReport>>.broadcast();

  TrexTraitReportSyncStatus _status = const TrexTraitReportSyncStatus(
    state: TrexTraitReportSyncState.synced,
  );

  final List<TrexTraitReport> pushed = <TrexTraitReport>[];
  int initializeCalls = 0;
  int syncNowCalls = 0;
  bool simulateOutage = false;

  @override
  Stream<TrexTraitReportSyncStatus> get statusStream =>
      _statusController.stream;

  @override
  TrexTraitReportSyncStatus get status => _status;

  @override
  Stream<List<TrexTraitReport>> get remoteReportsStream =>
      _remoteController.stream;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> push(TrexTraitReport report) async {
    if (simulateOutage) {
      emitStatus(
        TrexTraitReportSyncStatus(
          state: TrexTraitReportSyncState.offline,
          error: 'push failed',
        ),
      );
      return;
    }
    pushed.add(report);
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

  void emitRemote(List<TrexTraitReport> reports) {
    _remoteController.add(reports);
  }

  void emitStatus(TrexTraitReportSyncStatus next) {
    _status = next;
    _statusController.add(next);
  }
}
