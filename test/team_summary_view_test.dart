import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/team_summary_view.dart';

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

ScoutEntry _entry(
  int team, {
  String match = 'qm1',
  Map<String, dynamic> fieldValues = const <String, dynamic>{},
}) {
  return ScoutEntry(matchId: match, teamNumber: team, fieldValues: fieldValues);
}

Widget _host({
  required ScoutingController scoutingController,
  required ScoutConfigController configController,
}) {
  return MaterialApp(
    home: Scaffold(
      body: TeamSummaryView(
        scoutingController: scoutingController,
        configController: configController,
        eventController: EventController(),
      ),
    ),
  );
}

void main() {
  Future<ScoutConfigController> config() async {
    final controller = ScoutConfigController(service: FakeScoutConfigService());
    await controller.bootstrap();
    return controller;
  }

  testWidgets('shows the empty state with no teams and no entries', (
    tester,
  ) async {
    final scouting = await _seed(const <ScoutEntry>[]);
    await tester.pumpWidget(
      _host(scoutingController: scouting, configController: await config()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No teams to summarize'), findsOneWidget);
  });

  testWidgets('lists a team scouted for teleop fuel and its rate columns', (
    tester,
  ) async {
    final scouting = await _seed([
      _entry(
        254,
        fieldValues: {
          'teleopFuelScored': 30,
          'autoFuelScored': 5,
          'eLow': 'Outpost',
        },
      ),
    ]);
    await tester.pumpWidget(
      _host(scoutingController: scouting, configController: await config()),
    );
    await tester.pumpAndSettle();

    expect(find.text('254'), findsOneWidget);
    expect(find.text('30'), findsWidgets);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('a team with no data at all shows dashes, not zeros', (
    tester,
  ) async {
    final scouting = await _seed([_entry(254)]);
    await tester.pumpWidget(
      _host(scoutingController: scouting, configController: await config()),
    );
    await tester.pumpAndSettle();

    expect(find.text('254'), findsOneWidget);
    expect(find.text('--'), findsWidgets);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('recomputes live as a new scout entry lands', (tester) async {
    final scouting = await _seed([
      _entry(254, fieldValues: {'teleopFuelScored': 10}),
    ]);
    await tester.pumpWidget(
      _host(scoutingController: scouting, configController: await config()),
    );
    await tester.pumpAndSettle();
    expect(find.text('10'), findsWidgets);

    await scouting.saveEntry(
      _entry(254, match: 'qm2', fieldValues: {'teleopFuelScored': 90}),
    );
    await tester.pumpAndSettle();

    expect(find.text('50'), findsWidgets);
  });
}
