import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/match_prediction_view.dart';
import 'package:statbotics_client/statbotics_client.dart';

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

Future<ScoutConfigController> _config() async {
  final controller = ScoutConfigController(service: FakeScoutConfigService());
  await controller.bootstrap();
  return controller;
}

class _FakeStatboticsClient extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async {
    return StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);
  }

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async {
    return const <StatboticsTeamEvent>[];
  }

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    return <StatboticsMatch>[
      StatboticsMatch(
        key: '${eventKey}_qm1',
        event: eventKey,
        matchNumber: 1,
        compLevel: 'qm',
        redTeams: const <int>[3847, 118, 2056],
        blueTeams: const <int>[971, 1323, 33],
      ),
    ];
  }
}

Future<EventController> _loadedEventController() async {
  final controller = EventController(
    statboticsEnabled: true,
    client: _FakeStatboticsClient(),
  );
  await controller.setEventKey('2026test');
  return controller;
}

Widget _host({
  required EventController eventController,
  required ScoutingController scoutingController,
  required ScoutConfigController configController,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MatchPredictionView(
        eventController: eventController,
        scoutingController: scoutingController,
        configController: configController,
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('shows the empty state until all six teams are filled in', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        eventController: await _loadedEventController(),
        scoutingController: await _seed(const <ScoutEntry>[]),
        configController: await _config(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Enter all three teams for each alliance'),
      findsOneWidget,
    );
  });

  testWidgets('typing six team numbers sums each alliance IQM total', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        eventController: await _loadedEventController(),
        scoutingController: await _seed([
          _entry(1, fieldValues: {'autoFuelScored': 4, 'teleopFuelScored': 10}),
          _entry(2, fieldValues: {'autoFuelScored': 2, 'teleopFuelScored': 8}),
          _entry(3, fieldValues: {'autoFuelScored': 0, 'teleopFuelScored': 6}),
        ]),
        configController: await _config(),
      ),
    );
    await tester.pumpAndSettle();

    final teamFields = find.widgetWithText(TextField, 'Team 1');
    expect(teamFields, findsNWidgets(2));

    await tester.enterText(find.byType(TextField).at(1), '1');
    await tester.enterText(find.byType(TextField).at(2), '2');
    await tester.enterText(find.byType(TextField).at(3), '3');
    await tester.enterText(find.byType(TextField).at(4), '4');
    await tester.enterText(find.byType(TextField).at(5), '5');
    await tester.enterText(find.byType(TextField).at(6), '6');
    await tester.pumpAndSettle();

    expect(find.text('30'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
  });

  testWidgets(
    'loading by match number fills both alliances from the schedule',
    (tester) async {
      await tester.pumpWidget(
        _host(
          eventController: await _loadedEventController(),
          scoutingController: await _seed(const <ScoutEntry>[]),
          configController: await _config(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Match number'),
        '1',
      );
      await tester.tap(find.text('Load match'));
      await tester.pumpAndSettle();

      for (final team in const ['3847', '118', '2056', '971', '1323', '33']) {
        expect(find.text(team), findsWidgets, reason: 'team $team missing');
      }
    },
  );

  testWidgets(
    'an unknown match number leaves the fields alone and shows an error',
    (tester) async {
      await tester.pumpWidget(
        _host(
          eventController: await _loadedEventController(),
          scoutingController: await _seed(const <ScoutEntry>[]),
          configController: await _config(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Match number'),
        '99',
      );
      await tester.tap(find.text('Load match'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No qualification match 99'), findsOneWidget);
    },
  );
}
