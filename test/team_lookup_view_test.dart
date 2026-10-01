import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/team_lookup_view.dart';

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

Future<ScoutConfigController> _config() async {
  final controller = ScoutConfigController(service: FakeScoutConfigService());
  await controller.bootstrap();
  return controller;
}

Widget _host({
  required ScoutingController scoutingController,
  required ScoutConfigController configController,
}) {
  return MaterialApp(
    home: Scaffold(
      body: TeamLookupView(
        scoutingController: scoutingController,
        configController: configController,
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a prompt until a team number is typed', (tester) async {
    final scouting = await _seed(const <ScoutEntry>[]);
    await _pump(
      tester,
      _host(scoutingController: scouting, configController: await _config()),
    );

    expect(find.textContaining('Type a team number'), findsOneWidget);
  });

  testWidgets('typing a team number shows its summary and history', (
    tester,
  ) async {
    final scouting = await _seed([
      ScoutEntry(
        matchId: 'qm1',
        teamNumber: 254,
        authorDisplayName: 'Alexandria',
        createdAt: DateTime.utc(2026, 3, 1, 10),
        fieldValues: const <String, dynamic>{
          'matchNumber': 1,
          'teleopFuelScored': 30,
          'autoFuelScored': 5,
          'eLow': 'Outpost',
          'comments': 'Fast cycles',
        },
      ),
      ScoutEntry(
        matchId: 'qm2',
        teamNumber: 254,
        createdAt: DateTime.utc(2026, 3, 1, 10, 5),
        fieldValues: const <String, dynamic>{
          'matchNumber': 2,
          'teleopFuelScored': 40,
        },
      ),
    ]);
    await _pump(
      tester,
      _host(scoutingController: scouting, configController: await _config()),
    );

    await tester.enterText(find.byType(TextField), '254');
    await tester.pumpAndSettle();

    expect(find.text('Team 254'), findsOneWidget);
    expect(find.text('35'), findsWidgets);

    expect(find.text('Match Number'), findsOneWidget);
    expect(find.text('Comments'), findsOneWidget);
    expect(find.text('Fast cycles'), findsOneWidget);

    expect(find.textContaining('Alexandria'), findsNothing);

    final matchOneCenter = tester.getCenter(find.text('1').first);
    final matchTwoCenter = tester.getCenter(find.text('2').first);
    expect(matchOneCenter.dy, lessThan(matchTwoCenter.dy));
  });

  testWidgets('typing a different team number replaces everything', (
    tester,
  ) async {
    final scouting = await _seed([
      ScoutEntry(
        matchId: 'qm1',
        teamNumber: 254,
        fieldValues: const <String, dynamic>{'comments': 'Team 254 note'},
      ),
      ScoutEntry(
        matchId: 'qm1',
        teamNumber: 1323,
        fieldValues: const <String, dynamic>{'comments': 'Team 1323 note'},
      ),
    ]);
    await _pump(
      tester,
      _host(scoutingController: scouting, configController: await _config()),
    );

    await tester.enterText(find.byType(TextField), '254');
    await tester.pumpAndSettle();
    expect(find.text('Team 254'), findsOneWidget);
    expect(find.textContaining('Team 254 note'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1323');
    await tester.pumpAndSettle();
    expect(find.text('Team 1323'), findsOneWidget);
    expect(find.text('Team 254'), findsNothing);
    expect(find.textContaining('Team 254 note'), findsNothing);
    expect(find.textContaining('Team 1323 note'), findsOneWidget);
  });

  testWidgets('a team with no entries shows an empty history message', (
    tester,
  ) async {
    final scouting = await _seed(const <ScoutEntry>[]);
    await _pump(
      tester,
      _host(scoutingController: scouting, configController: await _config()),
    );

    await tester.enterText(find.byType(TextField), '3847');
    await tester.pumpAndSettle();

    expect(find.text('Team 3847'), findsOneWidget);
    expect(find.textContaining('No scouting entries recorded'), findsOneWidget);
  });

  testWidgets("shows the searched team's own summary numbers, not the "
      'lowest-numbered scouted team', (tester) async {
    final scouting = await _seed([
      ScoutEntry(
        matchId: 'qm1',
        teamNumber: 100,
        fieldValues: const <String, dynamic>{'teleopFuelScored': 10},
      ),
      ScoutEntry(
        matchId: 'qm1',
        teamNumber: 200,
        fieldValues: const <String, dynamic>{'teleopFuelScored': 90},
      ),
    ]);
    await _pump(
      tester,
      _host(scoutingController: scouting, configController: await _config()),
    );

    await tester.enterText(find.byType(TextField), '200');
    await tester.pumpAndSettle();

    expect(find.text('Team 200'), findsOneWidget);
    expect(find.text('90'), findsWidgets);
    expect(find.text('10'), findsNothing);
  });

  testWidgets('orders history by match number, not by createdAt', (
    tester,
  ) async {
    final scouting = await _seed([
      ScoutEntry(
        matchId: 'qm2',
        teamNumber: 254,
        createdAt: DateTime.utc(2026, 3, 1, 10),
        fieldValues: const <String, dynamic>{'matchNumber': 2},
      ),
      ScoutEntry(
        matchId: 'qm1',
        teamNumber: 254,
        createdAt: DateTime.utc(2026, 3, 1, 10, 5),
        fieldValues: const <String, dynamic>{'matchNumber': 1},
      ),
    ]);
    await _pump(
      tester,
      _host(scoutingController: scouting, configController: await _config()),
    );

    await tester.enterText(find.byType(TextField), '254');
    await tester.pumpAndSettle();

    final matchOneCenter = tester.getCenter(find.text('1').first);
    final matchTwoCenter = tester.getCenter(find.text('2').first);
    expect(matchOneCenter.dy, lessThan(matchTwoCenter.dy));
  });

  testWidgets(
    'the spreadsheet shows every scouted field, including team and match '
    'identity columns',
    (tester) async {
      final scouting = await _seed([
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 3847,
          fieldValues: const <String, dynamic>{
            'pTnumber': 3847,
            'matchNumber': 1,
            'robot': 'Red 1',
            'teleopFuelScored': 20,
          },
        ),
      ]);
      await _pump(
        tester,
        _host(scoutingController: scouting, configController: await _config()),
      );

      await tester.enterText(find.byType(TextField), '3847');
      await tester.pumpAndSettle();

      expect(find.text('Team Number'), findsOneWidget);
      expect(find.text('Match Number'), findsOneWidget);
      expect(find.text('Robot Driver Station'), findsOneWidget);
      expect(find.text('Fuel Scored'), findsOneWidget);
    },
  );

  testWidgets('recomputes live when a new entry is saved after render', (
    tester,
  ) async {
    final scouting = await _seed([
      ScoutEntry(
        matchId: 'qm1',
        teamNumber: 254,
        fieldValues: const <String, dynamic>{'comments': 'First entry'},
      ),
    ]);
    await _pump(
      tester,
      _host(scoutingController: scouting, configController: await _config()),
    );

    await tester.enterText(find.byType(TextField), '254');
    await tester.pumpAndSettle();
    expect(find.text('Scouting history (1)'), findsOneWidget);
    expect(find.textContaining('Second entry'), findsNothing);

    await scouting.saveEntry(
      ScoutEntry(
        matchId: 'qm2',
        teamNumber: 254,
        fieldValues: const <String, dynamic>{'comments': 'Second entry'},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scouting history (2)'), findsOneWidget);
    expect(find.textContaining('Second entry'), findsOneWidget);
  });

  testWidgets(
    'scopes the history to the selected event, keeping entries with no '
    'event key (mirrors the Database tab rule)',
    (tester) async {
      final scouting = await _seed([
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 254,
          tbaMatchKey: '2026txhou_qm1',
          fieldValues: const <String, dynamic>{'comments': 'This event'},
        ),
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 254,
          tbaMatchKey: '2026txdal_qm1',
          fieldValues: const <String, dynamic>{'comments': 'Other event'},
        ),
        ScoutEntry(
          matchId: 'qm2',
          teamNumber: 254,
          fieldValues: const <String, dynamic>{'comments': 'No event key'},
        ),
      ]);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final event = EventController(client: _FakeStatboticsClient());
      await event.setEventKey('2026txhou');
      await _pump(
        tester,
        MaterialApp(
          home: Scaffold(
            body: TeamLookupView(
              scoutingController: scouting,
              configController: await _config(),
              eventController: event,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '254');
      await tester.pumpAndSettle();

      expect(find.text('Scouting history (2)'), findsOneWidget);
      expect(find.textContaining('This event'), findsOneWidget);
      expect(find.textContaining('No event key'), findsOneWidget);
      expect(find.textContaining('Other event'), findsNothing);
    },
  );

  testWidgets(
    'a fixed Notes column at the end shows ScoutEntry.notes, separate from '
    'any comments field value',
    (tester) async {
      final scouting = await _seed([
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 254,
          notes: 'Admin-edited note',
          fieldValues: const <String, dynamic>{'comments': 'Scouted comment'},
        ),
      ]);
      await _pump(
        tester,
        _host(scoutingController: scouting, configController: await _config()),
      );

      await tester.enterText(find.byType(TextField), '254');
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Admin-edited note'), findsOneWidget);
      expect(find.text('Scouted comment'), findsOneWidget);
    },
  );

  testWidgets(
    'a stored team number of 0 falls back to ScoutEntry.teamNumber, same as '
    'a missing one',
    (tester) async {
      final scouting = await _seed([
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 3847,
          fieldValues: const <String, dynamic>{'pTnumber': 0},
        ),
      ]);
      await _pump(
        tester,
        _host(scoutingController: scouting, configController: await _config()),
      );

      await tester.enterText(find.byType(TextField), '3847');
      await tester.pumpAndSettle();

      expect(find.text('0'), findsNothing);
      expect(find.text('3847'), findsWidgets);
    },
  );
}

class _FakeStatboticsClient extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async =>
      StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async =>
      const <StatboticsTeamEvent>[];

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async =>
      const <StatboticsMatch>[];
}
