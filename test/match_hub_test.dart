import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/match_brief_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/ui/freshness_pill.dart';
import 'package:spectrumstrategy/src/ui/match_hub/match_hub_launcher.dart';
import 'package:spectrumstrategy/src/ui/match_hub/match_hub_plan_tab.dart';
import 'package:spectrumstrategy/src/ui/match_hub/match_hub_screen.dart';

import 'support/fake_match_brief_storage.dart';
import 'support/fake_match_brief_sync_service.dart';
import 'support/fake_match_directory.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

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
        wins: 0,
        losses: 0,
        ties: 0,
        epa: const StatboticsEpa(
          totalPoints: 50,
          autoPoints: 12,
          teleopPoints: 30,
        ),
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
    ];
  }
}

class _FakeTbaClient extends TbaClient {
  _FakeTbaClient({required this.played})
    : super(config: InMemoryTbaConfig('test-key'));

  final bool played;

  @override
  Future<List<TbaScheduleMatch>> getEventMatches(String eventKey) async {
    return <TbaScheduleMatch>[
      TbaScheduleMatch(
        key: '${eventKey}_qm1',
        compLevel: 'qm',
        matchNumber: 1,
        redTeams: const <int>[3847, 118, 2056],
        blueTeams: const <int>[971, 1323, 33],
        redScore: played ? 80 : null,
        blueScore: played ? 70 : null,
        winningAlliance: played ? 'red' : null,
      ),
    ];
  }

  @override
  Future<Map<String, TbaMatchPrediction>> getEventPredictions(
    String eventKey,
  ) async => const <String, TbaMatchPrediction>{};
}

class _Rig {
  _Rig({
    required this.launcher,
    required this.briefs,
    required this.sync,
    required this.match,
    required this.openedTeams,
  });

  final MatchHubLauncher launcher;
  final MatchBriefController briefs;
  final FakeMatchBriefSyncService sync;
  final StatboticsMatch match;
  final List<int> openedTeams;
}

