import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/state/event_sections_controller.dart';

class _FakeTbaClient extends TbaClient {
  _FakeTbaClient() : super(config: InMemoryTbaConfig('test-key'));

  bool throwRankings = false;
  int rankingsCalls = 0;
  int alliancesCalls = 0;
  int awardsCalls = 0;
  int matchesCalls = 0;

  int detailedMatchesCalls = 0;
  int predictionsCalls = 0;

  @override
  Future<Map<String, TbaMatchPrediction>> getEventPredictions(
    String eventKey,
  ) async {
    predictionsCalls++;
    return <String, TbaMatchPrediction>{
      '${eventKey}_qm1': const TbaMatchPrediction(
        matchKey: 'qm1',
        redScore: 109.3,
        blueScore: 111.1,
        winningAlliance: 'blue',
        probability: 0.515,
      ),
    };
  }

  @override
  Future<List<TbaScheduleMatch>> getEventMatchesDetailed(
    String eventKey,
  ) async {
    detailedMatchesCalls++;
    return <TbaScheduleMatch>[
      TbaScheduleMatch.fromJson(<String, dynamic>{
        'key': '${eventKey}_qm1',
        'comp_level': 'qm',
        'match_number': 1,
        'winning_alliance': 'blue',
        'alliances': <String, dynamic>{
          'red': <String, dynamic>{
            'team_keys': <dynamic>['frc254'],
            'score': 61,
          },
          'blue': <String, dynamic>{
            'team_keys': <dynamic>['frc3847'],
            'score': 78,
          },
        },
        'videos': <dynamic>[
          <String, dynamic>{'type': 'youtube', 'key': 'abc123'},
        ],
        'score_breakdown': <String, dynamic>{
          'red': <String, dynamic>{'rp': 1},
          'blue': <String, dynamic>{'rp': 4},
        },
      }),
    ];
  }

  @override
  Future<List<TbaScheduleMatch>> getEventMatches(String eventKey) async {
    matchesCalls++;
    return <TbaScheduleMatch>[
      TbaScheduleMatch.fromJson(<String, dynamic>{
        'key': '${eventKey}_qm1',
        'comp_level': 'qm',
        'match_number': 1,
        'winning_alliance': 'blue',
        'actual_time': 1786000000,
        'alliances': <String, dynamic>{
          'red': <String, dynamic>{
            'team_keys': <dynamic>['frc254', 'frc118', 'frc2056'],
            'score': 61,
          },
          'blue': <String, dynamic>{
            'team_keys': <dynamic>['frc3847', 'frc1323', 'frc148'],
            'score': 78,
          },
        },
      }),
    ];
  }

  @override
  Future<TbaEventRankings?> getEventRankings(String eventKey) async {
    rankingsCalls++;
    if (throwRankings) throw TbaApiException(500, 'boom');
    return TbaEventRankings.fromJson(eventKey, <String, dynamic>{
      'rankings': <dynamic>[
        <String, dynamic>{
          'rank': 1,
          'team_key': 'frc254',
          'record': <String, dynamic>{'wins': 8, 'losses': 1, 'ties': 0},
          'matches_played': 9,
          'dq': 0,
          'qual_average': null,
          'sort_orders': <dynamic>[3.11, 42],
        },
      ],
      'sort_order_info': <dynamic>[
        <String, dynamic>{'name': 'Ranking Score'},
      ],
    });
  }

  @override
  Future<TbaEventAlliances?> getEventAlliances(String eventKey) async {
    alliancesCalls++;
    return TbaEventAlliances.fromJson(eventKey, <dynamic>[
      <String, dynamic>{
        'name': 'Alliance 1',
        'picks': <dynamic>['frc254', 'frc118', 'frc2056'],
        'status': <String, dynamic>{
          'status': 'won',
          'record': <String, dynamic>{'wins': 6, 'losses': 1, 'ties': 0},
        },
      },
    ]);
  }

