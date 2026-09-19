import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/models/playoff_board.dart';
import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/playoff_board_controller.dart';
import 'package:spectrumstrategy/src/state/post_match_report_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';
import 'package:spectrumstrategy/src/ui/match_info_view.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'support/fake_playoff_board_storage.dart';
import 'support/fake_post_match_report_storage.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

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

const _eventJson = '{"key":"2026txhou","name":"Houston","year":2026}';
const _teamEventsJson =
    '[{"team":3847,"event":"2026txhou","event_name":"Houston",'
    '"team_name":"Spectrum","year":2026,"wins":0,"losses":0,"ties":0,'
    '"epa":null}]';

const _matchesJson =
    '[{"key":"2026txhou_qm1","event":"2026txhou","match_number":1,'
    '"comp_level":"qm","alliances":{"red":{"team_keys":[3847,118,2056]},'
    '"blue":{"team_keys":[254,1323,971]}}},'
    '{"key":"2026txhou_qm2","event":"2026txhou","match_number":2,'
    '"comp_level":"qm","alliances":{"red":{"team_keys":[1,2,3]},'
    '"blue":{"team_keys":[4,5,6]}}}]';

const _matchesWithPlayoffJson =
    '[{"key":"2026txhou_qm1","event":"2026txhou","match_number":1,'
    '"comp_level":"qm","alliances":{"red":{"team_keys":[3847,118,2056]},'
    '"blue":{"team_keys":[254,1323,971]}}},'
    '{"key":"2026txhou_sf1","event":"2026txhou","match_number":1,'
    '"comp_level":"sf","alliances":{"red":{"team_keys":[3847,118,2056]},'
    '"blue":{"team_keys":[254,1323,971]}}}]';

Future<http.Response> _healthyApi(
  http.Request request,
  String matchesJson,
) async {
  final path = request.url.path;
  if (path.endsWith('/event/2026txhou')) return http.Response(_eventJson, 200);
  if (path.endsWith('/team_events')) return http.Response(_teamEventsJson, 200);
  if (path.endsWith('/matches')) return http.Response(matchesJson, 200);
  if (path.endsWith('/teams')) return http.Response('[]', 200);
  return http.Response('not found', 404);
}

Future<EventController> _loadedEventController({
  String matchesJson = _matchesJson,
}) async {
  final controller = EventController(
    client: StatboticsClient(
      httpClient: MockClient((request) => _healthyApi(request, matchesJson)),
      sleep: (_) async {},
    ),
  );
  await controller.setEventKey('2026txhou');
  return controller;
}

