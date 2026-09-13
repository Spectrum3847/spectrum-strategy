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
import 'package:spectrumstrategy/src/state/event_stats_controller.dart';
import 'package:spectrumstrategy/src/state/playoff_board_controller.dart';
import 'package:spectrumstrategy/src/ui/playoff_section_screen.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_playoff_board_storage.dart';
import 'support/fake_scouting_storage.dart';

class _RankingsTbaClient extends TbaClient {
  _RankingsTbaClient(this.rankings) : super(config: InMemoryTbaConfig('key'));

  final TbaEventRankings? rankings;

  @override
  Future<TbaEventRankings?> getEventRankings(String eventKey) async => rankings;
}

class _VideoTbaClient extends TbaClient {
  _VideoTbaClient(this.videosByMatchKey)
    : super(config: InMemoryTbaConfig('key'));

  final Map<String, List<Map<String, String>>> videosByMatchKey;

  @override
  Future<TbaMatch?> getMatch(String matchKey) async {
    final videos = videosByMatchKey[matchKey];
    if (videos == null) return null;
    return TbaMatch.fromJson(<String, dynamic>{
      'key': matchKey,
      'videos': videos,
    });
  }
}

TbaEventRankings _rankingsWith(int team, int rank) =>
    TbaEventRankings.fromJson('2026txhou', <String, dynamic>{
      'sort_order_info': <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Ranking Score'},
      ],
      'rankings': <Map<String, dynamic>>[
        <String, dynamic>{
          'rank': rank,
          'team_key': 'frc$team',
          'record': <String, dynamic>{'wins': 1, 'losses': 0, 'ties': 0},
          'sort_orders': <num>[1.0],
        },
      ],
    });

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

Future<EventController> _loadedEventController({TbaClient? tbaClient}) async {
  final controller = EventController(
    client: StatboticsClient(
      httpClient: MockClient(_healthyApi),
      sleep: (_) async {},
    ),
    tbaClient: tbaClient,
  );
  await controller.setEventKey('2026txhou');
  return controller;
}

