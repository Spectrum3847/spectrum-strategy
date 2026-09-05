import 'dart:async' show Completer;
import 'dart:convert' show jsonEncode;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';

import 'package:spectrumstrategy/src/services/statbotics/event_data_cache.dart';

import 'support/fake_active_event_sync_service.dart';

class _UnwritableCache extends EventDataCache {
  @override
  Future<void> saveEventData(CachedEventData data) async {
    throw StateError('storage full');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  EventController controllerWith(
    Future<http.Response> Function(http.Request) handler, {
    Future<http.Response> Function(http.Request)? tbaHandler,
    DateTime Function()? clock,
    FakeActiveEventSyncService? syncService,
    bool statboticsEnabled = true,
  }) {
    return EventController(
      client: StatboticsClient(
        httpClient: MockClient(handler),
        sleep: (_) async {},
      ),
      tbaClient: tbaHandler == null
          ? null
          : TbaClient(
              config: InMemoryTbaConfig('test-key'),
              httpClient: MockClient(tbaHandler),
            ),
      clock: clock,
      syncService: syncService,
      statboticsEnabled: statboticsEnabled,
    );
  }

  const eventJson = '{"key":"2026txhou","name":"Houston","year":2026}';

  const teamEventsJson =
      '[{"team":3847,"event":"2026txhou","event_name":"Houston",'
      '"team_name":"Spectrum","year":2026,'
      '"record":{"qual":{"rank":1,"num_teams":40},'
      '"total":{"wins":1,"losses":0,"ties":0}},"epa":null}]';
  const matchesJson =
      '[{"key":"2026txhou_qm1","event":"2026txhou","match_number":1,'
      '"comp_level":"qm","alliances":{"red":{"team_keys":[3847]},'
      '"blue":{"team_keys":[118]}}}]';
  const teamsJson = '[{"team":3847,"name":"Spectrum"}]';

  Future<http.Response> healthyApi(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/event/2026txhou')) {
      return http.Response(eventJson, 200);
    }
    if (path.endsWith('/team_events')) {
      return http.Response(teamEventsJson, 200);
    }
    if (path.endsWith('/matches')) return http.Response(matchesJson, 200);
    if (path.endsWith('/teams')) return http.Response(teamsJson, 200);
    return http.Response('not found', 404);
  }

  Future<http.Response> statboticsEventList(http.Request request) async {
    if (request.url.path.endsWith('/events')) {
      return http.Response('[$eventJson]', 200);
    }
    return healthyApi(request);
  }

  test('loads all event data with no error or notice', () async {
    final controller = controllerWith(healthyApi);
    await controller.setEventKey('2026txhou');

    expect(controller.error, isNull);
    expect(controller.dataNotice, isNull);
    expect(controller.eventName, 'Houston');
    expect(controller.teamEvents, hasLength(1));
    expect(controller.matches, hasLength(1));
    expect(controller.teamNicknames[3847], 'Spectrum');
  });

  test('a full outage names the cause once and asks for a retry', () async {
    final controller = controllerWith(
      (request) async => http.Response('overloaded', 500),
    );
    await controller.setEventKey('2026txhou');

    expect(controller.error, contains('Could not load event data'));
    expect(controller.error, contains('Statbotics is busy (500)'));
    expect(controller.dataNotice, isNull);
  });

  test('a missing TBA key is named when the fallback cannot run', () async {
    final controller = EventController(
      client: StatboticsClient(
        httpClient: MockClient((_) async => http.Response('overloaded', 500)),
        sleep: (_) async {},
      ),
      tbaClient: TbaClient(
        config: InMemoryTbaConfig(),
        httpClient: MockClient((_) async => http.Response('unused', 200)),
      ),
      statboticsEnabled: true,
    );

    await controller.setEventKey('2026txhou');
    expect(controller.error, contains('Could not load event data'));
    expect(controller.error, contains('team TBA key'));

    await controller.loadEventsForYear(2026);
    expect(controller.eventsError, contains('Could not load the event list'));
    expect(controller.eventsError, contains('team TBA key'));
  });

