import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/event_stats_controller.dart';
import 'package:spectrumstrategy/src/ui/playoff_ranking_screen.dart';

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
        teamName: 'Spartan Robotics',
        year: 2026,
        wins: 1,
        losses: 1,
        ties: 0,
        epa: StatboticsEpa.empty,
      ),
    ];
  }

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async =>
      const <StatboticsMatch>[];
}

class _FakeTbaClient extends TbaClient {
  _FakeTbaClient([this.oprs = const <String, num>{}, this.rankings])
    : super(config: InMemoryTbaConfig('test-key'));

  final Map<String, num> oprs;
  final TbaEventRankings? rankings;

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
  Future<TbaEventRankings?> getEventRankings(String eventKey) async => rankings;
}

TbaEventRankings _rankingsFor(Map<int, int> ranks) {
  return TbaEventRankings.fromJson('2026test', <String, dynamic>{
    'sort_order_info': <Map<String, dynamic>>[
      <String, dynamic>{'name': 'Ranking Score'},
    ],
    'rankings': <Map<String, dynamic>>[
      for (final entry in ranks.entries)
        <String, dynamic>{
          'rank': entry.value,
          'team_key': 'frc${entry.key}',
          'record': <String, dynamic>{'wins': 1, 'losses': 0, 'ties': 0},
          'sort_orders': <num>[-entry.value.toDouble()],
        },
    ],
  });
}

Future<EventStatsController> _statsController(
  Map<String, num> oprs, {
  TbaEventRankings? rankings,
}) async {
  final stats = EventStatsController(tbaClient: _FakeTbaClient(oprs, rankings));
  await stats.bootstrap();
  await stats.load(_eventKey);
  return stats;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('OPR sort ranks the higher TBA OPR first', (tester) async {
    final event = EventController(client: _FakeStatboticsClient());
    await event.setEventKey(_eventKey);
    final stats = await _statsController(<String, num>{
      'frc971': 45,
      'frc3847': 30,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayoffRankingScreen(
            eventController: event,
            scoutingController: ScoutingController(
              storage: FakeScoutingStorage(),
            ),
            configController: ScoutConfigController(
              service: FakeScoutConfigService(),
            ),
            statsController: stats,
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('OPR').first);
    await tester.pumpAndSettle();

    expect(find.text('45.0'), findsOneWidget);
    expect(find.text('30.0'), findsOneWidget);

    final rank971 = tester.getTopLeft(find.text('971')).dy;
    final rank3847 = tester.getTopLeft(find.text('3847')).dy;
    expect(rank971, lessThan(rank3847));

    expect(tester.takeException(), isNull);
  });

  testWidgets('stat columns show -- when no stats controller is wired', (
    tester,
  ) async {
    final event = EventController(client: _FakeStatboticsClient());
    await event.setEventKey(_eventKey);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayoffRankingScreen(
            eventController: event,
            scoutingController: ScoutingController(
              storage: FakeScoutingStorage(),
            ),
            configController: ScoutConfigController(
              service: FakeScoutConfigService(),
            ),
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('--'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rank sort ranks the better TBA qualification rank first', (
    tester,
  ) async {
    final event = EventController(client: _FakeStatboticsClient());
    await event.setEventKey(_eventKey);
    final stats = await _statsController(
      const <String, num>{},
      rankings: _rankingsFor(<int, int>{971: 1, 3847: 5}),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayoffRankingScreen(
            eventController: event,
            scoutingController: ScoutingController(
              storage: FakeScoutingStorage(),
            ),
            configController: ScoutConfigController(
              service: FakeScoutConfigService(),
            ),
            statsController: stats,
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Rank').first,
      120,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rank').first);
    await tester.pumpAndSettle();

    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#5'), findsOneWidget);

    final rank971 = tester.getTopLeft(find.text('971')).dy;
    final rank3847 = tester.getTopLeft(find.text('3847')).dy;
    expect(rank971, lessThan(rank3847));

    expect(tester.takeException(), isNull);
  });

  testWidgets('does not show a Sections button', (tester) async {
    final event = EventController(client: _FakeStatboticsClient());
    await event.setEventKey(_eventKey);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayoffRankingScreen(
            eventController: event,
            scoutingController: ScoutingController(
              storage: FakeScoutingStorage(),
            ),
            configController: ScoutConfigController(
              service: FakeScoutConfigService(),
            ),
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sections'), findsNothing);
    expect(find.text('Event page'), findsNothing);
  });
}