Widget _host({
  required EventController eventController,
  required ScoutingController scoutingController,
  required ScoutConfigController configController,
  PlayoffBoardController? boardController,
  EventStatsController? eventStatsController,
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
        eventStatsController: eventStatsController,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('opens on the scouting meeting board', (tester) async {
    final eventController = await _loadedEventController();
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

    expect(find.text('Match info'), findsNothing);
    expect(find.text('Sorting board'), findsOneWidget);

    await tester.tap(find.text('Alliances'));
    await tester.pump(Duration.zero);
    expect(find.text('Team captain'), findsOneWidget);
    expect(find.text('Fourth'), findsOneWidget);
  });

  testWidgets('the scouting meeting ranked list shows the TBA rank', (
    tester,
  ) async {
    final eventController = await _loadedEventController();
    await eventController.setMyTeamNumber(3847);
    final configController = ScoutConfigController(
      service: FakeScoutConfigService(),
    );
    await configController.bootstrap();
    final scoutingController = await _seed([_entry(118, match: 'qf1')]);
    final statsController = EventStatsController(
      tbaClient: _RankingsTbaClient(_rankingsWith(118, 7)),
    );
    await statsController.bootstrap();
    await statsController.load('2026txhou');

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: scoutingController,
        configController: configController,
        eventStatsController: statsController,
      ),
    );
    await tester.pump(Duration.zero);

    await tester.tap(find.text('Scouting meeting'));
    await tester.pump(Duration.zero);

    expect(find.text('TBA rank'), findsOneWidget);
    expect(find.text('#7'), findsOneWidget);
  });

  testWidgets('the ranked list shows -- for a team absent from TBA rankings', (
    tester,
  ) async {
    final eventController = await _loadedEventController();
    await eventController.setMyTeamNumber(3847);
    final configController = ScoutConfigController(
      service: FakeScoutConfigService(),
    );
    await configController.bootstrap();
    final scoutingController = await _seed([_entry(118, match: 'qf1')]);
    final statsController = EventStatsController(
      tbaClient: _RankingsTbaClient(null),
    );
    await statsController.bootstrap();
    await statsController.load('2026txhou');

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: scoutingController,
        configController: configController,
        eventStatsController: statsController,
      ),
    );
    await tester.pump(Duration.zero);

    await tester.tap(find.text('Scouting meeting'));
    await tester.pump(Duration.zero);

    expect(find.text('TBA rank'), findsOneWidget);
    expect(find.text('--'), findsWidgets);
  });

  testWidgets('the qualification video list shows N/A with no TBA video', (
    tester,
  ) async {
    final eventController = await _loadedEventController();
    await eventController.setMyTeamNumber(3847);
    final configController = ScoutConfigController(
      service: FakeScoutConfigService(),
    );
    await configController.bootstrap();

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: await _seed(const []),
        configController: configController,
      ),
    );
    await tester.pump(Duration.zero);

    await tester.ensureVisible(find.text('Scouting meeting'));
    await tester.tap(find.text('Scouting meeting'));
    await tester.pump(Duration.zero);

    expect(find.text('Qualification video'), findsOneWidget);
    expect(find.text('Q1: '), findsOneWidget);
    expect(find.text('N/A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the qualification video list links a match TBA has a video for',
    (tester) async {
      final eventController = await _loadedEventController(
        tbaClient: _VideoTbaClient(<String, List<Map<String, String>>>{
          '2026txhou_qm1': [
            {'type': 'youtube', 'key': 'abc123'},
          ],
        }),
      );
      await eventController.setMyTeamNumber(3847);
      final configController = ScoutConfigController(
        service: FakeScoutConfigService(),
      );
      await configController.bootstrap();

      await tester.pumpWidget(
        _host(
          eventController: eventController,
          scoutingController: await _seed(const []),
          configController: configController,
        ),
      );
      await tester.pump(Duration.zero);

      await tester.ensureVisible(find.text('Scouting meeting'));
      await tester.tap(find.text('Scouting meeting'));
      await tester.pump(Duration.zero);

      await tester.pump(Duration.zero);

      expect(
        find.text('https://www.youtube.com/watch?v=abc123'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
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

  testWidgets('at desktop width the side tables sit beside the sorting board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    await tester.ensureVisible(find.text('Scouting meeting'));
    await tester.tap(find.text('Scouting meeting'));
    await tester.pump(Duration.zero);

    final boardTop = tester.getTopLeft(find.text('Sorting board'));
    final tankTop = tester.getTopLeft(find.text('Tank drivetrain'));
    expect(tankTop.dx, greaterThan(boardTop.dx));
    expect(tankTop.dy, closeTo(boardTop.dy, 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at phone width the side tables stack under the sorting board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    await tester.ensureVisible(find.text('Scouting meeting'));
    await tester.tap(find.text('Scouting meeting'));
    await tester.pump(Duration.zero);

    final boardTop = tester.getTopLeft(find.text('Sorting board'));
    final tankTop = tester.getTopLeft(find.text('Tank drivetrain'));
    expect(tankTop.dy, greaterThan(boardTop.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'focusing a sorting board cell shows a toolbar that toggles its style',
    (tester) async {
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

      expect(find.byKey(const ValueKey('meeting-0-0-highlight')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('meeting-0-0')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('meeting-0-0-highlight')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('meeting-0-0-italic')), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('meeting-0-0-highlight')),
      );
      await tester.tap(find.byKey(const ValueKey('meeting-0-0-highlight')));
      await tester.pump();
      await boardController.pendingWrites;

      expect(
        storage.boards['2026txhou']!.meetingCellStyle(0, 0).highlighted,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets(
    'a team placed in the alliance grid drops off the panels and the next '
    'unplaced team takes its place',
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
              '0,0': '971',
              '0,1': '254',
              '1,0': '118',
              '1,1': '2056',
            },

            allianceCells: <String, String>{'0,0': '971'},
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

      expect(panels.contains('971'), isFalse);
      expect(panels.indexOf('254') < panels.indexOf('118'), isTrue);
      expect(panels.indexOf('118') < panels.indexOf('2056'), isTrue);
    },
  );
}
