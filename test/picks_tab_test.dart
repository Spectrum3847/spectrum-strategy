import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/models/pick_list.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/pick_list_controller.dart';
import 'package:spectrumstrategy/src/ui/picks_tab.dart';

import 'support/fake_pick_list_storage.dart';
import 'support/fake_pit_photo_store.dart';
import 'support/fake_pit_scout_config_service.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';

const _eventKey = '2026test';

class _FakeStatboticsClient extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async =>
      StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async {
    return <StatboticsTeamEvent>[
      for (var i = 0; i < 10; i++)
        StatboticsTeamEvent(
          team: 101 + i,
          event: eventKey,
          eventName: 'Test Event',
          year: 2026,
          wins: 0,
          losses: 0,
          ties: 0,
          epa: StatboticsEpa(totalPoints: 50.0 - i),
        ),
    ];
  }

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async =>
      <StatboticsMatch>[];

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async =>
      <StatboticsTeamBasic>[];
}

class _Harness {
  _Harness(this.pickLists, this.opened);

  final PickListController pickLists;
  final List<int> opened;

  PickList get list => pickLists.lists.single;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  List<int> teams = const [101, 102],
  int? myTeam,
  List<ScoutEntry> entries = const [],
  Size size = const Size(800, 2400),
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final event = EventController(client: _FakeStatboticsClient());
  await event.setEventKey(_eventKey);
  if (myTeam != null) await event.setMyTeamNumber(myTeam);

  final scouting = ScoutingController(storage: FakeScoutingStorage());
  await scouting.bootstrap();
  for (final entry in entries) {
    await scouting.saveEntry(entry);
  }
  final config = ScoutConfigController(service: FakeScoutConfigService());
  await config.bootstrap();

  final pit = PitScoutingController(
    storage: FakePitScoutingStorage(),
    photoStore: FakePitPhotoStore(),
  );
  await pit.bootstrap();
  await pit.saveEntry(
    PitScoutEntry(
      teamNumber: 101,
      authorUid: 'uid-1',
      fieldValues: const {'launcherType': 'Flywheel'},
    ),
  );
  final pitConfig = PitScoutConfigController(
    service: FakePitScoutConfigService(),
  );
  await pitConfig.bootstrap();

  final pickLists = PickListController(storage: FakePickListStorage());
  await pickLists.bootstrap();
  final created = await pickLists.create('Quals');
  for (final team in teams) {
    await pickLists.addTeam(created!.id, team);
  }

