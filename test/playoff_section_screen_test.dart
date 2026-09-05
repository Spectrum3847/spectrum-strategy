import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/models/playoff_board.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/playoff_board_controller.dart';
import 'package:spectrumstrategy/src/ui/playoff_section_screen.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_playoff_board_storage.dart';
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

const _eventJson = '{"key":"2026txhou","name":"Houston","year":2026}';
const _teamEventsJson =
    '[{"team":3847,"event":"2026txhou","event_name":"Houston",'
    '"team_name":"Spectrum","year":2026,"wins":0,"losses":0,"ties":0,'
    '"epa":null}]';

const _matchesJson =
    '[{"key":"2026txhou_qm1","event":"2026txhou","match_number":1,'
    '"comp_level":"qm","alliances":{"red":{"team_keys":[1,2,3]},'
    '"blue":{"team_keys":[4,5,6]}}},'
    '{"key":"2026txhou_qf1","event":"2026txhou","match_number":1,'
    '"comp_level":"qf","alliances":{"red":{"team_keys":[3847,118,2056]},'
    '"blue":{"team_keys":[254,1323,971]}}}]';

Future<http.Response> _healthyApi(http.Request request) async {
  final path = request.url.path;
  if (path.endsWith('/event/2026txhou')) return http.Response(_eventJson, 200);
  if (path.endsWith('/team_events')) return http.Response(_teamEventsJson, 200);
  if (path.endsWith('/matches')) return http.Response(_matchesJson, 200);
  if (path.endsWith('/teams')) return http.Response('[]', 200);
  return http.Response('not found', 404);
}

Future<EventController> _loadedEventController() async {
  final controller = EventController(
    client: StatboticsClient(
      httpClient: MockClient(_healthyApi),
      sleep: (_) async {},
    ),
    statboticsEnabled: true,
  );
  await controller.setEventKey('2026txhou');
  return controller;
}

Widget _host({
  required EventController eventController,
  required ScoutingController scoutingController,
  required ScoutConfigController configController,
  PlayoffBoardController? boardController,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PlayoffSectionScreen(
        eventController: eventController,
        scoutingController: scoutingController,
        configController: configController,
        boardController:
            boardController ??
            PlayoffBoardController(storage: FakePlayoffBoardStorage()),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('shows an empty state with no team number set', (tester) async {
    final eventController = await _loadedEventController();
    final configController = ScoutConfigController(
      service: FakeScoutConfigService(),
    );
    await configController.bootstrap();
    final scoutingController = await _seed(const []);

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: scoutingController,
        configController: configController,
      ),
    );
    await tester.pump(Duration.zero);

    expect(find.text('Match info'), findsOneWidget);
    expect(find.textContaining('No team number set'), findsOneWidget);
  });

  testWidgets(
    'builds the alliance table and opponents once a team number is set',
    (tester) async {
      final eventController = await _loadedEventController();
      await eventController.setMyTeamNumber(3847);
      final configController = ScoutConfigController(
        service: FakeScoutConfigService(),
      );
      await configController.bootstrap();
      final scoutingController = await _seed([
        _entry(118, match: 'qf1', fieldValues: {'ryCard': true}),
      ]);

      await tester.pumpWidget(
        _host(
          eventController: eventController,
          scoutingController: scoutingController,
          configController: configController,
        ),
      );
      await tester.pump(Duration.zero);

      expect(find.text('Our alliance'), findsOneWidget);
      expect(find.text('QF1'), findsOneWidget);
      expect(find.text('Opponents'), findsOneWidget);

      await tester.tap(find.text('Scouting meeting'));
      await tester.pump(Duration.zero);
      expect(find.text('Yellow / red card'), findsOneWidget);
      expect(find.text('118'), findsWidgets);

      await tester.tap(find.text('Alliances'));
      await tester.pump(Duration.zero);
      expect(find.text('Team captain'), findsOneWidget);
      expect(find.text('4th pick'), findsOneWidget);
    },
  );

  testWidgets('typing into the sorting board persists through the controller', (
    tester,
  ) async {
    final eventController = await _loadedEventController();
    await eventController.setMyTeamNumber(3847);
    final configController = ScoutConfigController(
      service: FakeScoutConfigService(),
    );
    await configController.bootstrap();
    final storage = FakePlayoffBoardStorage();
    final boardController = PlayoffBoardController(storage: storage);
    await boardController.bootstrap();

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: await _seed(const []),
        configController: configController,
        boardController: boardController,
      ),
    );
    await tester.pump(Duration.zero);

    await tester.tap(find.text('Scouting meeting'));
    await tester.pump(Duration.zero);

    await tester.enterText(find.byKey(const ValueKey('meeting-0-0')), '3847');
    await tester.enterText(
      find.byKey(const ValueKey('meeting-label-0')),
      'Must pick',
    );
    await boardController.pendingWrites;

    final board = storage.boards['2026txhou'];
    expect(board, isNotNull);
    expect(board!.meetingCell(0, 0), '3847');
    expect(board.columnLabel(0), 'Must pick');
  });

  testWidgets(
    'the alliance detail panels follow the sorting board reading order',
    (tester) async {
      final eventController = await _loadedEventController();
      await eventController.setMyTeamNumber(3847);
      final configController = ScoutConfigController(
        service: FakeScoutConfigService(),
      );
      await configController.bootstrap();
      final boardController = PlayoffBoardController(
        storage: FakePlayoffBoardStorage(<String, PlayoffBoard>{
          '2026txhou': const PlayoffBoard(
            meetingCells: <String, String>{
              '0,1': '254',
              '1,0': '118',
              '0,0': '971',
            },
          ),
        }),
      );
      await boardController.bootstrap();

      await tester.pumpWidget(
        _host(
          eventController: eventController,
          scoutingController: await _seed(const []),
          configController: configController,
          boardController: boardController,
        ),
      );
      await tester.pump(Duration.zero);

      await tester.tap(find.text('Alliances'));
      await tester.pump(Duration.zero);

      final panels = tester
          .widgetList<Text>(
            find.descendant(of: find.byType(Wrap), matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .toList();
      expect(panels.indexOf('971') < panels.indexOf('254'), isTrue);
      expect(panels.indexOf('254') < panels.indexOf('118'), isTrue);
    },
  );

  testWidgets('an edited playoff match info cell is stored as an override', (
    tester,
  ) async {
    final eventController = await _loadedEventController();
    await eventController.setMyTeamNumber(3847);
    final configController = ScoutConfigController(
      service: FakeScoutConfigService(),
    );
    await configController.bootstrap();
    final storage = FakePlayoffBoardStorage();
    final boardController = PlayoffBoardController(storage: storage);
    await boardController.bootstrap();

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: await _seed(const []),
        configController: configController,
        boardController: boardController,
      ),
    );
    await tester.pump(Duration.zero);

    final key = PlayoffBoard.overrideKey(
      tableId: 'alliance',
      teamNumber: 118,
      columnCode: 'robotType',
    );
    await tester.enterText(find.byKey(ValueKey<String>(key)), 'swerve trench');
    await boardController.pendingWrites;

    expect(
      storage.boards['2026txhou']!.matchInfoOverrides[key],
      'swerve trench',
    );
  });
}