  test('bootstrap does not block startup on the event fetch', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'selected_event_key': '2026txhou',
    });
    final gate = Completer<http.Response>();
    final controller = controllerWith((_) => gate.future);

    await controller.bootstrap().timeout(const Duration(seconds: 5));

    expect(controller.eventKey, '2026txhou');
    expect(controller.isLoading, isTrue);

    gate.complete(http.Response('overloaded', 500));
    while (controller.isLoading) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.error, contains('Could not load event data'));
  });

  test('an unreachable API reads as a network error', () async {
    final controller = controllerWith(
      (request) async => throw http.ClientException('connection refused'),
    );
    await controller.setEventKey('2026txhou');

    expect(controller.error, contains('network error'));
  });

  test(
    'a partial failure keeps the data that loaded and names the rest',
    () async {
      final controller = controllerWith((request) async {
        final path = request.url.path;
        if (path.endsWith('/matches')) {
          return http.Response('<html>gateway error</html>', 200);
        }
        return healthyApi(request);
      });
      await controller.setEventKey('2026txhou');

      expect(controller.teamEvents, hasLength(1));
      expect(controller.eventName, 'Houston');
      expect(controller.error, contains('match schedule'));
      expect(controller.error, contains('unexpected data'));
    },
  );

  test('a legacy v1 snapshot is not restored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'event_data_cache_v1:2026txhou': jsonEncode(<String, dynamic>{
        'eventName': 'Houston',
        'fetchedAt': DateTime.utc(2026, 8, 1).toIso8601String(),
        'teamEvents': <dynamic>[],
        'matches': <dynamic>[],
        'teamNicknames': <String, dynamic>{'1': 'The Juggernauts'},
      }),
    });
    final controller = controllerWith(
      (request) async => http.Response('down', 503),
    );
    await controller.setEventKey('2026txhou');

    expect(controller.teamNicknames, isEmpty);
    expect(controller.dataNotice, isNot(contains('cached')));
  });

  test('an offseason event is a notice even though /teams answers', () async {
    final controller = controllerWith((request) async {
      final path = request.url.path;
      if (path.endsWith('/event/2026txdri1')) {
        return http.Response('{}', 500);
      }
      if (path.endsWith('/teams')) {
        return http.Response('[{"team":1,"name":"The Juggernauts"}]', 200);
      }
      return http.Response('[]', 200);
    });
    await controller.setEventKey('2026txdri1');

    expect(controller.error, isNull);
    expect(controller.dataNotice, contains('offseason'));

    expect(controller.teamNicknames, isEmpty);
  });

  test(
    'an event Statbotics does not cover is a notice, not an error',
    () async {
      final controller = controllerWith((request) async {
        final path = request.url.path;
        if (path.endsWith('/event/2026offseason')) {
          return http.Response('not found', 404);
        }

        return http.Response('[]', 200);
      });
      await controller.setEventKey('2026offseason');

      expect(controller.error, isNull);
      expect(controller.dataNotice, contains('offseason'));
      expect(controller.eventName, '2026offseason');
    },
  );

  Future<http.Response> statboticsWithoutTheEvent(http.Request request) async {
    if (request.url.path.endsWith('/event/2026txdri1')) {
      return http.Response('{}', 500);
    }
    return http.Response('[]', 200);
  }

  const driEventJson =
      '{"key":"2026txdri1","name":"Dripping Springs Invitational","year":2026}';

  Future<http.Response> tbaWithTheEvent(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/matches/simple')) {
      return http.Response(
        '[{"key":"2026txdri1_qm1","match_number":1,"comp_level":"qm",'
        '"alliances":{"red":{"team_keys":["frc3847"]},'
        '"blue":{"team_keys":["frc118"]}}}]',
        200,
      );
    }
    if (path.endsWith('/teams/simple')) {
      return http.Response(
        '[{"key":"frc3847","team_number":3847,"nickname":"Spectrum",'
        '"name":"Spectrum full"}]',
        200,
      );
    }
    if (path.endsWith('/event/2026txdri1')) {
      return http.Response(driEventJson, 200);
    }
    return http.Response('not found', 404);
  }

  test(
    'a 500 on the event lookup alone is no coverage, not an outage',
    () async {
      final controller = controllerWith(statboticsWithoutTheEvent);
      await controller.setEventKey('2026txdri1');

      expect(controller.error, isNull);
      expect(controller.dataNotice, contains('no data for this event'));
      expect(controller.dataNotice, contains('offseason'));

      expect(controller.dataNotice, isNot(contains('unavailable')));
      expect(controller.dataNotice, isNot(contains('recovers')));
    },
  );

  test(
    'no Statbotics coverage still gets the name and schedule from TBA',
    () async {
      final controller = controllerWith(
        statboticsWithoutTheEvent,
        tbaHandler: tbaWithTheEvent,
      );
      await controller.setEventKey('2026txdri1');

      expect(controller.error, isNull);
      expect(controller.eventName, 'Dripping Springs Invitational');

      expect(controller.matches, hasLength(1));
      expect(controller.teamNicknames[3847], 'Spectrum');
      expect(controller.dataNotice, contains('The Blue Alliance'));
      expect(controller.dataNotice, isNot(contains('unavailable')));

      expect(controller.dataNotice, contains('event name'));
      expect(controller.dataNotice, contains('schedule'));
      expect(controller.dataNotice, contains('team names'));
    },
  );

  test('with no EPA the team list falls back to the TBA roster', () async {
    final controller = controllerWith(
      statboticsWithoutTheEvent,
      tbaHandler: tbaWithTheEvent,
    );
    await controller.setEventKey('2026txdri1');

    expect(controller.teamEvents, isEmpty);
    expect(controller.teamsAreRosterOnly, isTrue);
    expect(controller.displayTeams.map((t) => t.team), <int>[3847]);

    expect(controller.displayTeams.single.epa.totalPoints, isNull);
    expect(controller.displayTeams.single.event, '2026txdri1');
  });

  test('a roster fallback never replaces real Statbotics data', () async {
    final controller = controllerWith((request) async {
      if (request.url.path.endsWith('/team_events')) {
        return http.Response(
          '[{"team":254,"event":"2026txhou","event_name":"Houston",'
          '"year":2026,"record":{"qual":{"rank":2,"num_teams":40},'
          '"total":{"wins":8,"losses":1,"ties":0}},'
          '"epa":{"total_points":72.5,"unitless":1820.0,"norm":1755.0,'
          '"breakdown":{"auto_points":18.0,"teleop_points":45.0,'
          '"endgame_points":9.5}}}]',
          200,
        );
      }
      if (request.url.path.contains('/event/')) {
        return http.Response(
          '{"key":"2026txhou","name":"Houston","year":2026}',
          200,
        );
      }
      return http.Response('[]', 200);
    });
    await controller.setEventKey('2026txhou');

    expect(controller.teamsAreRosterOnly, isFalse);
    expect(controller.displayTeams, same(controller.teamEvents));
  });

  test(
    'the no-coverage notice only names what TBA actually returned',
    () async {
      final controller = controllerWith(
        statboticsWithoutTheEvent,
        tbaHandler: (request) async {
          final path = request.url.path;
          if (path.endsWith('/matches/simple')) {
            return http.Response('[]', 200);
          }
          return tbaWithTheEvent(request);
        },
      );
      await controller.setEventKey('2026txdri1');

      expect(controller.matches, isEmpty);
      expect(controller.dataNotice, contains('event name'));
      expect(controller.dataNotice, contains('team names'));
      expect(controller.dataNotice, isNot(contains('schedule')));
    },
  );

  test(
    'a failed event lookup next to real team stats stays an error',
    () async {
      final controller = controllerWith((request) async {
        final path = request.url.path;
        if (path.endsWith('/event/2026txhou')) {
          return http.Response('{}', 500);
        }
        if (path.endsWith('/team_events')) {
          return http.Response(teamEventsJson, 200);
        }
        if (path.endsWith('/matches')) return http.Response(matchesJson, 200);
        if (path.endsWith('/teams')) return http.Response(teamsJson, 200);
        return http.Response('not found', 404);
      });
      await controller.setEventKey('2026txhou');

      expect(controller.error, contains('event info'));
      expect(controller.dataNotice, isNot(contains('no data for this event')));
    },
  );
  test('a Statbotics-only failure is not a schedule error', () async {
    final controller = controllerWith((request) async {
      if (request.url.path.endsWith('/team_events')) {
        return http.Response('overloaded', 500);
      }
      return healthyApi(request);
    });
    await controller.setEventKey('2026txhou');

    expect(controller.matches, hasLength(1));
    expect(controller.error, contains('team stats'));
    expect(controller.scheduleError, isNull);
  });

  test('a schedule that no source could supply is a schedule error', () async {
    final controller = controllerWith((request) async {
      if (request.url.path.endsWith('/matches')) {
        return http.Response('overloaded', 500);
      }
      return healthyApi(request);
    });
    await controller.setEventKey('2026txhou');

    expect(controller.matches, isEmpty);
    expect(controller.scheduleError, isNotNull);
    expect(controller.scheduleError, contains('match schedule'));
  });

  test('event list failure names its cause', () async {
    final controller = controllerWith(
      (request) async => http.Response('overloaded', 503),
    );
    await controller.loadEventsForYear(2026);

    expect(controller.eventsError, contains('Statbotics is busy (503)'));
  });

  const tbaMatchesJson =
      '[{"key":"2026txhou_qm1","match_number":1,"comp_level":"qm",'
      '"alliances":{"red":{"team_keys":["frc3847","frc118"]},'
      '"blue":{"team_keys":["frc254"]}}}]';
  const tbaTeamsJson =
      '[{"key":"frc3847","team_number":3847,"nickname":"Spectrum",'
      '"name":"Spectrum full"}]';
  const tbaEventJson = '{"key":"2026txhou","name":"Houston","year":2026}';

  Future<http.Response> healthyTba(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/matches/simple')) {
      return http.Response(tbaMatchesJson, 200);
    }
    if (path.endsWith('/teams/simple')) {
      return http.Response(tbaTeamsJson, 200);
    }
    if (path.endsWith('/event/2026txhou')) {
      return http.Response(tbaEventJson, 200);
    }
    if (path.endsWith('/events/2026')) {
      return http.Response('[$tbaEventJson]', 200);
    }
    return http.Response('not found', 404);
  }

  test(
    'a Statbotics outage falls back to TBA for schedule and names',
    () async {
      final controller = controllerWith(
        (request) async => http.Response('down', 503),
        tbaHandler: healthyTba,
      );
      await controller.setEventKey('2026txhou');

      expect(controller.matches, hasLength(1));
      expect(controller.matches.single.redTeams, [3847, 118]);
      expect(controller.matches.single.blueTeams, [254]);
      expect(controller.teamNicknames[3847], 'Spectrum');
      expect(controller.eventName, 'Houston');
      expect(controller.teamEvents, isEmpty);
      expect(controller.error, isNull);
      expect(controller.dataNotice, contains('The Blue Alliance'));
      expect(controller.dataNotice, contains('EPA stats return'));

      expect(controller.scheduleError, isNull);
    },
  );

  test(
    'EPA and the rest come from the cache when everything is down',
    () async {
      final fetchedAt = DateTime.utc(2026, 7, 9, 8);

      final warm = controllerWith(healthyApi, clock: () => fetchedAt);
      await warm.setEventKey('2026txhou');
      expect(warm.error, isNull);

      final controller = controllerWith(
        (request) async => http.Response('down', 503),
        clock: () => fetchedAt.add(const Duration(hours: 3)),
      );
      await controller.setEventKey('2026txhou');

      expect(controller.teamEvents, hasLength(1));
      expect(controller.matches, hasLength(1));
      expect(controller.teamNicknames[3847], 'Spectrum');
      expect(controller.eventName, 'Houston');
      expect(controller.error, isNull);
      expect(controller.dataNotice, contains('cached'));
      expect(controller.dataNotice, contains('3 hours ago'));
    },
  );

  test('live TBA schedule merges with cached EPA in one notice', () async {
    final fetchedAt = DateTime.utc(2026, 7, 9, 8);
    final warm = controllerWith(healthyApi, clock: () => fetchedAt);
    await warm.setEventKey('2026txhou');

    final controller = controllerWith(
      (request) async => http.Response('down', 503),
      tbaHandler: healthyTba,
      clock: () => fetchedAt.add(const Duration(minutes: 30)),
    );
    await controller.setEventKey('2026txhou');

    expect(controller.matches.single.redTeams, [3847, 118]);
    expect(controller.teamEvents, hasLength(1));
    expect(controller.error, isNull);
    expect(controller.dataNotice, contains('The Blue Alliance'));
    expect(controller.dataNotice, contains('cached from 30 minutes ago'));
  });

  test('a TBA-supplied schedule survives into the cache', () async {
    final online = controllerWith(
      statboticsWithoutTheEvent,
      tbaHandler: tbaWithTheEvent,
    );
    await online.setEventKey('2026txdri1');
    expect(online.matches, hasLength(1));

    final offline = controllerWith(
      (request) async => throw http.ClientException('offline'),
    );
    await offline.setEventKey('2026txdri1');

    expect(offline.matches, hasLength(1));
    expect(offline.eventName, 'Dripping Springs Invitational');
    expect(offline.teamNicknames[3847], 'Spectrum');
  });

  test('re-caching after a cache-served recovery keeps the age', () async {
    final fetchedAt = DateTime.utc(2026, 7, 9, 8);
    final warm = controllerWith(healthyApi, clock: () => fetchedAt);
    await warm.setEventKey('2026txhou');

    final middle = controllerWith(
      (request) async => http.Response('down', 503),
      tbaHandler: healthyTba,
      clock: () => fetchedAt.add(const Duration(minutes: 30)),
    );
    await middle.setEventKey('2026txhou');
    expect(middle.dataNotice, contains('cached from 30 minutes ago'));

    final later = controllerWith(
      (request) async => http.Response('down', 503),
      tbaHandler: healthyTba,
      clock: () => fetchedAt.add(const Duration(hours: 1)),
    );
    await later.setEventKey('2026txhou');

    expect(later.dataNotice, contains('cached from 1 hour ago'));
    expect(later.dataNotice, isNot(contains('30 minutes ago')));
  });

  test('a failing cache write does not hang the fetch', () async {
    for (final handler in <Future<http.Response> Function(http.Request)>[
      healthyApi,
      (request) async => http.Response('down', 503),
    ]) {
      final controller = EventController(
        client: StatboticsClient(
          httpClient: MockClient(handler),
          sleep: (_) async {},
        ),
        cache: _UnwritableCache(),
        statboticsEnabled: true,
      );

      await controller.setEventKey('2026txhou');

      expect(controller.isLoading, isFalse);
    }
  });

  test('the event list adds the offseason events only TBA knows', () async {
    const offseason =
        '{"key":"2026txdri1","name":"Dripping Springs Invitational",'
        '"year":2026,"start_date":"2026-09-18"}';
    final controller = controllerWith(
      statboticsEventList,
      tbaHandler: (request) async => request.url.path.endsWith('/events/2026')
          ? http.Response('[$tbaEventJson,$offseason]', 200)
          : http.Response('not found', 404),
    );
    await controller.loadEventsForYear(2026);

    expect(controller.eventsError, isNull);
    expect(
      controller.availableEvents.map((e) => e.key),
      containsAll(<String>['2026txhou', '2026txdri1']),
    );

    expect(
      controller.availableEvents.where((e) => e.key == '2026txhou'),
      hasLength(1),
    );
  });

  test('a TBA miss costs the offseason events and nothing else', () async {
    final controller = controllerWith(
      statboticsEventList,
      tbaHandler: (request) async => http.Response('down', 503),
    );
    await controller.loadEventsForYear(2026);

    expect(controller.eventsError, isNull);
    expect(controller.availableEvents.single.key, '2026txhou');
  });

  test('the event list falls back to TBA, then to its cache', () async {
    final controller = controllerWith(
      (request) async => http.Response('down', 503),
      tbaHandler: healthyTba,
    );
    await controller.loadEventsForYear(2026);
    expect(controller.eventsError, isNull);
    expect(controller.availableEvents.single.key, '2026txhou');

    final offline = controllerWith(
      (request) async => http.Response('down', 503),
      tbaHandler: (request) async => http.Response('down', 503),
    );
    await offline.loadEventsForYear(2026);
    expect(offline.eventsError, isNull);
    expect(offline.availableEvents.single.name, 'Houston');
  });

  test('an event with a schedule but no team stats says so', () async {
    final controller = controllerWith((request) async {
      if (request.url.path.endsWith('/team_events')) {
        return http.Response('[]', 200);
      }
      return healthyApi(request);
    });
    await controller.setEventKey('2026txhou');

    expect(controller.error, isNull);
    expect(controller.teamEvents, isEmpty);
    expect(controller.matches, hasLength(1));
    expect(controller.dataNotice, contains('no team stats'));
    expect(controller.dataNotice, contains('2026txhou'));
  });

  test('an empty team list does not wipe cached EPA stats', () async {
    final fetchedAt = DateTime.utc(2026, 7, 9, 8);
    final warm = controllerWith(healthyApi, clock: () => fetchedAt);
    await warm.setEventKey('2026txhou');
    expect(warm.teamEvents, hasLength(1));

    final thin = controllerWith((request) async {
      if (request.url.path.endsWith('/team_events')) {
        return http.Response('[]', 200);
      }
      return healthyApi(request);
    }, clock: () => fetchedAt.add(const Duration(hours: 1)));
    await thin.setEventKey('2026txhou');
    expect(thin.teamEvents, isEmpty);

    final offline = controllerWith(
      (request) async => http.Response('down', 503),
      clock: () => fetchedAt.add(const Duration(hours: 3)),
    );
    await offline.setEventKey('2026txhou');

    expect(offline.teamEvents, hasLength(1));
    expect(offline.dataNotice, contains('cached'));

    expect(offline.dataNotice, contains('3 hours ago'));
  });

  test('re-selecting the current event refetches', () async {
    var teamEventCalls = 0;
    final controller = controllerWith((request) async {
      if (request.url.path.endsWith('/team_events')) {
        teamEventCalls++;
      }
      return healthyApi(request);
    });

    await controller.setEventKey('2026txhou');
    expect(teamEventCalls, 1);

    await controller.setEventKey('2026txhou');
    expect(teamEventCalls, 2);

    await controller.setEventKey('  2026txhou  ');
    expect(teamEventCalls, 3);
  });

  test('a refresh while one is already running does not stack', () async {
    final gate = Completer<http.Response>();
    final controller = controllerWith((_) => gate.future);

    final first = controller.setEventKey('2026txhou');
    await Future<void>.delayed(Duration.zero);
    expect(controller.isLoading, isTrue);

    await controller.refresh().timeout(const Duration(seconds: 1));

    gate.complete(http.Response('overloaded', 500));
    await first;
  });

  test('a TBA key TBA rejects is named in the error', () async {
    final controller = controllerWith(
      (request) async => http.Response('down', 503),
      tbaHandler: (request) async => http.Response('unauthorized', 401),
    );
    await controller.setEventKey('2026txhou');

    expect(controller.error, contains('rejected the team TBA key'));

    await controller.loadEventsForYear(2026);
    expect(controller.eventsError, contains('rejected the team TBA key'));
  });

  test('no TBA hint appears when the key works', () async {
    final controller = controllerWith(
      (request) async => http.Response('down', 503),
      tbaHandler: healthyTba,
    );
    await controller.setEventKey('2026txhou');

    expect(controller.error, isNull);
    expect(controller.dataNotice, isNot(contains('team TBA key')));
  });

  test(
    'a manual setEventKey pushes the key through the sync service',
    () async {
      final sync = FakeActiveEventSyncService();
      final controller = controllerWith(healthyApi, syncService: sync);
      await controller.bootstrap();

      expect(sync.pushedKeys, isEmpty);

      await controller.setEventKey('2026txhou');

      expect(controller.eventKey, '2026txhou');
      expect(sync.pushedKeys, ['2026txhou']);
    },
  );

  test('a remote event key switches the event and is not re-pushed', () async {
    final sync = FakeActiveEventSyncService();
    final controller = controllerWith(healthyApi, syncService: sync);
    await controller.bootstrap();
    expect(controller.eventKey, isEmpty);

    sync.emit('2026txdri1');

    await Future<void>.delayed(Duration.zero);
    while (controller.isLoading) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(controller.eventKey, '2026txdri1');
    expect(controller.eventName, '2026txdri1');

    expect(sync.pushedKeys, isEmpty);
  });

  group('the Statbotics switch', () {
    Future<http.Response> unreachableIfCalled(http.Request request) async {
      fail('Statbotics request fired while the switch is off: ${request.url}');
    }

    test('with the switch off, no request fires and TBA takes over', () async {
      final controller = controllerWith(
        unreachableIfCalled,
        tbaHandler: healthyTba,
        statboticsEnabled: false,
      );
      await controller.setEventKey('2026txhou');

      expect(controller.matches, hasLength(1));
      expect(controller.matches.single.redTeams, [3847, 118]);
      expect(controller.teamNicknames[3847], 'Spectrum');
      expect(controller.eventName, 'Houston');
      expect(controller.teamEvents, isEmpty);
      expect(controller.error, isNull);
    });

    test(
      'with the switch off, the source notice still names TBA (#1020)',
      () async {
        final controller = controllerWith(
          unreachableIfCalled,
          tbaHandler: healthyTba,
          statboticsEnabled: false,
        );
        await controller.setEventKey('2026txhou');

        expect(controller.dataNotice, contains('Statbotics is busy (500)'));
        expect(controller.dataNotice, contains('The Blue Alliance'));
        expect(controller.dataNotice, contains('EPA stats return'));
      },
    );

    test(
      'with the switch off, the event list request is skipped too',
      () async {
        final controller = controllerWith(
          unreachableIfCalled,
          tbaHandler: healthyTba,
          statboticsEnabled: false,
        );
        await controller.loadEventsForYear(2026);

        expect(controller.eventsError, isNull);
        expect(controller.availableEvents.single.key, '2026txhou');
      },
    );

    test(
      'with the switch off, cached EPA still serves with no TBA client',
      () async {
        final fetchedAt = DateTime.utc(2026, 7, 9, 8);
        final warm = controllerWith(healthyApi, clock: () => fetchedAt);
        await warm.setEventKey('2026txhou');
        expect(warm.error, isNull);

        final controller = controllerWith(
          unreachableIfCalled,
          clock: () => fetchedAt.add(const Duration(hours: 3)),
          statboticsEnabled: false,
        );
        await controller.setEventKey('2026txhou');

        expect(controller.teamEvents, hasLength(1));
        expect(controller.matches, hasLength(1));
        expect(controller.error, isNull);
        expect(controller.dataNotice, contains('cached'));
        expect(controller.dataNotice, contains('3 hours ago'));
      },
    );

    test(
      'with the switch on, a real outage still falls back exactly as before',
      () async {
        final controller = controllerWith(
          (request) async => http.Response('overloaded', 500),
          tbaHandler: healthyTba,
          statboticsEnabled: true,
        );
        await controller.setEventKey('2026txhou');

        expect(controller.matches, hasLength(1));
        expect(controller.dataNotice, contains('Statbotics is busy (500)'));
        expect(controller.dataNotice, contains('The Blue Alliance'));
      },
    );
  });

  group('myTeamNumber', () {
    test('is null until set', () async {
      final controller = controllerWith(healthyApi);
      await controller.bootstrap();

      expect(controller.myTeamNumber, isNull);
    });

    test('persists across a restart', () async {
      final controller = controllerWith(healthyApi);
      await controller.bootstrap();

      await controller.setMyTeamNumber(3847);
      expect(controller.myTeamNumber, 3847);

      final restarted = controllerWith(healthyApi);
      await restarted.bootstrap();
      expect(restarted.myTeamNumber, 3847);
    });

    test('clears back to null', () async {
      final controller = controllerWith(healthyApi);
      await controller.bootstrap();
      await controller.setMyTeamNumber(3847);

      await controller.setMyTeamNumber(null);

      expect(controller.myTeamNumber, isNull);
      final restarted = controllerWith(healthyApi);
      await restarted.bootstrap();
      expect(restarted.myTeamNumber, isNull);
    });
  });

  group('a Statbotics body the client cannot decode', () {
    Future<http.Response> undecodableTeamEvents(http.Request request) async {
      final path = request.url.path;
      if (path.endsWith('/team_events')) {
        return http.Response(
          '[{"team":3847,"event":"2026txhou","event_name":"Houston",'
          '"team_name":"Spectrum","year":2026,'
          '"epa":{"total_points":{"mean":72.5,"sd":3.0}}}]',
          200,
        );
      }
      return healthyApi(request);
    }

    test('degrades to TBA instead of surfacing an error', () async {
      final controller = controllerWith(
        undecodableTeamEvents,
        tbaHandler: healthyTba,
      );
      await controller.setEventKey('2026txhou');

      expect(controller.teamEvents, isEmpty);
      expect(controller.teamsAreRosterOnly, isTrue);
      expect(controller.displayTeams.map((t) => t.team), <int>[3847]);

      expect(controller.displayTeams.single.epa.totalPoints, isNull);
      expect(controller.error, isNull);
    });

    test('names the cause as bad data, not as an outage', () async {
      final controller = controllerWith(
        undecodableTeamEvents,
        tbaHandler: healthyTba,
      );
      await controller.setEventKey('2026txhou');

      expect(
        controller.dataNotice,
        contains('unexpected data from Statbotics'),
      );
      expect(controller.dataNotice, contains('The Blue Alliance'));
    });

    test('leaves the schedule alone', () async {
      final controller = controllerWith(
        undecodableTeamEvents,
        tbaHandler: healthyTba,
      );
      await controller.setEventKey('2026txhou');

      expect(controller.matches, hasLength(1));
      expect(controller.scheduleError, isNull);
    });
  });
}
