import 'dart:async';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/services/strategy_board_sync_service.dart';

class FakeStrategyBoardSyncService implements StrategyBoardSyncService {
  final List<StrategySession> pushed = <StrategySession>[];
  final List<String> deleted = <String>[];
  int syncNowCalls = 0;
  bool disposed = false;

  bool simulateOutage = false;

  bool simulateRejection = false;

  final StreamController<StrategyBoardSyncStatus> _statusController =
      StreamController<StrategyBoardSyncStatus>.broadcast();
  final StreamController<List<StrategySession>> _remoteController =
      StreamController<List<StrategySession>>.broadcast();

  @override
  StrategyBoardSyncStatus status = const StrategyBoardSyncStatus(
    state: StrategyBoardSyncState.synced,
  );

  @override
  Stream<StrategyBoardSyncStatus> get statusStream => _statusController.stream;

  @override
  Stream<List<StrategySession>> get remoteBoardsStream =>
      _remoteController.stream;

  void emitRemote(List<StrategySession> boards) =>
      _remoteController.add(boards);

  void emitStatus(StrategyBoardSyncStatus next) {
    status = next;
    _statusController.add(next);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> push(StrategySession session) async {
    if (simulateRejection) {
      emitStatus(
        const StrategyBoardSyncStatus(
          state: StrategyBoardSyncState.rejected,
          error: 'permission-denied: push rejected',
        ),
      );
      return;
    }
    if (simulateOutage) {
      emitStatus(
        const StrategyBoardSyncStatus(
          state: StrategyBoardSyncState.offline,
          error: 'push failed',
        ),
      );
      return;
    }
    pushed.add(session);
    emitStatus(
      const StrategyBoardSyncStatus(state: StrategyBoardSyncState.synced),
    );
  }

  @override
  Future<void> delete(StrategySession session) async => deleted.add(session.id);

  @override
  Future<void> syncNow() async => syncNowCalls++;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _statusController.close();
    await _remoteController.close();
  }
}