  final opened = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: PicksTab(
          pickListController: pickLists,
          eventController: event,
          scoutingController: scouting,
          configController: config,
          pitScoutingController: pit,
          pitScoutConfigController: pitConfig,
          onOpenTeam: opened.add,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(pickLists, opened);
}

List<List<int>> _tiers(PickList list) => [
  for (final t in list.layout.tiers) t.teams,
];

ScoutEntry _incident(
  int team,
  int match, {
  String card = 'None',
  bool died = false,
  String eventKey = _eventKey,
}) => ScoutEntry(
  matchId: '',
  teamNumber: team,
  tbaMatchKey: '${eventKey}_qm$match',
  fieldValues: <String, dynamic>{'ryCard': card, 'dieCard': died},
);

Future<void> _openMenu(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

void main() {
  group('pick list', () {
    testWidgets(
      'shows default tiers with each team stat and pit flags inline',
      (tester) async {
        await _pump(tester);

        expect(find.text('1st pick (2)'), findsOneWidget);
        expect(find.text('2nd pick (0)'), findsOneWidget);
        expect(find.text('Defense/role (0)'), findsOneWidget);
        expect(find.text('Backup (0)'), findsOneWidget);
        expect(find.text('Do not pick (0)'), findsOneWidget);
        expect(find.textContaining('Not scouted'), findsNWidgets(2));
        expect(find.textContaining('EPA 50.0'), findsOneWidget);
        expect(find.textContaining('Flywheel'), findsOneWidget);
      },
    );

    testWidgets('a team number opens that team', (tester) async {
      final h = await _pump(tester);

      await tester.tap(find.text('102'));

      expect(h.opened, [102]);
    });

    testWidgets('move buttons reorder, and cross into the next tier', (
      tester,
    ) async {
      final h = await _pump(tester);

      await tester.tap(find.byTooltip('Move 101 down'));
      await tester.pumpAndSettle();
      expect(h.list.teamNumbers, [102, 101]);

      await tester.tap(find.byTooltip('Move 101 down'));
      await tester.pumpAndSettle();
      expect(_tiers(h.list).take(2), [
        [102],
        [101],
      ]);
      expect(find.text('2nd pick (1)'), findsOneWidget);

      expect(h.list.teamNumbers, [102, 101]);
    });

    testWidgets('dragging the handle reorders a team', (tester) async {
      final h = await _pump(tester);

      final handle = find.byIcon(Icons.drag_indicator_rounded).first;
      await tester.timedDrag(
        handle,
        const Offset(0, 140),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();

      expect(h.list.teamNumbers, [102, 101]);
    });

    testWidgets('a team moves to another tier from its menu', (tester) async {
      final h = await _pump(tester);

      await _openMenu(tester, 'More for 102');
      await tester.tap(find.text('Move to Backup'));
      await tester.pumpAndSettle();

      expect(_tiers(h.list)[3], [102]);
    });

    testWidgets(
      'do not pick needs a reason, and keeps the team off the tiers',
      (tester) async {
        final h = await _pump(tester);

        await _openMenu(tester, 'More for 102');
        await tester.tap(find.text('Do not pick'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Do not pick'));
        await tester.pumpAndSettle();
        expect(
          find.text('Say why, so the drive team trusts it.'),
          findsOneWidget,
        );
        expect(h.list.dnp, isEmpty);

        await tester.enterText(
          find.byType(TextField),
          'Breaks down in playoffs',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Do not pick'));
        await tester.pumpAndSettle();

        expect(find.text('Do not pick (1)'), findsOneWidget);
        expect(find.text('Breaks down in playoffs'), findsOneWidget);
        expect(h.list.dnp.single.team, 102);
        expect(h.list.teamNumbers, [101]);
      },
    );

    testWidgets('adding a team checks it is at the event', (tester) async {
      final h = await _pump(tester);

      await tester.tap(find.byTooltip('Add team to 2nd pick'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.text('Team 9999 is not at this event.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '105');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(_tiers(h.list)[1], [105]);
    });

    testWidgets('a tier can be renamed', (tester) async {
      final h = await _pump(tester);

      await _openMenu(tester, 'Tier options for Backup');
      await tester.tap(find.text('Rename tier'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sleepers');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Sleepers (0)'), findsOneWidget);
      expect(h.list.tiers.last.name, 'Sleepers');
    });

    testWidgets('a list the MCP server wrote with no tiers still opens', (
      tester,
    ) async {
      final h = await _pump(tester, teams: const [101, 102, 103]);

      expect(h.list.tiers, isEmpty);
      expect(find.text('1st pick (3)'), findsOneWidget);
    });
  });

  group('do-not-pick suggestions', () {
    final carded = [
      _incident(103, 16, card: 'Red'),
      _incident(104, 9, card: 'Yellow'),
      _incident(104, 55, died: true),
      _incident(105, 4, card: 'Yellow'),
      _incident(106, 2, card: 'Red', eventKey: '2026other'),
    ];

    testWidgets('suggests a red card or two incidents, worst first', (
      tester,
    ) async {
      await _pump(tester, entries: carded);

      expect(find.text('Suggested (2)'), findsOneWidget);
      expect(find.text('Red card Q16'), findsOneWidget);
      expect(find.text('Yellow card Q9 · died Q55'), findsOneWidget);

      expect(find.byKey(const ValueKey('dnp-suggested-105')), findsNothing);
      expect(find.byKey(const ValueKey('dnp-suggested-106')), findsNothing);
      final first = tester.getTopLeft(
        find.byKey(const ValueKey('dnp-suggested-103')),
      );
      final second = tester.getTopLeft(
        find.byKey(const ValueKey('dnp-suggested-104')),
      );
      expect(first.dy, lessThan(second.dy));
    });

    testWidgets('Add moves the team to do-not-pick with the reason', (
      tester,
    ) async {
      final h = await _pump(tester, teams: const [101, 104], entries: carded);

      expect(find.text('Now on 1st pick'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Add 104 to do not pick'));
      await tester.pumpAndSettle();

      expect(h.list.teamNumbers, [101]);
      expect(h.list.dnp.single.team, 104);
      expect(h.list.dnp.single.reason, 'Yellow card Q9 · died Q55');
      expect(find.text('Suggested (1)'), findsOneWidget);
    });

    testWidgets('Add all adds every suggestion', (tester) async {
      final h = await _pump(tester, entries: carded);

      await tester.tap(find.text('Add all'));
      await tester.pumpAndSettle();

      expect(h.list.dnp.map((d) => d.team), [103, 104]);
      expect(find.textContaining('Suggested'), findsNothing);
    });

    testWidgets('our own team is never suggested', (tester) async {
      await _pump(tester, myTeam: 103, entries: carded);

      expect(find.text('Suggested (1)'), findsOneWidget);
      expect(find.byKey(const ValueKey('dnp-suggested-103')), findsNothing);
    });

    testWidgets('fits a phone at 200% text', (tester) async {
      await _pump(
        tester,
        teams: const [104],
        entries: carded,
        size: const Size(360, 4000),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Suggested (2)'), findsOneWidget);
      final add = tester.getRect(
        find.bySemanticsLabel('Add 104 to do not pick'),
      );
      expect(add.right, lessThanOrEqualTo(360));
    });

    testWidgets('a listed team shows its incidents on its row', (tester) async {
      await _pump(tester, teams: const [105], entries: carded);

      expect(find.text('Yellow card Q4'), findsOneWidget);
    });
  });

  group('draft board', () {
    Future<void> openDraft(WidgetTester tester) async {
      await tester.tap(find.text('Draft board'));
      await tester.pumpAndSettle();
    }

    Finder inAlliance(int n, String team) => find.descendant(
      of: find.byKey(ValueKey('alliance-$n')),
      matching: find.text(team),
    );

    Future<void> invite(WidgetTester tester, int team, String answer) async {
      await tester.tap(find.byKey(ValueKey('free-$team')).hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text(answer));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'seeds the top eight as captains with alliance 1 on the clock',
      (tester) async {
        await _pump(tester);
        await openDraft(tester);

        expect(find.text('Round 1 of 3'), findsOneWidget);
        expect(find.text('Alliance 1 is on the clock'), findsOneWidget);
        for (var n = 1; n <= 8; n++) {
          expect(inAlliance(n, '${100 + n}'), findsOneWidget);
        }
      },
    );

    testWidgets('the rounds selector sets the draft length', (tester) async {
      await _pump(tester);
      await openDraft(tester);
      expect(find.text('Round 1 of 3'), findsOneWidget);

      await tester.tap(find.text('2 rounds'));
      await tester.pumpAndSettle();

      expect(find.text('Round 1 of 2'), findsOneWidget);
      expect(find.text('3 open'), findsNothing);
      expect(find.text('2 open'), findsNWidgets(8));
    });

    testWidgets('says how many picks until our alliance is on the clock', (
      tester,
    ) async {
      await _pump(tester, myTeam: 104);
      await openDraft(tester);

      expect(find.text('We pick in 3 picks.'), findsOneWidget);

      await invite(tester, 109, 'Accepted');
      await invite(tester, 110, 'Accepted');
      expect(find.text('We pick in 1 pick.'), findsOneWidget);

      await invite(tester, 108, 'Accepted');
      expect(find.text('We are on the clock.'), findsOneWidget);
    });

    testWidgets('says nothing when our team is not in the draft', (
      tester,
    ) async {
      await _pump(tester, myTeam: 999);
      await openDraft(tester);

      expect(find.textContaining('We pick'), findsNothing);
      expect(find.textContaining('We are on the clock'), findsNothing);
    });

    testWidgets('your pick list comes first in best available', (tester) async {
      await _pump(tester, teams: const [109, 110]);
      await openDraft(tester);

      final first = tester.getTopLeft(find.byKey(const ValueKey('free-109')));
      final other = tester.getTopLeft(find.byKey(const ValueKey('free-102')));
      expect(first.dy, lessThan(other.dy));
    });

    testWidgets('accepting a pick moves the clock, and undo takes it back', (
      tester,
    ) async {
      await _pump(tester);
      await openDraft(tester);

      await invite(tester, 109, 'Accepted');

      expect(inAlliance(1, '109'), findsOneWidget);
      expect(find.text('Alliance 2 is on the clock'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Undo'));
      await tester.pumpAndSettle();

      expect(inAlliance(1, '109'), findsNothing);
      expect(find.text('Alliance 1 is on the clock'), findsOneWidget);
    });

    testWidgets('a captain who accepts leaves, and the board moves up', (
      tester,
    ) async {
      await _pump(tester);
      await openDraft(tester);

      await invite(tester, 105, 'Accepted');

      expect(inAlliance(1, '105'), findsOneWidget);

      expect(inAlliance(5, '106'), findsOneWidget);
      expect(inAlliance(8, '109'), findsOneWidget);
    });

    testWidgets('a decline keeps the clock and removes the team', (
      tester,
    ) async {
      await _pump(tester);
      await openDraft(tester);

      await invite(tester, 109, 'Declined');

      expect(find.text('Alliance 1 is on the clock'), findsOneWidget);
      expect(find.byKey(const ValueKey('free-109')), findsNothing);
      expect(find.text('109 declined'), findsOneWidget);
    });

    testWidgets('a team on the do-not-pick list is flagged with its reason', (
      tester,
    ) async {
      final h = await _pump(tester, teams: const [109]);
      await h.pickLists.saveLayout(h.list.id, h.list.layout.tiers, const [
        DoNotPick(team: 110, reason: 'Tips over'),
      ]);
      await tester.pumpAndSettle();
      await openDraft(tester);

      expect(find.text('Do not pick: Tips over'), findsOneWidget);
    });

    testWidgets('picked teams are greyed out and labelled on the pick list', (
      tester,
    ) async {
      await _pump(tester, teams: const [109, 110]);
      await openDraft(tester);
      await invite(tester, 109, 'Accepted');

      await tester.tap(find.text('Pick list'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Picked by alliance 1'), findsOneWidget);
    });

    testWidgets('reset clears the board and can be undone', (tester) async {
      await _pump(tester);
      await openDraft(tester);
      await invite(tester, 109, 'Accepted');

      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
      await tester.pumpAndSettle();
      expect(inAlliance(1, '109'), findsNothing);

      await tester.tap(find.text('Undo').last);
      await tester.pumpAndSettle();
      expect(inAlliance(1, '109'), findsOneWidget);
    });
  });
}
