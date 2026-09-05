import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/ui/analysis_view.dart';

import 'support/fake_pit_photo_store.dart';
import 'support/fake_pit_scout_config_service.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';

Future<ScoutingController> _seed(List<ScoutEntry> entries) async {
  final controller = ScoutingController(storage: FakeScoutingStorage());
  await controller.bootstrap();
  for (final entry in entries) {
    await controller.saveEntry(entry);
  }
  return controller;
}

ScoutEntry _entry(int team, {required int teleop, String match = 'qm1'}) {
  return ScoutEntry(
    matchId: match,
    teamNumber: team,
    byPhase: {StrategyPhase.teleop: ScoutPhaseData(score: teleop)},
  );
}

Widget _host(ScoutingController controller) {
  final config = ScoutConfigController(service: FakeScoutConfigService());
  return MaterialApp(
    home: Scaffold(
      body: AnalysisView(controller: controller, configController: config),
    ),
  );
}

void main() {
  testWidgets('lists teams ranked by IQM total score', (tester) async {
    final controller = await _seed([
      _entry(1678, teleop: 20),
      _entry(254, teleop: 50),
    ]);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.text('Team 254'), findsOneWidget);
    expect(find.text('Team 1678'), findsOneWidget);
    expect(find.text('Ranked by IQM total score'), findsOneWidget);

    final y254 = tester.getTopLeft(find.text('Team 254')).dy;
    final y1678 = tester.getTopLeft(find.text('Team 1678')).dy;
    expect(y254, lessThan(y1678));
  });

  testWidgets('shows a teaching empty state with no entries', (tester) async {
    final controller = await _seed([]);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('No scouting data to analyze'), findsOneWidget);
  });

  testWidgets('tapping a team opens its analysis detail', (tester) async {
    final controller = await _seed([
      _entry(254, teleop: 50),
      _entry(1678, teleop: 20),
    ]);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Team 254'));
    await tester.pumpAndSettle();

    expect(find.text('IQM total score'), findsOneWidget);
    expect(find.text('Auton'), findsWidgets);
    expect(find.text('Teleop'), findsWidgets);
    expect(find.text('Endgame'), findsWidgets);
  });

  testWidgets('compare flow picks an opponent and shows both teams', (
    tester,
  ) async {
    final controller = await _seed([
      _entry(254, teleop: 50),
      _entry(1678, teleop: 20),
    ]);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Team 254'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();

    expect(find.text('Compare Team 254 with'), findsOneWidget);
    await tester.tap(find.text('Team 1678'));
    await tester.pumpAndSettle();

    expect(find.text('Compare teams'), findsOneWidget);
    expect(find.text('vs'), findsOneWidget);
    expect(find.text('Team 254'), findsWidgets);
    expect(find.text('Team 1678'), findsWidgets);
  });

  testWidgets('compare shortcut appears once two teams have entries', (
    tester,
  ) async {
    final controller = await _seed([
      _entry(254, teleop: 50),
      _entry(1678, teleop: 20),
    ]);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Compare'), findsOneWidget);
  });

  testWidgets('compare shortcut hidden with no entries', (tester) async {
    final controller = await _seed([]);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Compare'), findsNothing);
  });

  testWidgets('compare shortcut hidden with a single team', (tester) async {
    final controller = await _seed([_entry(254, teleop: 50)]);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Compare'), findsNothing);
  });

  testWidgets('compare shortcut picks both teams and shows them', (
    tester,
  ) async {
    final controller = await _seed([
      _entry(254, teleop: 50),
      _entry(1678, teleop: 20),
    ]);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();

    expect(find.text('Compare which team?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Team 254'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Team 254'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compare Team 254 with'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Team 254'),
      ),
      findsNothing,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Team 1678'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compare teams'), findsOneWidget);
    expect(find.text('vs'), findsOneWidget);
    expect(find.text('Team 254'), findsWidgets);
    expect(find.text('Team 1678'), findsWidgets);
  });

  testWidgets('backing out of the first picker does not navigate', (
    tester,
  ) async {
    final controller = await _seed([
      _entry(254, teleop: 50),
      _entry(1678, teleop: 20),
    ]);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    expect(find.text('Compare which team?'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Compare which team?'), findsNothing);
    expect(find.text('Compare teams'), findsNothing);
    expect(find.text('Compare'), findsOneWidget);
  });

  testWidgets("a team's pit summary shows on its detail screen", (
    tester,
  ) async {
    final controller = await _seed([_entry(254, teleop: 50)]);
    final pitController = PitScoutingController(
      storage: FakePitScoutingStorage(),
      photoStore: FakePitPhotoStore(),
    );
    await pitController.bootstrap();
    await pitController.saveEntry(
      PitScoutEntry(
        teamNumber: 254,
        authorUid: 'uid-1',
        fieldValues: const {'weightLbs': 120},
      ),
    );
    final pitConfigController = PitScoutConfigController(
      service: FakePitScoutConfigService(),
    );
    await pitConfigController.bootstrap();

    final config = ScoutConfigController(service: FakeScoutConfigService());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalysisView(
            controller: controller,
            configController: config,
            pitScoutingController: pitController,
            pitScoutConfigController: pitConfigController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Team 254'));
    await tester.pumpAndSettle();

    expect(find.text('Pit scouting'), findsOneWidget);

    expect(find.text('Weight (lbs)'), findsOneWidget);
  });

  testWidgets('no pit summary section when no controller is wired', (
    tester,
  ) async {
    final controller = await _seed([_entry(254, teleop: 50)]);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Team 254'));
    await tester.pumpAndSettle();

    expect(find.text('Pit scouting'), findsNothing);
  });

  testWidgets('backing out of the second picker does not navigate', (
    tester,
  ) async {
    final controller = await _seed([
      _entry(254, teleop: 50),
      _entry(1678, teleop: 20),
    ]);

    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Team 254'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Compare Team 254 with'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Compare Team 254 with'), findsNothing);
    expect(find.text('Compare teams'), findsNothing);
    expect(find.text('Compare'), findsOneWidget);
  });
}