Widget _host({
  required EventController eventController,
  required ScoutingController scoutingController,
  required ScoutConfigController configController,
  PlayoffBoardController? playoffBoardController,
  PostMatchReportController? postMatchReportController,
  UserRoleController? userRoleController,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MatchInfoView(
        eventController: eventController,
        scoutingController: scoutingController,
        configController: configController,
        playoffBoardController: playoffBoardController,
        postMatchReportController: postMatchReportController,
        userRoleController: userRoleController,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<ScoutConfigController> config() async {
    final controller = ScoutConfigController(service: FakeScoutConfigService());
    await controller.bootstrap();
    return controller;
  }

  testWidgets('shows an empty state with no team number set', (tester) async {
    final eventController = await _loadedEventController();
    final scouting = await _seed(const <ScoutEntry>[]);

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: scouting,
        configController: await config(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No team number set'), findsOneWidget);
  });

  testWidgets('lists a match with the pre-match and opponents tables', (
    tester,
  ) async {
    final eventController = await _loadedEventController();
    await eventController.setMyTeamNumber(3847);
    final scouting = await _seed([
      _entry(118, fieldValues: {'teleopFuelScored': 10}),
    ]);

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: scouting,
        configController: await config(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pre-match'), findsOneWidget);
    expect(find.text('Opponents'), findsOneWidget);

    expect(find.text('3847'), findsOneWidget);
    expect(find.text('118'), findsOneWidget);
    expect(find.text('2056'), findsOneWidget);
    expect(find.text('254'), findsOneWidget);
    expect(find.text('1323'), findsOneWidget);
    expect(find.text('971'), findsOneWidget);

    expect(find.text('Max auto'), findsNWidgets(2));

    expect(find.textContaining('Q1'), findsOneWidget);
    expect(find.textContaining('Q2'), findsNothing);
  });

  testWidgets(
    'shows a Playoff Match Info divider before semis/finals matches',
    (tester) async {
      final eventController = await _loadedEventController(
        matchesJson: _matchesWithPlayoffJson,
      );
      await eventController.setMyTeamNumber(3847);
      final scouting = await _seed(const <ScoutEntry>[]);

      await tester.pumpWidget(
        _host(
          eventController: eventController,
          scoutingController: scouting,
          configController: await config(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Playoff Match Info'), 400);
      await tester.pumpAndSettle();

      expect(find.text('Playoff Match Info'), findsOneWidget);
      expect(find.textContaining('SF1'), findsOneWidget);
    },
  );

  testWidgets(
    'editing a playoff match info cell stores an override on the board',
    (tester) async {
      final eventController = await _loadedEventController(
        matchesJson: _matchesWithPlayoffJson,
      );
      await eventController.setMyTeamNumber(3847);
      final scouting = await _seed(const <ScoutEntry>[]);
      final storage = FakePlayoffBoardStorage();
      final boardController = PlayoffBoardController(storage: storage);
      await boardController.bootstrap();

      await tester.pumpWidget(
        _host(
          eventController: eventController,
          scoutingController: scouting,
          configController: await config(),
          playoffBoardController: boardController,
        ),
      );
      await tester.pumpAndSettle();

      final key = PlayoffBoard.overrideKey(
        tableId: 'alliance',
        teamNumber: 118,
        columnCode: 'robotType',
      );
      await tester.scrollUntilVisible(find.byKey(ValueKey<String>(key)), 400);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ValueKey<String>(key)),
        'swerve trench',
      );
      await boardController.pendingWrites;

      expect(
        storage.boards['2026txhou']!.matchInfoOverrides[key],
        'swerve trench',
      );
    },
  );

  Future<UserRoleController> readyRoles(UserRole role) async {
    const user = SpectrumUser(uid: 'lead-uid', displayName: 'Lead');
    final roleService = FakeUserRoleService()
      ..setRoles('lead-uid', <UserRole>{role});
    final roles = UserRoleController(
      authService: FakeSpectrumAuthService(initialUser: user),
      roleService: roleService,
    );
    await roles.bootstrap();
    return roles;
  }

  testWidgets('a lead can fill in and save the post-match table (#1843)', (
    tester,
  ) async {
    final eventController = await _loadedEventController();
    await eventController.setMyTeamNumber(3847);
    final scouting = await _seed(const <ScoutEntry>[]);
    final storage = FakePostMatchReportStorage();
    final postMatch = PostMatchReportController(storage: storage);
    await postMatch.bootstrap();
    final roles = await readyRoles(UserRole.strategy);

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: scouting,
        configController: await config(),
        postMatchReportController: postMatch,
        userRoleController: roles,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Post-match'), findsOneWidget);
    expect(find.text('Auton'), findsOneWidget);
    expect(find.text('Teleop'), findsOneWidget);
    expect(find.text('Endgame'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'outpost trench');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byIcon(Icons.save_outlined),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();

    final saved = postMatch.reportFor(
      eventController.eventKey,
      '2026txhou_qm1',
    );
    expect(saved.auto, 'outpost trench');
  });

  testWidgets('the post-match table is read-only with no editing role', (
    tester,
  ) async {
    final eventController = await _loadedEventController();
    await eventController.setMyTeamNumber(3847);
    final scouting = await _seed(const <ScoutEntry>[]);
    final postMatch = PostMatchReportController(
      storage: FakePostMatchReportStorage(),
    );
    await postMatch.bootstrap();

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: scouting,
        configController: await config(),
        postMatchReportController: postMatch,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Post-match'), findsOneWidget);

    expect(find.byIcon(Icons.save_outlined), findsNothing);
  });

  testWidgets('a scouter cannot edit the post-match table (#2003)', (
    tester,
  ) async {
    final eventController = await _loadedEventController();
    await eventController.setMyTeamNumber(3847);
    final scouting = await _seed(const <ScoutEntry>[]);
    final postMatch = PostMatchReportController(
      storage: FakePostMatchReportStorage(),
    );
    await postMatch.bootstrap();
    final roles = await readyRoles(UserRole.scouter);

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: scouting,
        configController: await config(),
        postMatchReportController: postMatch,
        userRoleController: roles,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Post-match'), findsOneWidget);

    expect(find.byIcon(Icons.save_outlined), findsNothing);
  });

  testWidgets(
    'pre-match and opponents sit side by side with post-match at the far '
    'right (#2003)',
    (tester) async {
      final eventController = await _loadedEventController();
      await eventController.setMyTeamNumber(3847);
      final scouting = await _seed(const <ScoutEntry>[]);
      final postMatch = PostMatchReportController(
        storage: FakePostMatchReportStorage(),
      );
      await postMatch.bootstrap();
      final roles = await readyRoles(UserRole.strategy);

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          eventController: eventController,
          scoutingController: scouting,
          configController: await config(),
          postMatchReportController: postMatch,
          userRoleController: roles,
        ),
      );
      await tester.pumpAndSettle();

      final preMatchX = tester.getTopLeft(find.text('Pre-match')).dx;
      final opponentsX = tester.getTopLeft(find.text('Opponents')).dx;
      final postMatchX = tester.getTopLeft(find.text('Post-match')).dx;

      expect(preMatchX, lessThan(opponentsX));
      expect(opponentsX, lessThan(postMatchX));
    },
  );

  testWidgets('a long computed cell value wraps instead of clipping (#2003)', (
    tester,
  ) async {
    final eventController = await _loadedEventController();
    await eventController.setMyTeamNumber(3847);
    final scouting = await _seed(const <ScoutEntry>[]);

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: scouting,
        configController: await config(),
      ),
    );
    await tester.pumpAndSettle();

    final nameCell = tester.widget<Text>(find.text('--').first);
    expect(nameCell.overflow, isNot(TextOverflow.ellipsis));
    expect(nameCell.softWrap, isTrue);
  });
}
