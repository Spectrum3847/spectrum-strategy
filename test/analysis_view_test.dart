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

Widget _hostTeam(
  ScoutingController controller,
  int teamNumber, {
  PitScoutingController? pitScoutingController,
  PitScoutConfigController? pitScoutConfigController,
}) {
  final config = ScoutConfigController(service: FakeScoutConfigService());
  return MaterialApp(
    home: TeamAnalysisScreen(
      controller: controller,
      configController: config,
      teamNumber: teamNumber,
      pitScoutingController: pitScoutingController,
      pitScoutConfigController: pitScoutConfigController,
    ),
  );
}

void main() {
  testWidgets('compare flow picks an opponent and shows both teams', (
    tester,
  ) async {
    final controller = await _seed([
      _entry(254, teleop: 50),
      _entry(1678, teleop: 20),
    ]);

    await tester.pumpWidget(_hostTeam(controller, 254));
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

  testWidgets('backing out of the opponent picker does not navigate', (
    tester,
  ) async {
    final controller = await _seed([
      _entry(254, teleop: 50),
      _entry(1678, teleop: 20),
    ]);

    await tester.pumpWidget(_hostTeam(controller, 254));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    expect(find.text('Compare Team 254 with'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Compare Team 254 with'), findsNothing);
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
        fieldValues: const {'launcherType': 'Flywheel'},
      ),
    );
    final pitConfigController = PitScoutConfigController(
      service: FakePitScoutConfigService(),
    );
    await pitConfigController.bootstrap();

    await tester.pumpWidget(
      _hostTeam(
        controller,
        254,
        pitScoutingController: pitController,
        pitScoutConfigController: pitConfigController,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pit scouting'), findsOneWidget);

    expect(find.text('Launcher Type'), findsOneWidget);
  });

  testWidgets('no pit summary section when no controller is wired', (
    tester,
  ) async {
    final controller = await _seed([_entry(254, teleop: 50)]);

    await tester.pumpWidget(_hostTeam(controller, 254));
    await tester.pumpAndSettle();

    expect(find.text('Pit scouting'), findsNothing);
  });
}