Future<_Rig> _rig({
  required UserRole role,
  bool played = false,
  List<ScoutEntry> entries = const <ScoutEntry>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final event = EventController(
    client: _FakeStatboticsClient(),
    tbaClient: _FakeTbaClient(played: played),
  );
  await event.setEventKey(_eventKey);
  await event.setMyTeamNumber(3847);

  final scouting = ScoutingController(storage: FakeScoutingStorage());
  await scouting.bootstrap();
  for (final entry in entries) {
    await scouting.saveEntry(entry);
  }
  final config = ScoutConfigController(service: FakeScoutConfigService());
  await config.bootstrap();
  final strategy = StrategyController(directory: FakeMatchDirectory());
  await strategy.bootstrap();

  const user = SpectrumUser(uid: 'lead-uid', displayName: 'Lead');
  final roles = UserRoleController(
    authService: FakeSpectrumAuthService(initialUser: user),
    roleService: FakeUserRoleService()..setRoles('lead-uid', <UserRole>{role}),
  );
  await roles.bootstrap();

  final sync = FakeMatchBriefSyncService();
  final briefs = MatchBriefController(
    storage: FakeMatchBriefStorage(),
    syncService: sync,
  );
  await briefs.bootstrap();

  final opened = <int>[];
  return _Rig(
    launcher: MatchHubLauncher(
      eventController: event,
      scoutingController: scouting,
      configController: config,
      strategyController: strategy,
      openTeam: (context, team) => opened.add(team),
      briefController: briefs,
      userRoleController: roles,
    ),
    briefs: briefs,
    sync: sync,
    match: event.matches.single,
    openedTeams: opened,
  );
}

Future<void> _pumpHub(WidgetTester tester, _Rig rig) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MatchHubScreen(launcher: rig.launcher, match: rig.match),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(TestWidgetsFlutterBinding.ensureInitialized);

  testWidgets('an upcoming match shows both alliances and a prediction', (
    tester,
  ) async {
    final rig = await _rig(role: UserRole.scouter);
    await _pumpHub(tester, rig);

    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Prediction'), findsOneWidget);
    expect(find.text('Expected points (EPA)'), findsOneWidget);
    expect(find.text('Result'), findsNothing);
    expect(find.text('3847'), findsOneWidget);
    expect(find.text('971'), findsOneWidget);
    expect(find.text('Match'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Brief'), findsOneWidget);
  });

  testWidgets('a played match shows official beside scouted', (tester) async {
    final entry = ScoutEntry(
      matchId: 'qm1',
      teamNumber: 3847,
      tbaMatchKey: '${_eventKey}_qm1',
      byPhase: <StrategyPhase, ScoutPhaseData>{
        StrategyPhase.auton: const ScoutPhaseData(score: 12),
        StrategyPhase.teleop: const ScoutPhaseData(score: 30),
      },
    );
    final rig = await _rig(
      role: UserRole.scouter,
      played: true,
      entries: <ScoutEntry>[entry],
    );
    await _pumpHub(tester, rig);

    expect(find.text('Played'), findsOneWidget);
    expect(find.text('Upcoming'), findsNothing);
    expect(find.text('Result'), findsOneWidget);
    expect(find.text('Red won'), findsOneWidget);
    expect(find.text('Official 80'), findsOneWidget);
    expect(find.text('Official 70'), findsOneWidget);
    expect(find.text('Scouted 42.0 from 1 of 3 robots'), findsOneWidget);
    expect(find.text('Scouted 0.0 from 0 of 3 robots'), findsOneWidget);
  });

  testWidgets('a team number on the hub opens that team', (tester) async {
    final rig = await _rig(role: UserRole.scouter);
    await _pumpHub(tester, rig);

    await tester.tap(find.text('3847'));
    await tester.pumpAndSettle();

    expect(rig.openedTeams, <int>[3847]);
  });

  testWidgets('the app bar carries the data freshness pill', (tester) async {
    final rig = await _rig(role: UserRole.scouter);
    await _pumpHub(tester, rig);

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(FreshnessPill),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the strategy lead writes key points and marks the brief Ready', (
    tester,
  ) async {
    final rig = await _rig(role: UserRole.strategy);
    await _pumpHub(tester, rig);

    await tester.tap(find.text('Brief'));
    await tester.pumpAndSettle();
    expect(find.textContaining('has not marked this ready'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Defend the ramp early');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Mark ready'));
    await tester.pumpAndSettle();

    final stored = rig.briefs.briefFor(_eventKey, 'qm1');
    expect(stored.ready, isTrue);
    expect(stored.keyPoints, 'Defend the ramp early');
    expect(rig.sync.pushes.single.ready, isTrue);
    expect(find.textContaining('has not marked this ready'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Mark as draft'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Mark as draft'));
    await tester.pumpAndSettle();
    expect(rig.briefs.briefFor(_eventKey, 'qm1').ready, isFalse);
  });

  testWidgets('robot plans are typed and saved together', (tester) async {
    final rig = await _rig(role: UserRole.strategy);
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final data = rig.launcher.dataFor(rig.match);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              RobotPlansCard(launcher: rig.launcher, data: data),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(6));
    await tester.enterText(find.byType(TextField).first, 'Start left');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save plans'));
    await tester.pumpAndSettle();

    expect(rig.briefs.briefFor(_eventKey, 'qm1').planFor(3847), 'Start left');
    expect(rig.sync.pushes, hasLength(1));
  });

  testWidgets('a coach reads the brief and cannot edit it', (tester) async {
    final rig = await _rig(role: UserRole.scouter);
    await rig.briefs.save(
      eventKey: _eventKey,
      matchId: 'qm1',
      robotPlans: <int, String>{3847: 'Defend the ramp'},
      keyPoints: 'Climb early',
      ready: true,
    );
    await _pumpHub(tester, rig);

    await tester.tap(find.text('Brief'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Mark ready'), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Climb early'), findsOneWidget);
    expect(find.text('Defend the ramp'), findsOneWidget);

    expect(find.textContaining('Not scouted yet'), findsNWidgets(3));
    expect(find.text('Opponents'), findsOneWidget);
  });

  testWidgets('a coach sees a draft brief labelled as a draft', (tester) async {
    final rig = await _rig(role: UserRole.scouter);
    await _pumpHub(tester, rig);

    await tester.tap(find.text('Brief'));
    await tester.pumpAndSettle();

    expect(find.text('Draft'), findsOneWidget);
    expect(find.textContaining('has not marked this ready'), findsOneWidget);
    expect(find.text('None written'), findsOneWidget);
  });

  testWidgets('the board is not offered to a role that cannot edit', (
    tester,
  ) async {
    final rig = await _rig(role: UserRole.scouter);
    await _pumpHub(tester, rig);

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();

    expect(find.text('Robot plans'), findsOneWidget);
    expect(find.text('Save plans'), findsNothing);
    expect(find.text('No plan written'), findsNWidgets(6));
  });

  test('openBoardForMatch reuses the board for a match', () async {
    final rig = await _rig(role: UserRole.strategy);
    final strategy = rig.launcher.strategyController;

    await openBoardForMatch(
      strategy,
      eventKey: _eventKey,
      eventName: 'Test Event',
      matchNumber: 1,
      alliance: 'Red',
    );
    final first = strategy.session.id;
    expect(strategy.session.matchNumber, 1);
    expect(strategy.session.eventKey, _eventKey);

    await strategy.createMatch(eventKey: _eventKey, matchNumber: 5);
    await openBoardForMatch(
      strategy,
      eventKey: _eventKey,
      eventName: 'Test Event',
      matchNumber: 1,
      alliance: 'Red',
    );

    expect(strategy.session.id, first);
    final boards = await strategy.listMatches();
    expect(
      boards.where((m) => m.eventKey == _eventKey && m.matchNumber == 1),
      hasLength(1),
    );
  });
}
