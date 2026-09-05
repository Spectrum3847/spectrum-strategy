import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/app.dart';
import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_assignment.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_assignment_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/prescout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/prescouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_assignment_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_shift_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/shift_trade_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/cycle_log_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/event_sections_controller.dart';
import 'package:spectrumstrategy/src/state/event_stats_controller.dart';
import 'package:spectrumstrategy/src/state/pick_list_controller.dart';
import 'package:spectrumstrategy/src/state/post_match_report_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/state/theme_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';
import 'package:spectrumstrategy/src/state/playoff_board_controller.dart';

import 'support/fake_cycle_log_storage.dart';
import 'support/fake_match_directory.dart';
import 'support/fake_pit_scout_config_service.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_post_match_report_storage.dart';
import 'support/fake_post_match_report_sync_service.dart';
import 'support/fake_prescout_config_service.dart';
import 'support/fake_prescouting_storage.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_scout_shift_sync_service.dart';
import 'support/fake_shift_trade_sync_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';
import 'support/fake_playoff_board_storage.dart';

class _FakeAssignmentSyncService implements ScoutAssignmentSyncService {
  @override
  Stream<List<ScoutAssignment>> watchAll() =>
      const Stream<List<ScoutAssignment>>.empty();

  @override
  Future<void> upsert(ScoutAssignment assignment) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> dispose() async {}
}

class _FailingOnceDirectory extends FakeMatchDirectory {
  bool failNextActiveIdRead = true;

  @override
  Future<String?> getActiveMatchId() async {
    if (failNextActiveIdRead) {
      failNextActiveIdRead = false;
      throw StateError('simulated storage failure');
    }
    return super.getActiveMatchId();
  }
}

void main() {
  testWidgets('bootstrap failure shows the error screen and retry recovers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final directory = _FailingOnceDirectory();
    await directory.saveMatch(StrategySession.create(id: 'stored'));
    final auth = FakeSpectrumAuthService();

    await tester.pumpWidget(
      StrategyApp(
        strategyController: StrategyController(directory: directory),
        scoutingController: ScoutingController(storage: FakeScoutingStorage()),
        configController: ScoutConfigController(
          service: FakeScoutConfigService(),
        ),
        authService: auth,
        themeController: ThemeController(),
        userRoleController: UserRoleController(
          authService: auth,
          roleService: FakeUserRoleService(),
        ),
        eventController: EventController(),
        pickListController: PickListController(),
        eventStatsController: EventStatsController(tbaClient: null),
        eventSectionsController: EventSectionsController(tbaClient: null),
        assignmentController: ScoutAssignmentController(
          syncService: _FakeAssignmentSyncService(),
        ),
        pitScoutConfigController: PitScoutConfigController(
          service: FakePitScoutConfigService(),
        ),
        pitScoutingController: PitScoutingController(
          storage: FakePitScoutingStorage(),
        ),
        prescoutConfigController: PrescoutConfigController(
          service: FakePrescoutConfigService(),
        ),
        prescoutingController: PrescoutingController(
          storage: FakePrescoutingStorage(),
        ),
        cycleLogController: CycleLogController(storage: FakeCycleLogStorage()),
        playoffBoardController: PlayoffBoardController(
          storage: FakePlayoffBoardStorage(),
        ),
        postMatchReportController: PostMatchReportController(
          storage: FakePostMatchReportStorage(),
          syncService: FakePostMatchReportSyncService(),
        ),
        shiftController: ScoutShiftController(
          syncService: FakeScoutShiftSyncService(),
        ),
        shiftTradeController: ShiftTradeController(
          syncService: FakeShiftTradeSyncService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spectrum Strategy could not start'), findsOneWidget);
    expect(find.textContaining('simulated storage failure'), findsOneWidget);

    final retry = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Try again'),
    );
    retry.onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Spectrum Strategy could not start'), findsNothing);
    expect(find.text('You are signed out.'), findsOneWidget);
  });
}