  @override
  Future<TbaEventAwards?> getEventAwards(String eventKey) async {
    awardsCalls++;
    return TbaEventAwards.fromJson(eventKey, <dynamic>[
      <String, dynamic>{
        'name': 'Winner',
        'award_type': 1,
        'recipient_list': <dynamic>[
          <String, dynamic>{'team_key': 'frc254', 'awardee': null},
        ],
      },
    ]);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  EventSectionsController controllerWith(_FakeTbaClient client) {
    final controller = EventSectionsController(tbaClient: client);
    addTearDown(controller.dispose);
    return controller;
  }

  test('nothing is on by default, so nothing is fetched', () async {
    final client = _FakeTbaClient();
    final controller = controllerWith(client);
    await controller.bootstrap();

    expect(controller.visible, isEmpty);

    await controller.load('2026txhou');

    expect(client.rankingsCalls, 0);
    expect(client.alliancesCalls, 0);
    expect(client.awardsCalls, 0);
    expect(controller.error, isNull);
  });

  test('only the sections that are on get fetched', () async {
    final client = _FakeTbaClient();
    final controller = controllerWith(client);
    await controller.bootstrap();
    await controller.toggle(EventSection.rankings);

    await controller.load('2026txhou');

    expect(client.rankingsCalls, 1);
    expect(client.alliancesCalls, 0);
    expect(controller.rankings?.rankings.single.rank, 1);
    expect(controller.rankings?.sortOrderNames.first, 'Ranking Score');
  });

  test('showAll turns on every section', () async {
    final client = _FakeTbaClient();
    final controller = controllerWith(client);
    await controller.bootstrap();
    await controller.showAll();

    await controller.load('2026txhou');

    expect(controller.visible, EventSection.values.toSet());
    expect(controller.alliances?.alliances.single.picks.first, 'frc254');
    expect(controller.awards?.awards.single.name, 'Winner');
  });

  test('predictions are fetched only when their section is on', () async {
    final client = _FakeTbaClient();
    final controller = controllerWith(client);
    await controller.bootstrap();
    await controller.toggle(EventSection.rankings);

    await controller.load('2026txhou');
    expect(client.predictionsCalls, 0);
    expect(controller.predictionFor('2026txhou_qm1'), isNull);

    await controller.toggle(EventSection.predictedScores);
    await controller.load('2026txhou');

    expect(client.predictionsCalls, 1);
    expect(controller.predictionFor('2026txhou_qm1')?.winningAlliance, 'blue');
  });

  test('turning predictions off drops them', () async {
    final client = _FakeTbaClient();
    final controller = controllerWith(client);
    await controller.bootstrap();
    await controller.toggle(EventSection.predictedScores);
    await controller.load('2026txhou');
    expect(controller.predictionFor('2026txhou_qm1'), isNotNull);

    await controller.toggle(EventSection.predictedScores);

    expect(controller.predictionFor('2026txhou_qm1'), isNull);
  });

  test('one endpoint failing does not lose the others', () async {
    final client = _FakeTbaClient()..throwRankings = true;
    final controller = controllerWith(client);
    await controller.bootstrap();
    await controller.showAll();

    await controller.load('2026txhou');

    expect(controller.rankings, isNull);
    expect(controller.alliances, isNotNull);
    expect(controller.awards, isNotNull);
    expect(controller.error, contains('rankings'));
  });

  test('the selection survives a relaunch', () async {
    final first = controllerWith(_FakeTbaClient());
    await first.bootstrap();
    await first.toggle(EventSection.awards);

    final second = controllerWith(_FakeTbaClient());
    await second.bootstrap();

    expect(second.visible, <EventSection>{EventSection.awards});
  });

  test('an emptied selection survives too, rather than reverting', () async {
    final first = controllerWith(_FakeTbaClient());
    await first.bootstrap();
    await first.showAll();
    await first.hideAll();

    final second = controllerWith(_FakeTbaClient());
    await second.bootstrap();

    expect(second.visible, isEmpty);
  });

  test('turning a section off drops the data it was showing', () async {
    final controller = controllerWith(_FakeTbaClient());
    await controller.bootstrap();
    await controller.showAll();
    await controller.load('2026txhou');

    await controller.toggle(EventSection.awards);

    expect(controller.awards, isNull);
    expect(controller.alliances, isNotNull);
  });

  test('a stale event key is not published over a newer one', () async {
    final controller = controllerWith(_FakeTbaClient());
    await controller.bootstrap();
    await controller.showAll();

    final first = controller.load('2026txhou');
    final second = controller.load('2026mibel');
    await Future.wait<void>([first, second]);

    expect(controller.rankings?.eventKey, '2026mibel');
  });

  test('an empty event key clears rather than fetching', () async {
    final client = _FakeTbaClient();
    final controller = controllerWith(client);
    await controller.bootstrap();
    await controller.showAll();
    await controller.load('2026txhou');

    await controller.load('');

    expect(controller.rankings, isNull);
    expect(controller.isLoading, isFalse);
  });

  test('no TBA client is a configuration error, not an empty page', () async {
    final controller = EventSectionsController(tbaClient: null);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.showAll();

    await controller.load('2026txhou');

    expect(controller.error, contains('TBA API key'));
  });

  test('a section name removed in a later version is ignored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tba_sections_v1': <String>['rankings', 'somethingRemoved'],
    });
    final controller = controllerWith(_FakeTbaClient());

