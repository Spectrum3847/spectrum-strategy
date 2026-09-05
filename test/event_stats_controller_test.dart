import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/models/event_stat_table.dart';
import 'package:spectrumstrategy/src/state/event_stats_controller.dart';

class _FakeTbaClient extends TbaClient {
  _FakeTbaClient({
    this.oprs,
    this.coprs,
    this.rankings,
    this.throwOprs = false,
    this.throwCoprs = false,
    this.throwRankings = false,
  }) : super(config: InMemoryTbaConfig('test-key'));

  TbaEventRankings? rankings;
  bool throwRankings;

  @override
  Future<TbaEventRankings?> getEventRankings(String eventKey) async {
    if (throwRankings) throw TbaApiException(500, 'boom');
    return rankings;
  }

  TbaEventOprs? oprs;
  TbaEventCoprs? coprs;

  bool throwOprs;
  bool throwCoprs;

  int oprsCalls = 0;
  int coprsCalls = 0;

  @override
  Future<TbaEventOprs?> getEventOprs(String eventKey) async {
    oprsCalls++;
    if (throwOprs) throw TbaApiException(500, 'boom');
    return oprs;
  }

  @override
  Future<TbaEventCoprs?> getEventCoprs(String eventKey) async {
    coprsCalls++;
    if (throwCoprs) throw TbaApiException(500, 'boom');
    return coprs;
  }
}

class _GatedTbaClient extends TbaClient {
  _GatedTbaClient() : super(config: InMemoryTbaConfig('test-key'));

  final Map<String, Completer<void>> gates = <String, Completer<void>>{};
  final Map<String, TbaEventOprs?> results = <String, TbaEventOprs?>{};

  Completer<void> gateFor(String eventKey) =>
      gates.putIfAbsent(eventKey, Completer<void>.new);

  @override
  Future<TbaEventOprs?> getEventOprs(String eventKey) async {
    await gateFor(eventKey).future;
    return results[eventKey];
  }

  @override
  Future<TbaEventCoprs?> getEventCoprs(String eventKey) async => null;

  final Map<String, TbaEventRankings?> rankings = <String, TbaEventRankings?>{};

  @override
  Future<TbaEventRankings?> getEventRankings(String eventKey) async =>
      rankings[eventKey];
}

TbaEventOprs _oprsFor(String eventKey, double opr) =>
    TbaEventOprs.fromJson(eventKey, <String, dynamic>{
      'oprs': <String, dynamic>{'frc254': opr},
      'dprs': <String, dynamic>{},
      'ccwms': <String, dynamic>{},
    });

TbaEventOprs _oprs() => TbaEventOprs.fromJson('2026txhou', <String, dynamic>{
  'oprs': <String, dynamic>{'frc254': 60.0, 'frc118': 40.0},
  'dprs': <String, dynamic>{'frc254': -5.0},
  'ccwms': <String, dynamic>{'frc254': 65.0},
});

