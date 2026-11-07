import 'package:flutter_test/flutter_test.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/models/event_stat_table.dart';

void main() {
  TbaEventCoprs coprs([Map<String, dynamic>? json]) => TbaEventCoprs.fromJson(
    '2026txhou',
    json ??
        <String, dynamic>{
          'Total Coral Points': <String, dynamic>{
            'frc254': 45.2,
            'frc118': 30.0,
          },
          'foulPoints': <String, dynamic>{'frc254': 3.1, 'frc118': 2.0},
          'teleopCoralCount': <String, dynamic>{'frc254': 12.5},
        },
  );

  TbaEventOprs oprs([Map<String, dynamic>? json]) => TbaEventOprs.fromJson(
    '2026txhou',
    json ??
        <String, dynamic>{
          'oprs': <String, dynamic>{'frc254': 60.0, 'frc118': 40.0},
          'dprs': <String, dynamic>{'frc254': -5.0, 'frc118': -3.0},
          'ccwms': <String, dynamic>{'frc254': 65.0, 'frc118': 43.0},
        },
  );

  test('joins both endpoints into one set of columns', () {
    final table = EventStatTable.from(
      eventKey: '2026txhou',
      oprs: oprs(),
      coprs: coprs(),
    );

    expect(table.eventKey, '2026txhou');
    expect(table.isEmpty, isFalse);
    expect(table.valueFor(254, oprStatName), 60.0);
    expect(table.valueFor(254, 'foulPoints'), 3.1);
    expect(table.teams, <int>[118, 254]);
  });

  test('OPR, DPR and CCWM lead, then the breakdown in TBA order', () {
    final table = EventStatTable.from(
      eventKey: '2026txhou',
      oprs: oprs(),
      coprs: coprs(),
    );

    expect(table.statNames, <String>[
      oprStatName,
      dprStatName,
      ccwmStatName,
      'Total Coral Points',
      'foulPoints',
      'teleopCoralCount',
    ]);
  });

  test('a missing value stays null rather than becoming zero', () {
    final table = EventStatTable.from(
      eventKey: '2026txhou',
      oprs: oprs(),
      coprs: coprs(),
    );

    expect(table.valueFor(118, 'teleopCoralCount'), isNull);
    expect(table.valueFor(254, 'teleopCoralCount'), 12.5);
  });

  test('either endpoint may be missing on its own', () {
    final oprsOnly = EventStatTable.from(eventKey: '2026txhou', oprs: oprs());
    expect(oprsOnly.statNames, <String>[
      oprStatName,
      dprStatName,
      ccwmStatName,
    ]);

    final coprsOnly = EventStatTable.from(
      eventKey: '2026txhou',
      coprs: coprs(),
    );
    expect(coprsOnly.statNames, isNot(contains(oprStatName)));
    expect(coprsOnly.valueFor(254, 'foulPoints'), 3.1);

    final neither = EventStatTable.from(eventKey: '2026txhou');
    expect(neither.isEmpty, isTrue);
    expect(neither.teams, isEmpty);
  });

  test('a stat no team reports is not offered as a column', () {
    final table = EventStatTable.from(
      eventKey: '2026txhou',
      coprs: coprs(<String, dynamic>{
        'foulPoints': <String, dynamic>{'frc254': 3.1},
        'nobodyHasThis': <String, dynamic>{},
      }),
    );

    expect(table.statNames, <String>['foulPoints']);
  });

  test('a coprs stat cannot shadow the OPR from the other endpoint', () {
    final table = EventStatTable.from(
      eventKey: '2026txhou',
      oprs: oprs(),
      coprs: coprs(<String, dynamic>{
        'OPR': <String, dynamic>{'frc254': 999.0},
        'foulPoints': <String, dynamic>{'frc254': 3.1},
      }),
    );

    expect(table.valueFor(254, oprStatName), 60.0);
    expect(
      table.statNames.where((s) => s == oprStatName).length,
      1,
      reason: 'OPR must appear once, from /oprs',
    );
  });

  test('non-frc team keys are skipped rather than guessed at', () {
    final table = EventStatTable.from(
      eventKey: '2026txhou',
      coprs: coprs(<String, dynamic>{
        'foulPoints': <String, dynamic>{
          'frc254': 3.1,
          'notATeam': 1.0,
          'frcABC': 2.0,
        },
      }),
    );

    expect(table.teams, <int>[254]);
  });

  group('visibleColumns', () {
    test('keeps the table order, not the selection order', () {
      final table = EventStatTable.from(
        eventKey: '2026txhou',
        oprs: oprs(),
        coprs: coprs(),
      );

      expect(
        table.visibleColumns(<String>{'foulPoints', oprStatName}),
        <String>[oprStatName, 'foulPoints'],
      );
    });

    test('drops names this event does not report', () {
      final table = EventStatTable.from(eventKey: '2026txhou', coprs: coprs());

      expect(
        table.visibleColumns(<String>{'foulPoints', 'lastSeasonsStat'}),
        <String>['foulPoints'],
      );
    });

    test('an empty selection shows nothing', () {
      final table = EventStatTable.from(eventKey: '2026txhou', coprs: coprs());
      expect(table.visibleColumns(<String>{}), isEmpty);
    });
  });

  test('the default columns are curated, not the whole grid', () {
    expect(defaultStatColumns, <String>[oprStatName, 'foulPoints']);

    final table = EventStatTable.from(
      eventKey: '2026txhou',
      oprs: oprs(),
      coprs: coprs(),
    );
    expect(table.visibleColumns(defaultStatColumns.toSet()), <String>[
      oprStatName,
      'foulPoints',
    ]);
  });

  test('teamNumberFromKey parses frc keys and rejects the rest', () {
    expect(teamNumberFromKey('frc254'), 254);
    expect(teamNumberFromKey('frc3847'), 3847);
    expect(teamNumberFromKey('254'), isNull);
    expect(teamNumberFromKey('frc'), isNull);
    expect(teamNumberFromKey('frcABC'), isNull);
    expect(teamNumberFromKey(''), isNull);
  });
}
