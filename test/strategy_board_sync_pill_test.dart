import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/services/strategy_board_sync_service.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/ui/strategy_tab.dart';

import 'support/fake_match_directory.dart';
import 'support/fake_strategy_board_sync_service.dart';

class _FailingSaveDirectory extends FakeMatchDirectory {
  bool failSaves = false;

  @override
  Future<void> saveMatch(StrategySession session) async {
    if (failSaves) throw StateError('disk full');
    await super.saveMatch(session);
  }
}

void main() {
  testWidgets('a local save failure shows even when the push was rejected', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final directory = _FailingSaveDirectory();
    final sync = FakeStrategyBoardSyncService()..simulateRejection = true;
    final strategy = StrategyController(
      directory: directory,
      syncService: sync,
    );
    await strategy.bootstrap();

    directory.failSaves = true;
    await strategy.saveNow();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StrategyTab(
            controller: strategy,
            eventController: EventController(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.state<StrategyTabState>(find.byType(StrategyTab)).openMatchPicker();
    await tester.pumpAndSettle();

    expect(strategy.syncStatus.state, StrategyBoardSyncState.rejected);
    expect(find.text('1 edit not saved'), findsOneWidget);
    expect(find.text('Not accepted'), findsNothing);

    strategy.dispose();
    await tester.pumpAndSettle();
  });
}
