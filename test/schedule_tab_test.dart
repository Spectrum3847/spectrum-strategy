import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/schedule_tab.dart';

const _testEventKey = '2026test';

Future<EventController> _pumpTab(
  WidgetTester tester, {
  bool selectEvent = true,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final event = EventController(
    statboticsEnabled: true,
    client: _FakeStatboticsClient(),
  );
  if (selectEvent) {
    await event.setEventKey(_testEventKey);
  }

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ScheduleTab(eventController: event)),
    ),
  );
  await tester.pumpAndSettle();
  return event;
}

void main() {
  testWidgets('points at Settings when no event is selected', (tester) async {
    await _pumpTab(tester, selectEvent: false);

    expect(find.textContaining('No event selected'), findsOneWidget);
    expect(find.textContaining('Settings'), findsOneWidget);

    expect(find.text('Select event'), findsNothing);
  });

  testWidgets('lists the schedule with team numbers and nicknames', (
    tester,
  ) async {
    await _pumpTab(tester);

    expect(find.text('Test Event'), findsOneWidget);
    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('Q2'), findsOneWidget);
    expect(find.text('Red'), findsNWidgets(3));
    expect(find.text('Blue'), findsNWidgets(3));
    expect(
      find.text('3847 Spectrum · 118 · 2056'),
      findsOneWidget,
      reason:
          'the red alliance line carries each team number plus its nickname '
          'when one is known',
    );
  });

  testWidgets('sorts qualification matches ahead of playoffs', (tester) async {
    await _pumpTab(tester);

    final q1 = tester.getTopLeft(find.text('Q1')).dy;
    final q2 = tester.getTopLeft(find.text('Q2')).dy;
    final f1 = tester.getTopLeft(find.text('F1')).dy;
    expect(q1, lessThan(q2));
    expect(q2, lessThan(f1));
  });

  testWidgets('searching the schedule by team number filters matches', (
    tester,
  ) async {
    await _pumpTab(tester);

    await tester.enterText(find.byType(TextField), '254');
    await tester.pumpAndSettle();

    expect(find.text('Q2'), findsOneWidget);
    expect(find.text('Q1'), findsNothing);
  });

  testWidgets('team segment indexes every team, searchable by name', (
    tester,
  ) async {
    await _pumpTab(tester);

    await tester.tap(find.text('Teams'));
    await tester.pumpAndSettle();

    expect(find.text('254'), findsOneWidget);
    expect(find.text('3847'), findsOneWidget);
    expect(find.text('Spectrum'), findsOneWidget);
    expect(
      find.text('Name unavailable'),
      findsOneWidget,
      reason: '971 has no nickname in the fake data',
    );

    await tester.enterText(find.byType(TextField), 'cheesy');
    await tester.pumpAndSettle();

    expect(find.text('254'), findsOneWidget);
    expect(find.text('3847'), findsNothing);
  });

  testWidgets('an empty search result explains itself', (tester) async {
    await _pumpTab(tester);

    await tester.enterText(find.byType(TextField), 'nothing here');
    await tester.pumpAndSettle();

    expect(find.textContaining('matches that search'), findsOneWidget);
  });
}

class _FakeStatboticsClient extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async {
    return StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);
  }

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async {
    return <StatboticsTeamEvent>[
      StatboticsTeamEvent(
        team: 3847,
        event: eventKey,
        eventName: 'Test Event',

        teamName: 'Spectrum',
        year: 2026,
        wins: 2,
        losses: 0,
        ties: 0,
        epa: StatboticsEpa.empty,
      ),
      StatboticsTeamEvent(
        team: 254,
        event: eventKey,
        eventName: 'Test Event',
        teamName: 'The Cheesy Poofs',
        year: 2026,
        wins: 2,
        losses: 0,
        ties: 0,
        epa: StatboticsEpa.empty,
      ),

      StatboticsTeamEvent(
        team: 971,
        event: eventKey,
        eventName: 'Test Event',
        year: 2026,
        wins: 1,
        losses: 1,
        ties: 0,
        epa: StatboticsEpa.empty,
      ),
    ];
  }

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    return <StatboticsMatch>[
      StatboticsMatch(
        key: '${eventKey}_f1m1',
        event: eventKey,
        matchNumber: 1,
        compLevel: 'f',
        redTeams: const <int>[3847, 971, 118],
        blueTeams: const <int>[254, 1323, 2056],
      ),
      StatboticsMatch(
        key: '${eventKey}_qm2',
        event: eventKey,
        matchNumber: 2,
        compLevel: 'qm',
        redTeams: const <int>[254, 118, 1323],
        blueTeams: const <int>[971, 2056, 33],
      ),
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

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async {
    return <StatboticsTeamBasic>[
      StatboticsTeamBasic(team: 3847, nickname: 'Spectrum'),
      StatboticsTeamBasic(team: 254, nickname: 'The Cheesy Poofs'),
    ];
  }
}