    await controller.bootstrap();

    expect(controller.visible, <EventSection>{EventSection.rankings});
  });

  group('match results', () {
    test('the section is off by default, so no matches are fetched', () async {
      final client = _FakeTbaClient();
      final controller = controllerWith(client);
      await controller.bootstrap();

      await controller.load('2026txhou');

      expect(client.matchesCalls, 0);
      expect(controller.matchFor('2026txhou_qm1'), isNull);
    });

    test('turning it on loads scores and the winner, keyed by match', () async {
      final client = _FakeTbaClient();
      final controller = controllerWith(client);
      await controller.bootstrap();
      await controller.toggle(EventSection.matchResults);

      await controller.load('2026txhou');

      expect(client.matchesCalls, 1);

      final match = controller.matchFor('2026txhou_qm1');
      expect(match, isNotNull);
      expect(match!.redScore, 61);
      expect(match.blueScore, 78);
      expect(match.winningAlliance, 'blue');
      expect(match.actualTime, isNotNull);

      expect(client.rankingsCalls, 0);
    });

    test(
      'turning it off with another section still on drops the matches',
      () async {
        final client = _FakeTbaClient();
        final controller = controllerWith(client);
        await controller.bootstrap();
        await controller.toggle(EventSection.matchResults);
        await controller.toggle(EventSection.rankings);
        await controller.load('2026txhou');
        expect(controller.matchFor('2026txhou_qm1'), isNotNull);

        await controller.toggle(EventSection.matchResults);

        expect(controller.matchFor('2026txhou_qm1'), isNull);
        expect(controller.rankings, isNotNull);
      },
    );

    test('turning it back off drops the loaded matches', () async {
      final client = _FakeTbaClient();
      final controller = controllerWith(client);
      await controller.bootstrap();
      await controller.toggle(EventSection.matchResults);
      await controller.load('2026txhou');
      expect(controller.matchFor('2026txhou_qm1'), isNotNull);

      await controller.toggle(EventSection.matchResults);
      await controller.load('2026txhou');

      expect(controller.matchFor('2026txhou_qm1'), isNull);
    });
  });

  group('the detailed match payload', () {
    test('scores alone use the cheap endpoint', () async {
      final client = _FakeTbaClient();
      final controller = controllerWith(client);
      await controller.bootstrap();
      await controller.toggle(EventSection.matchResults);

      await controller.load('2026txhou');

      expect(client.matchesCalls, 1);
      expect(client.detailedMatchesCalls, 0);
    });

    test('videos or ranking points switch to the full endpoint', () async {
      final client = _FakeTbaClient();
      final controller = controllerWith(client);
      await controller.bootstrap();
      await controller.toggle(EventSection.matchVideos);

      await controller.load('2026txhou');

      expect(client.detailedMatchesCalls, 1);
      expect(client.matchesCalls, 0);
      final match = controller.matchFor('2026txhou_qm1');
      expect(match?.videos.single.key, 'abc123');
      expect(match?.scoreBreakdown['blue']?['rp'], 4);
    });

    test('three match sections still cost one request', () async {
      final client = _FakeTbaClient();
      final controller = controllerWith(client);
      await controller.bootstrap();
      await controller.toggle(EventSection.matchResults);
      await controller.toggle(EventSection.matchVideos);
      await controller.toggle(EventSection.rankingPoints);

      await controller.load('2026txhou');

      expect(client.detailedMatchesCalls, 1);
      expect(client.matchesCalls, 0);
    });

    test(
      'matches survive turning off only one of the match sections',
      () async {
        final client = _FakeTbaClient();
        final controller = controllerWith(client);
        await controller.bootstrap();
        await controller.toggle(EventSection.matchResults);
        await controller.toggle(EventSection.rankingPoints);
        await controller.load('2026txhou');

        await controller.toggle(EventSection.rankingPoints);

        expect(controller.matchFor('2026txhou_qm1'), isNotNull);
      },
    );
  });
}
