import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/prescout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/prescout_summary_stats.dart';

PrescoutEntry _entry(
  int team, {
  int? autoFuel,
  int? teleopFuel,
  int? fuelAccuracy,
  String? autoClimb,
  String? lowClimb,
}) {
  return PrescoutEntry(
    teamNumber: team,
    fieldValues: <String, dynamic>{
      'autoFuelScored': ?autoFuel,
      'teleopFuelScored': ?teleopFuel,
      'fuelAccuracy': ?fuelAccuracy,
      'autoClimbL1': ?autoClimb,
      'lowClimbL1': ?lowClimb,
    },
  );
}

void main() {
  test(
    'builds one row per team number, filling in a roster team with no entries',
    () {
      final rows = PrescoutSummaryStats.build(
        <PrescoutEntry>[_entry(254, autoFuel: 4)],
        teamNumbers: <int>[254, 359],
      );

      expect(rows, hasLength(2));
      expect(rows[0].teamNumber, 254);
      expect(rows[0].matchesRecorded, 1);
      expect(rows[0].iqmAutoFuel, 4);
      expect(rows[1].teamNumber, 359);
      expect(rows[1].matchesRecorded, 0);
      expect(rows[1].iqmAutoFuel, isNull);
    },
  );

  test('climb success rate counts only "successful", not "na" or "failed"', () {
    final rows = PrescoutSummaryStats.build(
      <PrescoutEntry>[
        _entry(254, autoClimb: 'successful'),
        _entry(254, autoClimb: 'failed'),
        _entry(254, autoClimb: 'na'),
      ],
      teamNumbers: <int>[254],
    );

    expect(rows.single.autoClimbRate, closeTo(1 / 3, 1e-9));
  });

  test('a column with no recorded values is null, not zero', () {
    final rows = PrescoutSummaryStats.build(
      <PrescoutEntry>[_entry(254, autoFuel: 4)],
      teamNumbers: <int>[254],
    );

    expect(rows.single.lowClimbRate, isNull);
    expect(rows.single.avgFuelAccuracy, isNull);
  });

  test('gradeFractions spreads two distinct values across 0 and 1', () {
    final rows = PrescoutSummaryStats.build(
      <PrescoutEntry>[_entry(254, autoFuel: 10), _entry(359, autoFuel: 20)],
      teamNumbers: <int>[254, 359],
    );

    final fractions = PrescoutSummaryStats.gradeFractions(
      rows,
      (r) => r.iqmAutoFuel,
    );
    expect(fractions[254], 0);
    expect(fractions[359], 1);
  });

  test('gradeFractions is empty when fewer than two teams have a value', () {
    final rows = PrescoutSummaryStats.build(
      <PrescoutEntry>[_entry(254, autoFuel: 10)],
      teamNumbers: <int>[254, 359],
    );

    final fractions = PrescoutSummaryStats.gradeFractions(
      rows,
      (r) => r.iqmAutoFuel,
    );
    expect(fractions, isEmpty);
  });

  group('notesForTeam', () {
    test('reads the comments column, oldest first', () {
      final notes = PrescoutSummaryStats.notesForTeam(254, <PrescoutEntry>[
        PrescoutEntry(
          teamNumber: 254,
          fieldValues: const <String, dynamic>{
            'matchNumber': '9',
            'comments': 'Fast cycles.',
          },
          authorDisplayName: 'Ada',
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
        PrescoutEntry(
          teamNumber: 254,
          fieldValues: const <String, dynamic>{
            'matchNumber': '3',
            'comments': 'Jammed twice.',
          },
          authorDisplayName: 'Grace',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);

      expect(notes.map((n) => n.text), <String>[
        'Jammed twice.',
        'Fast cycles.',
      ]);
      expect(notes.first.matchId, '3');
      expect(notes.first.author, 'Grace');
    });

    test('skips other teams and blank comments', () {
      final notes = PrescoutSummaryStats.notesForTeam(254, <PrescoutEntry>[
        PrescoutEntry(
          teamNumber: 254,
          fieldValues: const <String, dynamic>{'comments': '   '},
        ),
        PrescoutEntry(
          teamNumber: 1678,
          fieldValues: const <String, dynamic>{'comments': 'Not this one.'},
        ),
      ]);

      expect(notes, isEmpty);
    });

    test('falls back to the entry id when no match number was recorded', () {
      final entry = PrescoutEntry(
        teamNumber: 254,
        fieldValues: const <String, dynamic>{'comments': 'Solid climb.'},
      );

      final notes = PrescoutSummaryStats.notesForTeam(254, <PrescoutEntry>[
        entry,
      ]);

      expect(notes.single.matchId, entry.id);
    });
  });
}