TbaEventCoprs _coprs() => TbaEventCoprs.fromJson('2026txhou', <String, dynamic>{
  'foulPoints': <String, dynamic>{'frc254': 3.1, 'frc118': 2.0},
  'teleopCoralCount': <String, dynamic>{'frc254': 12.5},
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('loads both endpoints and joins them', () async {
    final client = _FakeTbaClient(oprs: _oprs(), coprs: _coprs());
    final controller = EventStatsController(tbaClient: client);
    await controller.bootstrap();

    await controller.load('2026txhou');

    expect(client.oprsCalls, 1);
    expect(client.coprsCalls, 1);
    expect(controller.isLoading, isFalse);
    expect(controller.error, isNull);
    expect(controller.table.valueFor(254, oprStatName), 60.0);
    expect(controller.table.valueFor(254, 'foulPoints'), 3.1);
  });

  test('one endpoint failing still shows the other', () async {
    final controller = EventStatsController(
      tbaClient: _FakeTbaClient(oprs: _oprs(), throwCoprs: true),
    );
    await controller.bootstrap();

    await controller.load('2026txhou');

    expect(controller.error, isNull);
    expect(controller.table.valueFor(254, oprStatName), 60.0);
    expect(controller.table.statNames, isNot(contains('foulPoints')));
  });

  test('both endpoints failing is an error naming them', () async {
    final controller = EventStatsController(
      tbaClient: _FakeTbaClient(throwOprs: true, throwCoprs: true),
    );
    await controller.bootstrap();

    await controller.load('2026txhou');

    expect(controller.error, contains('OPR'));
    expect(controller.error, contains('component OPR'));
    expect(controller.table.isEmpty, isTrue);
  });

  test('a previous failure does not colour the next load', () async {
    final client = _FakeTbaClient(throwOprs: true, throwCoprs: true);
    final controller = EventStatsController(tbaClient: client);
    await controller.bootstrap();

    await controller.load('2026txhou');
    expect(controller.error, isNotNull);

    client
      ..throwOprs = false
      ..throwCoprs = false
      ..oprs = _oprs()
      ..coprs = _coprs();

    await controller.load('2026txhou');

    expect(controller.error, isNull);
    expect(controller.table.valueFor(254, oprStatName), 60.0);
  });

  test('both endpoints 404 is empty, not an error', () async {
    final controller = EventStatsController(tbaClient: _FakeTbaClient());
    await controller.bootstrap();

    await controller.load('2026txhou');

    expect(controller.error, isNull);
    expect(controller.hasNoStats, isTrue);
  });

  test('no TBA client is a configuration error, not an empty table', () async {
    final controller = EventStatsController(tbaClient: null);
    await controller.bootstrap();

    await controller.load('2026txhou');

    expect(controller.error, contains('TBA API key'));
    expect(controller.isLoading, isFalse);
  });

  test('an empty event key clears rather than fetching', () async {
    final client = _FakeTbaClient(oprs: _oprs(), coprs: _coprs());
    final controller = EventStatsController(tbaClient: client);
    await controller.bootstrap();

    await controller.load('');

    expect(client.oprsCalls, 0);
    expect(controller.table.isEmpty, isTrue);
    expect(controller.error, isNull);
  });

  group('column selection', () {
    test('starts on the curated default', () async {
      final controller = EventStatsController(tbaClient: _FakeTbaClient());
      await controller.bootstrap();

      expect(controller.selectedColumns, defaultStatColumns.toSet());
    });

    test('toggling adds, removes, and persists', () async {
      final controller = EventStatsController(tbaClient: _FakeTbaClient());
      await controller.bootstrap();

      await controller.toggleColumn('teleopCoralCount');
      expect(controller.selectedColumns, contains('teleopCoralCount'));

      await controller.toggleColumn('teleopCoralCount');
      expect(controller.selectedColumns, isNot(contains('teleopCoralCount')));

      await controller.toggleColumn(dprStatName);

      final reloaded = EventStatsController(tbaClient: _FakeTbaClient());
      await reloaded.bootstrap();
      expect(reloaded.selectedColumns, contains(dprStatName));
    });

    test('an emptied selection survives a relaunch', () async {
      final controller = EventStatsController(tbaClient: _FakeTbaClient());
      await controller.bootstrap();
      for (final column in defaultStatColumns) {
        await controller.toggleColumn(column);
      }
      expect(controller.selectedColumns, isEmpty);

      final reloaded = EventStatsController(tbaClient: _FakeTbaClient());
      await reloaded.bootstrap();
      expect(reloaded.selectedColumns, isEmpty);
    });

    test('reset goes back to the default', () async {
      final controller = EventStatsController(tbaClient: _FakeTbaClient());
      await controller.bootstrap();
      await controller.toggleColumn('teleopCoralCount');
      await controller.toggleColumn(oprStatName);

      await controller.resetColumns();

      expect(controller.selectedColumns, defaultStatColumns.toSet());
    });

    test('visibleColumns hides stats the event does not report', () async {
      final controller = EventStatsController(
        tbaClient: _FakeTbaClient(oprs: _oprs(), coprs: _coprs()),
      );
      await controller.bootstrap();
      await controller.load('2026txhou');
      await controller.toggleColumn('lastSeasonsStat');

      expect(controller.selectedColumns, contains('lastSeasonsStat'));
      expect(controller.visibleColumns, <String>[oprStatName, 'foulPoints']);
    });
  });

  group('overlapping loads', () {
    test('a superseded load does not overwrite a newer one', () async {
      final client = _GatedTbaClient()
        ..results['eventA'] = _oprsFor('eventA', 10.0)
        ..results['eventB'] = _oprsFor('eventB', 99.0);
      final controller = EventStatsController(tbaClient: client);
      await controller.bootstrap();

      final loadA = controller.load('eventA');
      final loadB = controller.load('eventB');
      client.gateFor('eventB').complete();
      await loadB;
      expect(controller.table.valueFor(254, oprStatName), 99.0);

      client.gateFor('eventA').complete();
      await loadA;

      expect(
        controller.table.valueFor(254, oprStatName),
        99.0,
        reason: 'the stale load for eventA published over eventB',
      );
      expect(controller.table.eventKey, 'eventB');
    });
  });

  test('a failed bootstrap is not cached, so retry can recover', () async {
    final controller = EventStatsController(tbaClient: _FakeTbaClient());
    final first = controller.bootstrap();
    await first;

    expect(controller.bootstrap(), same(controller.bootstrap()));
  });

  test('the table seals its inner maps, not just the outer one', () async {
    final controller = EventStatsController(
      tbaClient: _FakeTbaClient(oprs: _oprs(), coprs: _coprs()),
    );
    await controller.bootstrap();
    await controller.load('2026txhou');

    expect(
      () => controller.table.valuesByStat[oprStatName]![254] = 0,
      throwsUnsupportedError,
    );
  });

  group('TBA rank and OPR', () {
    TbaEventRankings someRankings() =>
        TbaEventRankings.fromJson('2026txhou', <String, dynamic>{
          'sort_order_info': <Map<String, dynamic>>[
            <String, dynamic>{'name': 'Ranking Score'},
          ],
          'rankings': <Map<String, dynamic>>[
            <String, dynamic>{
              'rank': 1,
              'team_key': 'frc254',
              'record': <String, dynamic>{'wins': 8, 'losses': 2, 'ties': 0},
              'sort_orders': <num>[2.4],
            },
            <String, dynamic>{
              'rank': 7,
              'team_key': 'frc118',
              'record': <String, dynamic>{'wins': 5, 'losses': 5, 'ties': 0},
              'sort_orders': <num>[1.8],
            },
          ],
        });

    test('rank, record and OPR resolve per team', () async {
      final controller = EventStatsController(
        tbaClient: _FakeTbaClient(oprs: _oprs(), rankings: someRankings()),
      );
      await controller.bootstrap();
      await controller.load('2026txhou');

      expect(controller.rankFor(254), 1);
      expect(controller.recordFor(254), '8-2-0');
      expect(controller.rankFor(118), 7);

      expect(controller.oprFor(254), 60.0);
    });

    test('a team absent from the rankings is null, not zero', () async {
      final controller = EventStatsController(
        tbaClient: _FakeTbaClient(oprs: _oprs(), rankings: someRankings()),
      );
      await controller.bootstrap();
      await controller.load('2026txhou');

      expect(controller.rankFor(9999), isNull);
      expect(controller.recordFor(9999), isNull);
    });

    test('no rankings yet is null everywhere, not an error', () async {
      final controller = EventStatsController(
        tbaClient: _FakeTbaClient(oprs: _oprs()),
      );
      await controller.bootstrap();
      await controller.load('2026txhou');

      expect(controller.rankings, isNull);
      expect(controller.rankFor(254), isNull);
      expect(controller.error, isNull);

      expect(controller.oprFor(254), 60.0);
    });

    test('a rankings failure does not lose the OPRs', () async {
      final controller = EventStatsController(
        tbaClient: _FakeTbaClient(oprs: _oprs(), throwRankings: true),
      );
      await controller.bootstrap();
      await controller.load('2026txhou');

      expect(controller.rankFor(254), isNull);
      expect(controller.oprFor(254), 60.0);

      expect(controller.error, isNull);
    });

    test('a rank becomes a standing within the event', () async {
      final controller = EventStatsController(
        tbaClient: _FakeTbaClient(oprs: _oprs(), rankings: someRankings()),
      );
      addTearDown(controller.dispose);
      await controller.bootstrap();
      await controller.load('2026txhou');

      final top = controller.rankPercentileFor(254);
      expect(top, isNotNull);
      expect(top, inInclusiveRange(0, 1));
      expect(controller.rankPercentileFor(9999), isNull);
    });

    test('loading a new event clears the previous rankings', () async {
      final client = _FakeTbaClient(oprs: _oprs(), rankings: someRankings());
      final controller = EventStatsController(tbaClient: client);
      await controller.bootstrap();
      await controller.load('2026txhou');
      expect(controller.rankFor(254), 1);

      client.rankings = null;
      await controller.load('2026other');

      expect(controller.rankFor(254), isNull);
    });

    test('a new event drops the old metrics before the fetch lands', () async {
      final client = _GatedTbaClient();
      client.results['2026txhou'] = _oprsFor('2026txhou', 60);
      client.rankings['2026txhou'] = someRankings();
      client.results['2026other'] = _oprsFor('2026other', 20);
      final controller = EventStatsController(tbaClient: client);
      addTearDown(controller.dispose);
      await controller.bootstrap();

      final first = controller.load('2026txhou');
      client.gateFor('2026txhou').complete();
      await first;
      expect(controller.rankFor(254), 1);

      final second = controller.load('2026other');
      expect(controller.rankFor(254), isNull);
      expect(controller.oprFor(254), isNull);

      client.gateFor('2026other').complete();
      await second;
      expect(controller.oprFor(254), 20);
    });
  });
}
