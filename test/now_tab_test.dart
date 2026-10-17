import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_shift_schedule.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_shift_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/now_tab.dart';

import 'support/fake_scout_shift_sync_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_scouting_sync_service.dart';

const _eventKey = '2026test';

class _Taps {
  final List<int> teams = <int>[];
  final List<String> preps = <String>[];
  final List<String> tabs = <String>[];
}

ScoutEntry _entry(int team, int match) => ScoutEntry(
  matchId: 'm$match',
  teamNumber: team,
  tbaMatchKey: '${_eventKey}_qm$match',
);

ScoutShiftSchedule _scheduleFor(String uid, int start, int end) {
  return ScoutShiftSchedule(
    eventKey: _eventKey,
    matchCount: 4,
    roster: [ScoutShiftRosterEntry(uid: uid, name: 'Sam')],
    rotations: [
      ScouterShiftRotation(
        uid: uid,
        name: 'Sam',
        shifts: [ScoutShiftBlock(startMatch: start, endMatch: end)],
      ),
    ],
  );
}

Future<_Taps> _pump(
  WidgetTester tester, {
  bool selectEvent = true,
  int? myTeam = 3847,
  bool lead = false,
  bool withDatabase = true,
  List<ScoutEntry>? entries,
  ScoutingSyncState syncState = ScoutingSyncState.synced,
  bool withShifts = false,
  ScoutShiftSchedule? storedShifts,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final event = EventController(client: _FakeStatboticsClient());
  if (selectEvent) await event.setEventKey(_eventKey);
  await event.setMyTeamNumber(myTeam);

  final sync = FakeScoutingSyncService(initialState: syncState);
  final scouting = ScoutingController(
    storage: FakeScoutingStorage(),
    syncService: sync,
  );
  await scouting.bootstrap();
  for (final entry in entries ?? [_entry(254, 2), _entry(118, 2)]) {
    await scouting.saveEntry(entry);
  }

  ScoutShiftController? shiftController;
  if (withShifts) {
    final shiftSync = FakeScoutShiftSyncService()..stored = storedShifts;
    shiftController = ScoutShiftController(syncService: shiftSync);
    addTearDown(shiftController.dispose);
  }

  final taps = _Taps();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NowTab(
          eventController: event,
          scoutingController: scouting,
          shiftController: shiftController,
          currentUid: 'scout-1',
          isLead: lead,
          onOpenTeam: taps.teams.add,
          onPrepMatch: (match) => taps.preps.add(match.displayName),
          onOpenScout: () => taps.tabs.add('scout'),
          onOpenSettings: () => taps.tabs.add('settings'),
          onOpenDatabase: withDatabase ? () => taps.tabs.add('database') : null,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return taps;
}

void main() {
  group('our next match', () {
    testWidgets('names the match, how far away it is, and both alliances', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Test Event'), findsOneWidget);
      expect(find.text('Scouted through Q2'), findsOneWidget);
      expect(find.text('Q4'), findsOneWidget);
      expect(find.text('1 match away'), findsOneWidget);
      expect(find.text('Partners'), findsOneWidget);
      expect(find.text('Opponents'), findsOneWidget);

      expect(find.text('Red'), findsOneWidget);
      expect(find.text('Blue'), findsOneWidget);
    });

    testWidgets('partner and opponent numbers open that team', (tester) async {
      final taps = await _pump(tester);

      await tester.tap(find.text('118'));
      await tester.tap(find.text('971'));
      await tester.pump();

      expect(taps.teams, [118, 971]);
      expect(find.text('3847'), findsNothing);
    });

    testWidgets('Prep opens the match', (tester) async {
      final taps = await _pump(tester);

      await tester.tap(find.text('Prep'));

      expect(taps.preps, ['Q4']);
    });

    testWidgets('says so when scouting has not shown how far along it is', (
      tester,
    ) async {
      await _pump(tester, entries: const <ScoutEntry>[]);

      expect(find.text('Q1'), findsOneWidget);
      expect(find.text('Progress unknown'), findsOneWidget);
      expect(find.text('No scouted matches yet'), findsOneWidget);
    });

    testWidgets('reads as done once every one of our matches is played', (
      tester,
    ) async {
      await _pump(tester, entries: [_entry(254, 4), _entry(971, 4)]);

      expect(find.text('Prep'), findsNothing);
      expect(
        find.text('Team 3847 has played all 2 qualification matches.'),
        findsOneWidget,
      );
    });

    testWidgets('asks for a team number when none is set', (tester) async {
      final taps = await _pump(tester, myTeam: null);

      expect(
        find.text('Set your team number in Settings to see your next match.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open Settings'));
      expect(taps.tabs, ['settings']);
    });

    testWidgets('points at Settings when no event is selected', (tester) async {
      final taps = await _pump(tester, selectEvent: false);

      expect(find.textContaining('No event selected'), findsOneWidget);
      await tester.tap(find.text('Open Settings'));
      expect(taps.tabs, ['settings']);
    });
  });

  group('your scouting', () {
    testWidgets('a scout sees their shift first, with a Start button', (
      tester,
    ) async {
      final taps = await _pump(
        tester,
        withShifts: true,
        storedShifts: _scheduleFor('scout-1', 5, 10),
      );

      expect(find.text('Q5 to Q10'), findsOneWidget);
      expect(find.text('2 matches away'), findsOneWidget);
      final shiftTop = tester.getTopLeft(find.text('Your scouting')).dy;
      final matchTop = tester.getTopLeft(find.text('Our next match')).dy;
      expect(shiftTop, lessThan(matchTop));

      await tester.tap(find.text('Start'));
      expect(taps.tabs, ['scout']);
    });

    testWidgets('a lead sees the match before their shift', (tester) async {
      await _pump(
        tester,
        lead: true,
        withShifts: true,
        storedShifts: _scheduleFor('scout-1', 3, 4),
      );

      expect(find.text('On duty now'), findsOneWidget);
      final shiftTop = tester.getTopLeft(find.text('Your scouting')).dy;
      final matchTop = tester.getTopLeft(find.text('Our next match')).dy;
      expect(matchTop, lessThan(shiftTop));
    });

    testWidgets('a scout with no shift is told, and can open Scout', (
      tester,
    ) async {
      final taps = await _pump(
        tester,
        withShifts: true,
        storedShifts: _scheduleFor('someone-else', 5, 10),
      );

      expect(
        find.text('No scouting shift is assigned to you.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open Scout'));
      expect(taps.tabs, ['scout']);
    });

    testWidgets('a lead with no shift sees no scouting section', (
      tester,
    ) async {
      await _pump(tester, lead: true, withShifts: true);

      expect(find.text('Your scouting'), findsNothing);
    });

    testWidgets('a scout is told when no shifts exist for the event', (
      tester,
    ) async {
      await _pump(tester, withShifts: true);

      expect(
        find.text('No scouting shifts are set up for this event yet.'),
        findsOneWidget,
      );
    });
  });

  group('needs attention', () {
    testWidgets('lists unsynced entries and links to Scout', (tester) async {
      final taps = await _pump(tester);

      expect(
        find.text('2 scouting entries have not synced yet.'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining('have not synced'));
      expect(taps.tabs, ['scout']);
    });

    testWidgets('a lead sees played matches with unscouted robots', (
      tester,
    ) async {
      final taps = await _pump(tester, lead: true);

      expect(find.text('10 robots not scouted in Q1, Q2.'), findsOneWidget);
      await tester.tap(find.textContaining('not scouted in'));
      expect(taps.tabs, ['database']);
    });

    testWidgets('a scout does not see the coverage alert', (tester) async {
      await _pump(tester);

      expect(find.textContaining('not scouted in'), findsNothing);
    });

    testWidgets('is quiet when there is nothing to do', (tester) async {
      await _pump(tester, entries: const <ScoutEntry>[], lead: true);

      expect(find.text('Nothing right now.'), findsOneWidget);
    });

    testWidgets('says when the device is offline', (tester) async {
      await _pump(
        tester,
        entries: const <ScoutEntry>[],
        syncState: ScoutingSyncState.offline,
      );

      expect(find.textContaining('Offline.'), findsOneWidget);
      expect(find.textContaining('sync when you are back'), findsOneWidget);
    });
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
        wins: 0,
        losses: 0,
        ties: 0,
        epa: StatboticsEpa.empty,
      ),
    ];
  }

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    StatboticsMatch qual(int n, List<int> red, List<int> blue) {
      return StatboticsMatch(
        key: '${eventKey}_qm$n',
        event: eventKey,
        matchNumber: n,
        compLevel: 'qm',
        redTeams: red,
        blueTeams: blue,
      );
    }

    return <StatboticsMatch>[
      qual(4, const [3847, 118, 2056], const [254, 971, 1323]),
      qual(3, const [1114, 118, 2056], const [254, 971, 1323]),
      qual(2, const [254, 118, 1323], const [971, 2056, 33]),
      qual(1, const [3847, 118, 2056], const [971, 1323, 33]),
    ];
  }

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async {
    return <StatboticsTeamBasic>[
      StatboticsTeamBasic(team: 3847, nickname: 'Spectrum'),
    ];
  }
}
