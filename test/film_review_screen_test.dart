import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/cycle_log.dart';
import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/state/cycle_log_controller.dart';
import 'package:spectrumstrategy/src/state/post_match_report_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/ui/film_review_screen.dart';

import 'support/fake_cycle_log_storage.dart';
import 'support/fake_match_directory.dart';
import 'support/fake_post_match_report_storage.dart';
import 'support/fake_post_match_report_sync_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

void main() {
  Future<ScoutingController> readyScoutingController() async {
    final controller = ScoutingController(storage: FakeScoutingStorage());
    await controller.bootstrap();
    await controller.saveEntry(ScoutEntry(matchId: 'qm14', teamNumber: 3847));
    await controller.saveEntry(ScoutEntry(matchId: 'qm14', teamNumber: 254));
    return controller;
  }

  Future<PostMatchReportController> readyReportController() async {
    final controller = PostMatchReportController(
      storage: FakePostMatchReportStorage(),
      syncService: FakePostMatchReportSyncService(),
    );
    await controller.bootstrap();
    return controller;
  }

  Future<UserRoleController> readyRoles() async {
    const user = SpectrumUser(uid: 'lead-uid', displayName: 'Lead');
    final roleService = FakeUserRoleService()
      ..setRoles('lead-uid', <UserRole>{UserRole.strategy});
    final roles = UserRoleController(
      authService: FakeSpectrumAuthService(initialUser: user),
      roleService: roleService,
    );
    await roles.bootstrap();
    return roles;
  }

  testWidgets('the report action opens the post match report for the match', (
    tester,
  ) async {
    final scouting = await readyScoutingController();
    final reportController = await readyReportController();
    final roles = await readyRoles();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: FilmReviewScreen(
          scoutingController: scouting,
          eventKey: '2026miket',
          postMatchReportController: reportController,
          userRoleController: roles,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Match qm14'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Post match report'), findsOneWidget);

    await tester.tap(find.byTooltip('Post match report'));
    await tester.pumpAndSettle();

    expect(find.text('Match qm14 report'), findsOneWidget);

    scouting.dispose();
    reportController.dispose();
  });

  testWidgets('the report action is hidden with no controller wired', (
    tester,
  ) async {
    final scouting = await readyScoutingController();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: FilmReviewScreen(scoutingController: scouting),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Match qm14'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Post match report'), findsNothing);

    scouting.dispose();
  });

  testWidgets(
    'shows the strategy board section when a matchDirectory is wired',
    (tester) async {
      final scouting = await readyScoutingController();
      final directory = FakeMatchDirectory();
      final session = StrategySession.create(id: 'qm14')
        ..teamNumbers.addAll(<int>[3847, 254]);
      await directory.saveMatch(session);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: FilmReviewScreen(
            scoutingController: scouting,
            matchDirectory: directory,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Match qm14'));
      await tester.pumpAndSettle();

      expect(find.text('Strategy board'), findsOneWidget);
      expect(find.text('Teams: 3847, 254'), findsOneWidget);

      scouting.dispose();
    },
  );

  testWidgets('hides the strategy board section with no matchDirectory wired', (
    tester,
  ) async {
    final scouting = await readyScoutingController();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: FilmReviewScreen(scoutingController: scouting),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Match qm14'));
    await tester.pumpAndSettle();

    expect(find.text('Strategy board'), findsNothing);

    scouting.dispose();
  });

  testWidgets('a failed cycle log write shows the pill', (tester) async {
    final scouting = await readyScoutingController();
    final storage = FakeCycleLogStorage();
    final cycleLog = CycleLogController(storage: storage);
    await cycleLog.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: FilmReviewScreen(
          scoutingController: scouting,
          cycleLogController: cycleLog,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Match qm14'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not saved'), findsNothing);

    storage.failNextSave = StateError('offline');
    await cycleLog.recordEvent(
      matchKey: 'qm14',
      team: 3847,
      kind: CycleEventKind.intake,
      offsetMs: 0,
      phase: StrategyPhase.teleop,
    );
    await tester.pumpAndSettle();

    expect(find.text('1 edit not saved'), findsOneWidget);

    await cycleLog.recordEvent(
      matchKey: 'qm14',
      team: 3847,
      kind: CycleEventKind.score,
      offsetMs: 1000,
      phase: StrategyPhase.teleop,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('not saved'), findsNothing);

    scouting.dispose();
    cycleLog.dispose();
  });
}
