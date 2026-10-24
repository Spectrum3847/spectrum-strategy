import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/models/trex_trait_report.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/prescout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/prescouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/state/trex_trait_report_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/ui/freshness_pill.dart';
import 'package:spectrumstrategy/src/ui/match_hub/match_hub_launcher.dart';
import 'package:spectrumstrategy/src/ui/team_hub_screen.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'support/fake_match_directory.dart';
import 'support/fake_pit_photo_store.dart';
import 'support/fake_pit_scout_config_service.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_prescouting_storage.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_trex_trait_report_storage.dart';

const _eventKey = '2026test';

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
    ];
  }

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async {
    return <StatboticsTeamBasic>[
      StatboticsTeamBasic(team: 3847, nickname: 'Spectrum'),
    ];
  }
}

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

Future<ScoutConfigController> _config() async {
  final controller = ScoutConfigController(service: FakeScoutConfigService());
  await controller.bootstrap();
  return controller;
}

Future<EventController> _event() async {
  final event = EventController(client: _FakeStatboticsClient());
  await event.setEventKey(_eventKey);
  return event;
}

Future<PitScoutingController> _pitWith(PitScoutEntry entry) async {
  final controller = PitScoutingController(
    storage: FakePitScoutingStorage(),
    photoStore: FakePitPhotoStore(),
  );
  await controller.bootstrap();
  await controller.saveEntry(entry);
  return controller;
}

Future<PitScoutConfigController> _pitConfig() async {
  final controller = PitScoutConfigController(
    service: FakePitScoutConfigService(),
  );
  await controller.bootstrap();
  return controller;
}

