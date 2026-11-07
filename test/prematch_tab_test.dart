import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/team_filters.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/event_stats_controller.dart';
import 'package:spectrumstrategy/src/state/playoff_board_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';
import 'package:spectrumstrategy/src/ui/glass_chrome.dart';
import 'package:spectrumstrategy/src/ui/prematch_tab.dart';
import 'package:spectrumstrategy/src/ui/team_hub_screen.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_pit_photo_store.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_playoff_board_storage.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

const _testEventKey = '2026test';

Future<EventController> _pumpTab(
  WidgetTester tester, {
  StatboticsClient? client,

  bool glass = false,
  EventStatsController? stats,
  ScoutingController? scouting,
  ScoutConfigController? config,
  PitScoutingController? pit,
  Size size = const Size(1200, 2000),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  if (glass) {
    tester.view.padding = const FakeViewPadding(bottom: 40);
  }
  addTearDown(tester.view.reset);

  final event = EventController(client: client ?? _FakeStatboticsClient());
  await event.setEventKey(_testEventKey);

  await tester.pumpWidget(
    MaterialApp(
      home: GlassChrome(
        enabled: glass,
        child: Scaffold(
          body: PrematchTab(
            eventController: event,
            scoutingController:
                scouting ?? ScoutingController(storage: FakeScoutingStorage()),
            configController:
                config ??
                ScoutConfigController(service: FakeScoutConfigService()),
            playoffBoardController: PlayoffBoardController(
              storage: FakePlayoffBoardStorage(),
            ),
            eventStatsController: stats,
            pitScoutingController: pit,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return event;
}

Finder _glassInsetPadding(Finder descendant, double inset) => find.ancestor(
  of: descendant,
  matching: find.byWidgetPredicate(
    (w) => w is Padding && w.padding.resolve(TextDirection.ltr).bottom == inset,
  ),
);

Future<void> _openSection(WidgetTester tester, String label) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('defaults to the TBA sub-tab and shows the match schedule', (
    tester,
  ) async {
    await _pumpTab(tester);

    expect(find.text('TBA'), findsOneWidget);
    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('Q2'), findsOneWidget);
    expect(
      find.text(
        'Ranked by EPA, joined with your scouting. Tap a team to open its '
        'page. Pull to refresh.',
      ),
      findsNothing,
      reason: 'the EPA team list is behind the Statbotics segment by default',
    );
  });

  testWidgets('switching to Statbotics shows the EPA-ranked team list', (
    tester,
  ) async {
    await _pumpTab(tester);

    await _openSection(tester, 'Statbotics');

    expect(
      find.text(
        'Ranked by EPA, joined with your scouting. Tap a team to open its '
        'page. Pull to refresh.',
      ),
      findsOneWidget,
    );
    expect(find.text('3847'), findsOneWidget);
    expect(find.text('971'), findsOneWidget);
    expect(find.text('Q1'), findsNothing);
  });

  testWidgets('the team list sorts by OPR and by number', (tester) async {
    await _pumpTab(
      tester,
      stats: EventStatsController(
        tbaClient: _OprTbaClient(<String, num>{'frc3847': 50, 'frc971': 10}),
      ),
    );
    await _openSection(tester, 'Statbotics');

    await tester.tap(find.text('OPR'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('3847')).dy,
      lessThan(tester.getTopLeft(find.text('971')).dy),
    );
    expect(find.textContaining('Ranked by OPR'), findsOneWidget);

    await tester.tap(find.text('Number'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('971')).dy,
      lessThan(tester.getTopLeft(find.text('3847')).dy),
    );
    expect(find.textContaining('Sorted by team number'), findsOneWidget);
  });

  testWidgets('switching back to TBA shows the schedule again', (tester) async {
    await _pumpTab(tester);

    await _openSection(tester, 'Statbotics');
    expect(
      find.text(
        'Ranked by EPA, joined with your scouting. Tap a team to open its '
        'page. Pull to refresh.',
      ),
      findsOneWidget,
    );

    await _openSection(tester, 'TBA');

    expect(find.text('Q1'), findsOneWidget);
    expect(
      find.text(
        'Ranked by EPA, joined with your scouting. Tap a team to open its '
        'page. Pull to refresh.',
      ),
      findsNothing,
    );
  });

  testWidgets(
    'TBA sub-tab shows an empty state when the event has no matches',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final event = EventController(client: _EmptyScheduleStatboticsClient());
      await event.setEventKey(_testEventKey);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrematchTab(
              eventController: event,
              scoutingController: ScoutingController(
                storage: FakeScoutingStorage(),
              ),
              configController: ScoutConfigController(
                service: FakeScoutConfigService(),
              ),
              playoffBoardController: PlayoffBoardController(
                storage: FakePlayoffBoardStorage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No schedule for'), findsOneWidget);
    },
  );

  testWidgets('TBA sub-tab shows a spinner while the schedule is loading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final gate = Completer<void>();
    final event = EventController(client: _SlowStatboticsClient(gate.future));
    final loadFuture = event.setEventKey(_testEventKey);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrematchTab(
            eventController: event,
            scoutingController: ScoutingController(
              storage: FakeScoutingStorage(),
            ),
            playoffBoardController: PlayoffBoardController(
              storage: FakePlayoffBoardStorage(),
            ),
            configController: ScoutConfigController(
              service: FakeScoutConfigService(),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await loadFuture;
    await tester.pumpAndSettle();
  });

  group('unified destination menu', () {
    testWidgets('every destination is reachable from the one menu', (
      tester,
    ) async {
      await _pumpTab(tester);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      for (final label in const <String>[
        'Statbotics',
        'TBA',
        'Ranking',
        'Playoff',
      ]) {
        expect(find.text(label), findsWidgets, reason: '$label is missing');
      }
      expect(find.text('Pick lists'), findsNothing);
      expect(find.text('Post match'), findsNothing);
    });

    testWidgets('Traits is not one of the destinations', (tester) async {
      await _pumpTab(tester);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Traits'), findsNothing);
    });

    testWidgets('the destinations bring in no nested Scaffold or AppBar', (
      tester,
    ) async {
      await _pumpTab(tester);

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('switching away from a destination and back keeps its state', (
      tester,
    ) async {
      await _pumpTab(tester);

      final schedule = find.byType(Scrollable).last;
      await tester.drag(schedule, const Offset(0, -120));
      await tester.pumpAndSettle();
      final offset = tester.state<ScrollableState>(schedule).position.pixels;
      expect(offset, greaterThan(0));

      await _openSection(tester, 'Ranking');
      await _openSection(tester, 'TBA');

      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).last)
            .position
            .pixels,
        offset,
        reason: 'the schedule was rebuilt, so the stack is not holding state',
      );
    });

    testWidgets('each event lens renders its own body, not the selected one', (
      tester,
    ) async {
      await _pumpTab(tester);

      expect(find.text('Q1'), findsOneWidget);
      await _openSection(tester, 'Statbotics');

      expect(find.text('3847'), findsWidgets);
      expect(
        find.text('Q1', skipOffstage: false),
        findsOneWidget,
        reason: 'the TBA slot lost its schedule when Statbotics was selected',
      );

      expect(find.text('Q1'), findsNothing);
    });
  });

  group('Match prediction destination', () {
    testWidgets('is reachable from the destination menu', (tester) async {
      await _pumpTab(tester);

      await _openSection(tester, 'Prediction');

      expect(
        find.textContaining('Enter all three teams for each alliance'),
        findsOneWidget,
      );
    });

    testWidgets('a scouted alliance shows a predicted total', (tester) async {
      final scouting = ScoutingController(storage: FakeScoutingStorage());
      await scouting.bootstrap();

      await scouting.saveEntry(
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 3847,
          fieldValues: const {'autoFuelScored': 2, 'teleopFuelScored': 5},
        ),
      );
      await scouting.saveEntry(
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 1,
          fieldValues: const {'autoFuelScored': 3, 'teleopFuelScored': 4},
        ),
      );

      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final event = EventController(client: _FakeStatboticsClient());
      await event.setEventKey(_testEventKey);

      final config = ScoutConfigController(service: FakeScoutConfigService());
      await config.bootstrap();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrematchTab(
              eventController: event,
              scoutingController: scouting,
              configController: config,
              playoffBoardController: PlayoffBoardController(
                storage: FakePlayoffBoardStorage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _openSection(tester, 'Prediction');

      await tester.enterText(find.byType(TextField).at(1), '3847');
      await tester.enterText(find.byType(TextField).at(2), '1');
      await tester.enterText(find.byType(TextField).at(3), '2');
      await tester.enterText(find.byType(TextField).at(4), '4');
      await tester.enterText(find.byType(TextField).at(5), '5');
      await tester.enterText(find.byType(TextField).at(6), '6');
      await tester.pumpAndSettle();

      expect(find.text('14'), findsOneWidget);
    });
  });

  group('team page reached from the team list', () {
    Future<ScoutingController> readyScoutingWithNotes() async {
      final controller = ScoutingController(storage: FakeScoutingStorage());
      await controller.bootstrap();

      for (var i = 0; i < 4; i++) {
        await controller.saveEntry(
          ScoutEntry(
            matchId: 'qm$i',
            teamNumber: 3847,
            notes: 'Scouted note number $i about team 3847',
          ),
        );
      }
      return controller;
    }

    Future<UserRoleController> rolesFor(Set<UserRole> roles) async {
      const user = SpectrumUser(uid: 'test-uid', displayName: 'Test');
      final roleService = FakeUserRoleService()..setRoles('test-uid', roles);
      final controller = UserRoleController(
        authService: FakeSpectrumAuthService(initialUser: user),
        roleService: roleService,
      );
      await controller.bootstrap();
      return controller;
    }

    Future<void> pumpAndOpenTeamAnalysis(
      WidgetTester tester, {
      required ScoutingController scoutingController,
      UserRoleController? userRoleController,
      bool viaRanking = false,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final event = EventController(client: _FakeStatboticsClient());
      await event.setEventKey(_testEventKey);
      final assistant = AssistantService(
        backends: [_FakeAssistantBackend()],
        cache: AssistantCache(),
        minimumGap: Duration.zero,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrematchTab(
              eventController: event,
              scoutingController: scoutingController,
              configController: ScoutConfigController(
                service: FakeScoutConfigService(),
              ),
              playoffBoardController: PlayoffBoardController(
                storage: FakePlayoffBoardStorage(),
              ),
              assistant: assistant,
              userRoleController: userRoleController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (viaRanking) {
        await _openSection(tester, 'Ranking');
        await tester.tap(find.text('3847'));
        await tester.pumpAndSettle();
        return;
      }

      await _openSection(tester, 'Statbotics');
      await tester.tap(find.text('Spectrum'));
      await tester.pumpAndSettle();
    }

    testWidgets('a strategy lead gets "Summarise the comments" the same as the '
        'Database tab', (tester) async {
      final scouting = await readyScoutingWithNotes();
      final roles = await rolesFor(<UserRole>{UserRole.strategy});

      await pumpAndOpenTeamAnalysis(
        tester,
        scoutingController: scouting,
        userRoleController: roles,
      );

      expect(find.text('Team 3847'), findsOneWidget);
      expect(find.text('Summarise the comments'), findsOneWidget);
    });

    testWidgets(
      'a scouter (cannot publish) does not get "Summarise the comments"',
      (tester) async {
        final scouting = await readyScoutingWithNotes();
        final roles = await rolesFor(<UserRole>{UserRole.scouter});

        await pumpAndOpenTeamAnalysis(
          tester,
          scoutingController: scouting,
          userRoleController: roles,
        );

        expect(find.text('Team 3847'), findsOneWidget);
        expect(find.text('Summarise the comments'), findsNothing);
        expect(
          find.text(
            '4 comments on this team. No summary yet. A strategy lead '
            'can write one.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'no signed-in role defaults to false, matching TeamHubScreen and '
      "CommentDigestCard's own defaults",
      (tester) async {
        final scouting = await readyScoutingWithNotes();

        await pumpAndOpenTeamAnalysis(tester, scoutingController: scouting);

        expect(find.text('Team 3847'), findsOneWidget);
        expect(find.text('Summarise the comments'), findsNothing);
      },
    );

    testWidgets(
      'a strategy lead gets "Summarise the comments" from Ranking too',
      (tester) async {
        final scouting = await readyScoutingWithNotes();
        final roles = await rolesFor(<UserRole>{UserRole.strategy});

        await pumpAndOpenTeamAnalysis(
          tester,
          scoutingController: scouting,
          userRoleController: roles,
          viaRanking: true,
        );

        expect(find.text('Team 3847'), findsOneWidget);
        expect(find.text('Summarise the comments'), findsOneWidget);
      },
    );

    testWidgets(
      'a scouter (cannot publish) does not get "Summarise the comments" '
      'from Ranking either',
      (tester) async {
        final scouting = await readyScoutingWithNotes();
        final roles = await rolesFor(<UserRole>{UserRole.scouter});

        await pumpAndOpenTeamAnalysis(
          tester,
          scoutingController: scouting,
          userRoleController: roles,
          viaRanking: true,
        );

        expect(find.text('Team 3847'), findsOneWidget);
        expect(find.text('Summarise the comments'), findsNothing);
        expect(
          find.text(
            '4 comments on this team. No summary yet. A strategy lead '
            'can write one.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('a team number in the Statbotics list opens the team page', (
      tester,
    ) async {
      final scouting = await readyScoutingWithNotes();

      await pumpAndOpenTeamAnalysis(tester, scoutingController: scouting);

      expect(find.byType(TeamHubScreen), findsOneWidget);
    });

    testWidgets('a team number in Ranking opens the team page', (tester) async {
      final scouting = await readyScoutingWithNotes();

      await pumpAndOpenTeamAnalysis(
        tester,
        scoutingController: scouting,
        viaRanking: true,
      );

      expect(find.byType(TeamHubScreen), findsOneWidget);
    });

    testWidgets('a team nobody has scouted opens its page too', (tester) async {
      await _pumpTab(tester);
      await _openSection(tester, 'Statbotics');

      await tester.tap(find.text('971'));
      await tester.pumpAndSettle();

      expect(find.byType(TeamHubScreen), findsOneWidget);
      expect(find.text('Team 971'), findsOneWidget);
      expect(
        find.text('No entries recorded for this team yet.'),
        findsOneWidget,
      );
    });
  });
  group('team filters', () {
    ScoutEntry entry(int team, int n, Map<String, dynamic> values) =>
        ScoutEntry(
          matchId: '',
          teamNumber: team,
          tbaMatchKey: '${_testEventKey}_qm$n',
          fieldValues: values,
        );

    Future<EventController> pumpFilters(
      WidgetTester tester, {
      bool withPit = true,
      bool open = true,
      Size size = const Size(1200, 2000),
      StatboticsClient? client,
    }) async {
      final scouting = ScoutingController(storage: FakeScoutingStorage());
      await scouting.bootstrap();
      for (final e in [
        entry(3847, 1, {'eHigh': 'Successful', 'tRdefense': true}),
        entry(3847, 2, {'eHigh': 'Failed'}),
        entry(971, 3, {'eHigh': 'Successful'}),
        entry(254, 4, {'eHigh': 'Failed', 'ryCard': 'Red'}),
      ]) {
        await scouting.saveEntry(e);
      }
      final config = ScoutConfigController(service: FakeScoutConfigService());
      await config.bootstrap();
      PitScoutingController? pit;
      if (withPit) {
        pit = PitScoutingController(
          storage: FakePitScoutingStorage(),
          photoStore: FakePitPhotoStore(),
        );
        await pit.bootstrap();
        await pit.saveEntry(
          PitScoutEntry(teamNumber: 3847, fieldValues: {'trenchFit': true}),
        );
      }
      final event = await _pumpTab(
        tester,
        client: client ?? _FilterStatboticsClient(),
        scouting: scouting,
        config: config,
        pit: pit,
        size: size,
      );
      await _openSection(tester, 'Statbotics');
      if (open) {
        await tester.tap(find.text('Filters'));
        await tester.pumpAndSettle();
      }
      return event;
    }

    Finder chipFor(TeamFilter filter) => find.ancestor(
      of: find.textContaining(filter.label, skipOffstage: false),
      matching: find.byType(FilterChip, skipOffstage: false),
    );

    Finder chip(String label, int count) =>
        find.widgetWithText(FilterChip, '$label ($count)');

    testWidgets('the chips start folded away and say how many are on', (
      tester,
    ) async {
      await pumpFilters(tester, open: false);
      expect(find.byType(FilterChip), findsNothing);

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(chip('Climbs L3', 2));
      await tester.pumpAndSettle();

      expect(find.text('Filters (1 on)'), findsOneWidget);
      expect(find.text('2 of 4 teams'), findsOneWidget);
    });

    testWidgets('another event starts with no filters on', (tester) async {
      final event = await pumpFilters(tester);
      await tester.tap(chip('Climbs L3', 2));
      await tester.pumpAndSettle();
      expect(find.text('2 of 4 teams'), findsOneWidget);

      await event.setEventKey('2026other');
      await tester.pumpAndSettle();

      expect(find.textContaining(' of 4 teams'), findsNothing);
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets('the chips stay open after the header scrolls away', (
      tester,
    ) async {
      await pumpFilters(
        tester,
        size: const Size(400, 500),
        client: _ManyTeamsStatboticsClient(),
      );
      expect(find.byType(FilterChip), findsWidgets);

      final list = find.byType(Scrollable).last;
      await tester.drag(list, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text('Test Event', skipOffstage: false), findsNothing);
      await tester.drag(list, const Offset(0, 6000));
      await tester.pumpAndSettle();

      expect(find.byType(FilterChip), findsWidgets);
    });

    testWidgets('chips show counts over the whole roster', (tester) async {
      await pumpFilters(tester);

      expect(chip('Fits under trench', 1), findsOneWidget);
      expect(chip('Climbs L3', 2), findsOneWidget);
      expect(chip('Auto climb', 0), findsOneWidget);
      expect(chip('Plays defense', 1), findsOneWidget);
      expect(chip('Passer', 0), findsOneWidget);
      expect(chip('Clean record', 2), findsOneWidget);
      expect(chip('Consistent', 0), findsOneWidget);
      expect(chip('No pit data yet', 3), findsOneWidget);
      expect(find.text('Can they do it?'), findsOneWidget);
      expect(find.text('What job?'), findsOneWidget);
      expect(find.text('Can we trust them?'), findsOneWidget);
      expect(find.textContaining(' of 4 teams'), findsNothing);
      expect(find.text('254'), findsOneWidget);
    });

    testWidgets('two filters are ANDed and counts stay put', (tester) async {
      await pumpFilters(tester);

      await tester.tap(chip('Climbs L3', 2));
      await tester.pumpAndSettle();
      expect(find.text('2 of 4 teams'), findsOneWidget);
      expect(find.text('3847'), findsOneWidget);
      expect(find.text('971'), findsOneWidget);
      expect(find.text('254'), findsNothing);

      await tester.tap(chip('No pit data yet', 3));
      await tester.pumpAndSettle();
      expect(find.text('1 of 4 teams'), findsOneWidget);
      expect(find.text('3847'), findsNothing);
      expect(find.text('971'), findsOneWidget);
      expect(chip('Climbs L3', 2), findsOneWidget);
      expect(chip('Plays defense', 1), findsOneWidget);
    });

    testWidgets('Clear turns every filter off', (tester) async {
      await pumpFilters(tester);

      await tester.tap(chip('Climbs L3', 2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.textContaining(' of 4 teams'), findsNothing);
      expect(find.text('254'), findsOneWidget);
      expect(tester.widget<FilterChip>(chip('Climbs L3', 2)).selected, isFalse);
    });

    testWidgets('an empty result says so and Clear brings the list back', (
      tester,
    ) async {
      await pumpFilters(tester);

      await tester.tap(chip('Auto climb', 0));
      await tester.pumpAndSettle();

      expect(find.text('0 of 4 teams'), findsOneWidget);
      expect(
        find.textContaining('No team passes every selected filter'),
        findsOneWidget,
      );
      expect(find.text('3847'), findsNothing);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('3847'), findsOneWidget);
      expect(
        find.textContaining('No team passes every selected filter'),
        findsNothing,
      );
    });

    testWidgets('every chip has its rule as a tooltip', (tester) async {
      await pumpFilters(tester);

      for (final filter in TeamFilter.values) {
        final finder = chipFor(filter);
        expect(tester.widget<FilterChip>(finder).tooltip, filter.rule);
      }
    });

    testWidgets('pit chips are hidden without a pit controller', (
      tester,
    ) async {
      await pumpFilters(tester, withPit: false);

      expect(find.textContaining('Fits under trench'), findsNothing);
      expect(find.textContaining('No pit data yet'), findsNothing);
      expect(chip('Climbs L3', 2), findsOneWidget);
    });

    testWidgets('wraps at 200% text on a 360px phone, every chip reachable', (
      tester,
    ) async {
      await pumpFilters(tester, size: const Size(360, 800));

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      for (final filter in TeamFilter.values) {
        final finder = chipFor(filter);
        expect(finder, findsOneWidget, reason: filter.label);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0), reason: filter.label);
        expect(rect.right, lessThanOrEqualTo(360), reason: filter.label);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'the bottom inset sits outside the scrollable, not laid out under '
    'it, on the TBA schedule and the EPA-ranked team list',
    (tester) async {
      await _pumpTab(tester, glass: true);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

      final schedule = find.ancestor(
        of: find.text('Q1'),
        matching: find.byType(CustomScrollView),
      );
      final scheduleRefresh = find.ancestor(
        of: schedule,
        matching: find.byType(RefreshIndicator),
      );
      expect(scheduleRefresh, findsOneWidget);

      expect(_glassInsetPadding(scheduleRefresh, 40), findsOneWidget);
      expect(
        find.descendant(
          of: scheduleRefresh,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Padding &&
                w.padding.resolve(TextDirection.ltr).bottom == 40,
          ),
        ),
        findsNothing,
        reason:
            'the inset must not sit between RefreshIndicator and the '
            'scrollable it wraps',
      );
      expect(
        tester.getRect(schedule).bottom,
        closeTo(screen.height - 40, 0.5),
        reason: 'the schedule stops short of the reserved strip',
      );

      await _openSection(tester, 'Statbotics');

      final epaText = find.text(
        'Ranked by EPA, joined with your scouting. Tap a team to open its '
        'page. Pull to refresh.',
      );
      final epaList = find.ancestor(
        of: epaText,
        matching: find.byType(ListView),
      );
      final epaRefresh = find.ancestor(
        of: epaList,
        matching: find.byType(RefreshIndicator),
      );
      expect(epaRefresh, findsOneWidget);
      expect(_glassInsetPadding(epaRefresh, 40), findsOneWidget);
      expect(
        find.descendant(
          of: epaRefresh,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Padding &&
                w.padding.resolve(TextDirection.ltr).bottom == 40,
          ),
        ),
        findsNothing,
      );
      expect(tester.getRect(epaList).bottom, closeTo(screen.height - 40, 0.5));
    },
  );

  testWidgets(
    'pull-to-refresh on the TBA schedule still reaches EventController.refresh',
    (tester) async {
      final client = _CountingStatboticsClient();
      await _pumpTab(tester, glass: true, client: client);
      final loadedCalls = client.matchesCalls;

      final schedule = find.ancestor(
        of: find.text('Q1'),
        matching: find.byType(CustomScrollView),
      );
      final refresh = find.ancestor(
        of: schedule,
        matching: find.byType(RefreshIndicator),
      );

      await tester.widget<RefreshIndicator>(refresh).onRefresh();

      expect(client.matchesCalls, greaterThan(loadedCalls));
    },
  );
}

class _FakeAssistantBackend implements AssistantBackend {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    throw const AssistantUnavailable('test backend never generates');
  }
}

class _EmptyScheduleStatboticsClient extends _FakeStatboticsClient {
  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    return const <StatboticsMatch>[];
  }
}

class _CountingStatboticsClient extends _FakeStatboticsClient {
  int matchesCalls = 0;

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    matchesCalls++;
    return super.getEventMatches(eventKey);
  }
}

class _SlowStatboticsClient extends _FakeStatboticsClient {
  _SlowStatboticsClient(this._gate);

  final Future<void> _gate;

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    await _gate;
    return super.getEventMatches(eventKey);
  }
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
        key: '${eventKey}_qm1',
        event: eventKey,
        matchNumber: 1,
        compLevel: 'qm',
        redTeams: const <int>[3847, 118, 2056],
        blueTeams: const <int>[971, 1323, 33],
      ),
      StatboticsMatch(
        key: '${eventKey}_qm2',
        event: eventKey,
        matchNumber: 2,
        compLevel: 'qm',
        redTeams: const <int>[254, 118, 1323],
        blueTeams: const <int>[971, 2056, 33],
      ),

      for (var number = 3; number <= 60; number++)
        StatboticsMatch(
          key: '${eventKey}_qm$number',
          event: eventKey,
          matchNumber: number,
          compLevel: 'qm',
          redTeams: const <int>[254, 118, 1323],
          blueTeams: const <int>[971, 2056, 33],
        ),
      StatboticsMatch(
        key: '${eventKey}_f1m1',
        event: eventKey,
        matchNumber: 1,
        compLevel: 'f',
        redTeams: const <int>[3847, 971, 118],
        blueTeams: const <int>[254, 1323, 2056],
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

class _ManyTeamsStatboticsClient extends _FilterStatboticsClient {
  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async {
    final base = await super.getEventTeams(eventKey);
    return <StatboticsTeamEvent>[
      ...base,
      for (var team = 2000; team < 2040; team++)
        StatboticsTeamEvent(
          team: team,
          event: eventKey,
          eventName: 'Test Event',
          year: 2026,
          wins: 0,
          losses: 0,
          ties: 0,
          epa: StatboticsEpa.empty,
        ),
    ];
  }
}

class _FilterStatboticsClient extends _FakeStatboticsClient {
  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async {
    final base = await super.getEventTeams(eventKey);
    return <StatboticsTeamEvent>[
      ...base,
      for (final team in const [254, 118])
        StatboticsTeamEvent(
          team: team,
          event: eventKey,
          eventName: 'Test Event',
          year: 2026,
          wins: 0,
          losses: 0,
          ties: 0,
          epa: StatboticsEpa.empty,
        ),
    ];
  }
}

class _OprTbaClient extends TbaClient {
  _OprTbaClient(this.oprs) : super(config: InMemoryTbaConfig('test-key'));

  final Map<String, num> oprs;

  @override
  Future<TbaEventOprs?> getEventOprs(String eventKey) async => TbaEventOprs(
    eventKey: eventKey,
    oprs: oprs,
    dprs: const <String, num>{},
    ccwms: const <String, num>{},
  );

  @override
  Future<TbaEventCoprs?> getEventCoprs(String eventKey) async => null;

  @override
  Future<TbaEventRankings?> getEventRankings(String eventKey) async => null;
}
