import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouted_summary.dart';

final _config = ScoutConfig.fromJson(
  jsonDecode(File('assets/scout_config_default.json').readAsStringSync())
      as Map<String, dynamic>,
);

ScoutEntry _entry(int match, [Map<String, dynamic> values = const {}]) =>
    ScoutEntry(
      matchId: '',
      teamNumber: 100,
      tbaMatchKey: '2026test_qm$match',
      fieldValues: values,
    );

ScoutedSummary _build(List<ScoutEntry> entries) =>
    ScoutedSummaryBuilder.build(entries, config: _config);

List<String> _texts(List<ScoutedSummaryLine> lines) => [
  for (final l in lines) l.cited,
];

void main() {
  test('no entries gives an empty summary', () {
    final summary = _build(const []);
    expect(summary.isEmpty, isTrue);
    expect(summary.entryCount, 0);
  });

  group('incidents', () {
    test('deaths and cards cite their matches', () {
      final summary = _build([
        _entry(4, {'dieCard': true}),
        _entry(9, {'dieCard': true, 'ryCard': 'Red'}),
        _entry(12, {'ryCard': 'Yellow'}),
      ]);
      expect(
        _texts(summary.concerns),
        containsAll([
          'Died or disconnected (Q4, Q9)',
          'Red card (Q9)',
          'Yellow card (Q12)',
        ]),
      );
    });

    test('a clean team has no concerns', () {
      expect(_build([_entry(1), _entry(2)]).concerns, isEmpty);
    });
  });

  group('climb', () {
    Map<String, dynamic> climb(String high, {String low = 'Not Attempted'}) => {
      'eHigh': high,
      'eLow': low,
    };

    test('reliable climb names the usual level', () {
      final summary = _build([
        _entry(1, climb('Successful')),
        _entry(2, climb('Successful')),
        _entry(3, climb('Failed', low: 'Successful')),
        _entry(4, climb('Successful')),
      ]);
      expect(
        summary.strengths.single.text,
        'Reliable climb, 4 of 4 attempts, usually L3',
      );
    });

    test('unreliable climb cites the failed matches', () {
      final summary = _build([
        _entry(1, climb('Failed')),
        _entry(2, climb('Successful')),
        _entry(3, climb('Failed')),
        _entry(4, climb('Failed')),
      ]);
      expect(_texts(summary.concerns), [
        'Climb unreliable, 1 of 4 attempts (Q1, Q3, Q4)',
      ]);
    });

    test('too few attempts says nothing, and not attempted is not counted', () {
      final summary = _build([
        _entry(1, climb('Failed')),
        _entry(2, climb('Failed')),
        _entry(3, climb('Not Attempted')),
        _entry(4, climb('Not Attempted')),
      ]);
      expect(summary.strengths, isEmpty);
      expect(summary.concerns, isEmpty);
    });
  });

  group('defense', () {
    test('shows a role at 30 percent or more, from 2 entries', () {
      final summary = _build([
        _entry(1, {'tRdefense': true}),
        _entry(2),
        _entry(3, {'tRdefense': true}),
        _entry(4),
      ]);
      expect(_texts(summary.roles), ['Plays defense, 2 of 4 matches (Q1, Q3)']);
    });

    test('one entry is not enough', () {
      expect(
        _build([
          _entry(1, {'tRdefense': true}),
        ]).roles,
        isEmpty,
      );
    });
  });

  group('trend', () {
    List<ScoutEntry> series(List<int> fuel) => [
      for (var i = 0; i < fuel.length; i++)
        _entry(i + 1, {'teleopFuelScored': fuel[i]}),
    ];

    test('needs five scored entries', () {
      expect(_build(series([10, 10, 10, 30])).trend, isNull);
    });

    test('last 3 above the earlier ones is improving and cites them', () {
      final trend = _build(series([10, 10, 20, 20, 20])).trend!;
      expect(trend.direction, ScoutedTrend.improving);
      expect(trend.line.matches, ['Q3', 'Q4', 'Q5']);
      expect(trend.line.text, contains('20'));
    });

    test('last 3 below the earlier ones is declining', () {
      final trend = _build(series([30, 30, 10, 10, 10])).trend!;
      expect(trend.direction, ScoutedTrend.declining);
    });

    test('scoring after scoring nothing is improving', () {
      final trend = _build(series([0, 0, 5, 6, 5])).trend!;
      expect(trend.direction, ScoutedTrend.improving);
    });

    test('a small change is steady', () {
      final trend = _build(series([20, 20, 21, 20, 22])).trend!;
      expect(trend.direction, ScoutedTrend.steady);
    });

    test('entries are ordered by match, not by arrival', () {
      final entries = series([30, 30, 10, 10, 10]).reversed.toList();
      expect(_build(entries).trend!.direction, ScoutedTrend.declining);
    });
  });
}
