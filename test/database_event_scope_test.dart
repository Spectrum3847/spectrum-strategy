import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';

void main() {
  Future<ScoutingController> pumpWith(
    WidgetTester tester, {
    required List<ScoutEntry> entries,
    required EventController event,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await scouting.bootstrap();
    await config.bootstrap();
    for (final entry in entries) {
      await scouting.saveEntry(entry);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatabaseTab(
            scoutingController: scouting,
            configController: config,
            eventController: event,
            canEditAnyEntry: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return scouting;
  }

  ScoutEntry entry({required int team, String? tbaMatchKey}) {
    return ScoutEntry(
      matchId: 'session-uuid',
      teamNumber: team,
      tbaMatchKey: tbaMatchKey,
      fieldValues: <String, dynamic>{'pTnumber': team},
    );
  }

  testWidgets('shows only the selected event, plus unattributed entries', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final event = EventController(client: _FakeStatboticsClient());
    await event.setEventKey('2026txhou');

    await pumpWith(
      tester,
      event: event,
      entries: [
        entry(team: 100, tbaMatchKey: '2026txhou_qm1'),
        entry(team: 200, tbaMatchKey: '2026gapea_qm1'),

        entry(team: 300),
      ],
    );

    expect(find.text('100'), findsOneWidget);
    expect(find.text('200'), findsNothing);
    expect(find.text('300'), findsOneWidget);
  });

  testWidgets('switching the selected event switches the table contents', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final event = EventController(client: _FakeStatboticsClient());
    await event.setEventKey('2026txhou');

    final scouting = await pumpWith(
      tester,
      event: event,
      entries: [
        entry(team: 100, tbaMatchKey: '2026txhou_qm1'),
        entry(team: 200, tbaMatchKey: '2026gapea_qm1'),
      ],
    );

    expect(find.text('100'), findsOneWidget);
    expect(find.text('200'), findsNothing);

    await event.setEventKey('2026gapea');
    await tester.pumpAndSettle();

    expect(find.text('100'), findsNothing);
    expect(find.text('200'), findsOneWidget);

    expect(scouting.entries, hasLength(2));
  });

  testWidgets('All events reaches a past event\'s entries', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final event = EventController(client: _FakeStatboticsClient());
    await event.setEventKey('2026txhou');

    await pumpWith(
      tester,
      event: event,
      entries: [
        entry(team: 100, tbaMatchKey: '2026txhou_qm1'),
        entry(team: 200, tbaMatchKey: '2026gapea_qm1'),
      ],
    );

    expect(find.text('200'), findsNothing);

    await tester.tap(find.textContaining('This event', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<bool>, 'All events'));
    await tester.pumpAndSettle();

    expect(find.text('100'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);

    await tester.tap(find.textContaining('All events', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<bool>, 'This event'));
    await tester.pumpAndSettle();

    expect(find.text('200'), findsNothing);
  });

  testWidgets('no scope control when no event is selected', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await pumpWith(
      tester,
      event: EventController(client: _FakeStatboticsClient()),
      entries: [entry(team: 100, tbaMatchKey: '2026txhou_qm1')],
    );

    expect(find.textContaining('This event', findRichText: true), findsNothing);
    expect(find.text('100'), findsOneWidget);
  });
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
    return const <StatboticsMatch>[];
  }

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async {
    return const <StatboticsTeamBasic>[];
  }
}
