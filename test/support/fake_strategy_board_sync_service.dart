import 'dart:async';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/services/strategy_board_sync_service.dart';

class FakeStrategyBoardSyncService implements StrategyBoardSyncService {
  final List<StrategySession> pushed = <StrategySession>[];
  final List<String> deleted = <String>[];
  int syncNowCalls = 0;
  bool disposed = false;

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

  @override
  Future<void> initialize() async {}

  @override
  Future<void> push(StrategySession session) async => pushed.add(session);

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