Future<Widget> _host(
  ScoutingController scouting,
  int teamNumber, {
  EventController? event,
  PitScoutingController? pitScoutingController,
  PitScoutConfigController? pitScoutConfigController,
  PrescoutingController? prescoutingController,
  TrexTraitReportController? trexTraitReportController,
}) async {
  return MaterialApp(
    home: TeamHubScreen(
      teamNumber: teamNumber,
      eventController: event ?? EventController(),
      scoutingController: scouting,
      configController: await _config(),
      pitScoutingController: pitScoutingController,
      pitScoutConfigController: pitScoutConfigController,
      prescoutingController: prescoutingController,
      trexTraitReportController: trexTraitReportController,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('compare flow picks an opponent and shows both teams', (
    tester,
  ) async {
    final scouting = await _seed([
      _entry(254, teleop: 50),
      _entry(1678, teleop: 20),
    ]);

    await tester.pumpWidget(await _host(scouting, 254));
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
    final scouting = await _seed([
      _entry(254, teleop: 50),
      _entry(1678, teleop: 20),
    ]);

    await tester.pumpWidget(await _host(scouting, 254));
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

  testWidgets('offers no actions that have nothing behind them', (
    tester,
  ) async {
    final scouting = await _seed([_entry(254, teleop: 50)]);

    await tester.pumpWidget(await _host(scouting, 254));
    await tester.pumpAndSettle();

    expect(find.text('Compare'), findsNothing);
    expect(find.text('Pit scout'), findsNothing);
    expect(find.text('Add to pick list'), findsNothing);
    expect(find.text('Pit scouting'), findsNothing);
    expect(find.text('Prescout'), findsNothing);
    expect(find.text('T-Rex traits'), findsNothing);
  });

  testWidgets('the app bar carries the data freshness pill', (tester) async {
    final scouting = await _seed(const <ScoutEntry>[]);

    await tester.pumpWidget(await _host(scouting, 254));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(FreshnessPill),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a team with no data still opens with its empty states', (
    tester,
  ) async {
    final scouting = await _seed(const <ScoutEntry>[]);

    await tester.pumpWidget(await _host(scouting, 254));
    await tester.pumpAndSettle();

    expect(find.text('Team 254'), findsOneWidget);
    expect(find.text('No entries recorded for this team yet.'), findsOneWidget);
    expect(find.text('No scheduled matches for this team.'), findsOneWidget);
  });

  group('with data from every source', () {
    Future<Widget> hostWithEverything() async {
      final scouting = await _seed([
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 3847,
          notes: 'Climbs fast',
          fieldValues: const {
            'teleopFuelScored': 12,
            'autoFuelScored': 3,
            'eLow': 'Successful',
          },
        ),
        ScoutEntry(
          matchId: 'qm2',
          teamNumber: 3847,
          fieldValues: const {'teleopFuelScored': 20, 'eLow': 'Failed'},
        ),
        _entry(254, teleop: 10),
      ]);
      final pit = await _pitWith(
        PitScoutEntry(
          teamNumber: 3847,
          authorUid: 'uid-1',
          fieldValues: const {'launcherType': 'Flywheel'},
        ),
      );
      final prescouting = PrescoutingController(
        storage: FakePrescoutingStorage(),
      );
      await prescouting.bootstrap();
      await prescouting.saveEntry(
        PrescoutEntry(
          teamNumber: 3847,
          fieldValues: const {
            'teleopFuelScored': 40,
            'comments': 'Strong in practice',
          },
        ),
      );
      final trex = TrexTraitReportController(
        storage: FakeTrexTraitReportStorage(),
      );
      await trex.bootstrap();
      await trex.submitReport(
        TrexTraitReport(
          trait: 'defense',
          teamNumber: 3847,
          matchNumber: 5,
          report: 'Blocks the bump',
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      return _host(
        scouting,
        3847,
        event: await _event(),
        pitScoutingController: pit,
        pitScoutConfigController: await _pitConfig(),
        prescoutingController: prescouting,
        trexTraitReportController: trex,
      );
    }

    testWidgets('shows every section', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await hostWithEverything());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Team 3847'),
        ),
        findsOneWidget,
      );

      expect(find.text('Spectrum'), findsOneWidget);
      expect(find.text('2-0'), findsOneWidget);
      expect(find.text('Pit: Flywheel'), findsOneWidget);
      expect(find.text('Compare'), findsOneWidget);
      expect(find.text('Pit scout'), findsOneWidget);

      expect(find.text('Event stats'), findsOneWidget);
      expect(find.text('Total score'), findsOneWidget);
      expect(find.text('Teleop fuel'), findsWidgets);

      expect(find.text('Mean'), findsNWidgets(2));
      expect(find.text('SD'), findsNWidgets(2));
      expect(find.text('Low Climb 1 / 2'), findsOneWidget);
      expect(find.text('By phase'), findsOneWidget);

      expect(find.text('Matches'), findsOneWidget);
      expect(find.text('Q1'), findsOneWidget);
      expect(find.text('Q2'), findsNothing);

      expect(find.text('Scout comments'), findsOneWidget);
      expect(find.text('Climbs fast'), findsOneWidget);
      expect(find.text('Pit scouting'), findsOneWidget);
      expect(find.text('Launcher Type'), findsOneWidget);
      expect(find.text('T-Rex traits'), findsOneWidget);
      expect(find.text('Blocks the bump'), findsOneWidget);

      expect(find.text('Prescout'), findsOneWidget);
      expect(find.text('Strong in practice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('prescout numbers are not blended into the event stats', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await hostWithEverything());
      await tester.pumpAndSettle();

      expect(find.text('40'), findsNWidgets(2));
      expect(find.text('20'), findsWidgets);
    });

    testWidgets('two columns on a wide screen, one on a phone', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await hostWithEverything());
      await tester.pumpAndSettle();

      final statsX = tester.getTopLeft(find.text('Event stats')).dx;
      final matchesX = tester.getTopLeft(find.text('Matches')).dx;
      expect(matchesX, greaterThan(statsX));

      tester.view.physicalSize = const Size(420, 6000);
      await tester.pumpAndSettle();

      final phoneStatsX = tester.getTopLeft(find.text('Event stats')).dx;
      final phoneMatchesX = tester.getTopLeft(find.text('Matches')).dx;
      expect(phoneMatchesX, phoneStatsX);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a match row opens the Match hub', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final scouting = await _seed([_entry(3847, teleop: 10)]);
      final event = await _event();
      final config = await _config();
      final strategy = StrategyController(directory: FakeMatchDirectory());
      await strategy.bootstrap();
      final launcher = MatchHubLauncher(
        eventController: event,
        scoutingController: scouting,
        configController: config,
        strategyController: strategy,
        openTeam: (context, team) {},
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              MatchHubScope(launcher: launcher, child: child!),
          home: TeamHubScreen(
            teamNumber: 3847,
            eventController: event,
            scoutingController: scouting,
            configController: config,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Q1'));
      await tester.pumpAndSettle();

      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Prediction'), findsOneWidget);
    });
  });
}
