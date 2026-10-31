import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouter_opr.dart';

import 'support/scouter_opr_fixtures.dart';

ScouterScore _score(ScouterOprReport report, String name) =>
    report.scouts.singleWhere((s) => s.name == name);

ScouterOprReport _build(
  List<ScoutEntry> entries,
  List<OfficialAllianceFuel> official,
) => ScouterOpr.build(
  entries: entries,
  official: official,
  eventKey: '2026test',
);

void main() {
  group('solveRidge', () {
    test('recovers an exact noiseless system with lambda near zero', () {
      const truth = <double>[3, -2, 0.5, 5];
      final rows = <List<int>>[
        [0, 1, 2],
        [0, 1, 3],
        [0, 2, 3],
        [1, 2, 3],
        [0, 0, 1],
      ];
      final errors = <double>[
        for (final row in rows) row.fold(0.0, (sum, i) => sum + truth[i]),
      ];

      final b = ScouterOpr.solveRidge(rows, errors, 4, lambda: 1e-9);

      for (var i = 0; i < truth.length; i++) {
        expect(b[i], closeTo(truth[i], 1e-6));
      }
    });

    test('lambda 1 pulls a scout with one equation toward zero', () {
      final rows = <List<int>>[
        [0],
      ];
      final shrunk = ScouterOpr.solveRidge(rows, <double>[10], 1);
      final raw = ScouterOpr.solveRidge(rows, <double>[10], 1, lambda: 1e-9);

      expect(shrunk.single, closeTo(5, 1e-9));
      expect(raw.single, closeTo(10, 1e-6));
    });

    test('an unconstrained scout stays at zero instead of failing', () {
      final b = ScouterOpr.solveRidge(
        <List<int>>[
          [0],
        ],
        <double>[4],
        2,
        lambda: 0,
      );

      expect(b[0], closeTo(4, 1e-9));
      expect(b[1], 0);
    });
  });

  group('build over a rotated schedule', () {
    test('recovers three scouts with known miss rates', () {
      final random = Random(7);
      final scouts = <String>[for (var i = 0; i < 12; i++) 'Scout$i'];

      const miss = <String, int>{'Scout1': 15, 'Scout5': -8, 'Scout9': 5};

      final official = <OfficialAllianceFuel>[];
      final entries = <ScoutEntry>[];
      for (var m = 1; m <= 60; m++) {
        final order = [...scouts]..shuffle(random);
        for (var side = 0; side < 2; side++) {
          var allianceFuel = 0;
          final teams = <int>[];
          for (var slot = 0; slot < 3; slot++) {
            final scout = order[side * 3 + slot];
            final team = 1000 + m * 6 + side * 3 + slot;
            final truth = 20 + random.nextInt(41);
            final noise = random.nextInt(5) - 2;
            allianceFuel += truth;
            teams.add(team);
            entries.add(
              fuelEntry(m, team, scout, truth - (miss[scout] ?? 0) + noise),
            );
          }
          official.add(
            OfficialAllianceFuel(
              matchKey: '2026test_qm$m',
              compLevel: 'qm',
              matchNumber: m,
              alliance: side == 0 ? 'red' : 'blue',
              teams: teams,
              fuel: allianceFuel,
            ),
          );
        }
      }

      final report = _build(entries, official);

      expect(report.equations, 120);
      expect(report.skipped, 0);
      for (final scout in scouts) {
        expect(
          _score(report, scout).miss,
          closeTo((miss[scout] ?? 0).toDouble(), 2.5),
          reason: scout,
        );
      }
      expect(_score(report, 'Scout1').band, ScouterBand.coach);
      expect(_score(report, 'Scout5').miss, isNegative);
      expect(report.scouts.take(3).map((s) => s.name).toSet(), {
        'Scout1',
        'Scout5',
        'Scout9',
      });
    });
  });

  group('alliance selection', () {
    List<ScoutEntry> sixEntries([
      List<String?> scouts = const ['A', 'B', 'C', 'D', 'E', 'F'],
    ]) => <ScoutEntry>[
      for (var i = 0; i < 6; i++) fuelEntry(1, 100 + i, scouts[i], 20),
    ];

    final official = ScouterOpr.officialFuel([
      tbaMatch(
        1,
        red: [100, 101, 102],
        blue: [103, 104, 105],
        redFuel: 60,
        blueFuel: 60,
      ),
    ]);

    test('a complete match gives two equations', () {
      final report = _build(sixEntries(), official);

      expect(report.equations, 2);
      expect(report.scouts, hasLength(6));
      expect(report.averageCapture, closeTo(1, 1e-9));
    });

    test('a robot with two entries skips its alliance and counts it', () {
      final report = _build([
        ...sixEntries(),
        fuelEntry(1, 100, 'G', 25),
      ], official);

      expect(report.equations, 1);
      expect(report.skipped, 1);
      expect(report.scouts.map((s) => s.name), isNot(contains('G')));
    });

    test('a robot nobody scouted leaves the alliance incomplete', () {
      final report = _build(sixEntries().sublist(1), official);

      expect(report.equations, 1);
      expect(report.incomplete, 1);
      expect(report.skipped, 0);
    });

    test('an entry with no name at all makes its alliance unusable', () {
      final report = _build(
        sixEntries(<String?>[null, 'B', 'C', 'D', 'E', 'F']),
        official,
      );

      expect(report.equations, 1);
      expect(report.skipped, 1);
    });

    test('an entry with no fuel fields makes its alliance unusable', () {
      final entries = sixEntries();
      entries[0] = ScoutEntry(
        matchId: 'x',
        teamNumber: 100,
        tbaMatchKey: '2026test_qm1',
        fieldValues: const <String, dynamic>{'scouter': 'A'},
      );

      final report = _build(entries, official);

      expect(report.equations, 1);
      expect(report.skipped, 1);
    });

    test('the scout falls back to display name, then uid', () {
      final entries = <ScoutEntry>[
        fuelEntry(1, 100, null, 20, authorDisplayName: 'Dana'),
        fuelEntry(1, 101, null, 20, authorUid: 'uid-7'),
        fuelEntry(1, 102, 'C', 20, authorDisplayName: 'Ignored'),
        ...sixEntries().sublist(3),
      ];

      final names = _build(entries, official).scouts.map((s) => s.name);

      expect(names, containsAll(<String>['Dana', 'uid-7', 'C']));
      expect(names, isNot(contains('Ignored')));
    });

    test('entries from another event are ignored', () {
      final entries = <ScoutEntry>[
        for (var i = 0; i < 6; i++)
          fuelEntry(1, 100 + i, 'S$i', 20, matchKey: '2026other_qm1'),
      ];

      final report = _build(entries, official);

      expect(report.equations, 0);
      expect(report.incomplete, 2);
    });

    test('an entry without a TBA key is left out, since it could be from '
        'another event', () {
      final entries = <ScoutEntry>[
        for (var i = 0; i < 6; i++)
          ScoutEntry(
            matchId: '',
            teamNumber: 100 + i,
            fieldValues: <String, dynamic>{
              'scouter': 'S$i',
              'matchNumber': 1,
              'autoFuelScored': 5,
              'teleopFuelScored': 15,
            },
          ),
      ];

      final report = _build(entries, official);
      expect(report.equations, 0);
      expect(report.incomplete, 2);
    });

    test('an entry a lead keyed in by hand does not count', () {
      final report = _build([
        ...sixEntries().skip(1),
        ScoutEntry(
          matchId: '',
          teamNumber: 100,
          tbaMatchKey: '2026test_qm1',
          addedManually: true,
          fieldValues: const <String, dynamic>{
            'scouter': 'Lead',
            'autoFuelScored': 5,
            'teleopFuelScored': 15,
          },
        ),
      ], official);

      expect(report.equations, 1);
      expect(report.incomplete, 1);
      expect(report.scouts.map((s) => s.name), isNot(contains('Lead')));
    });

    test('a fuel value that is not a number makes its alliance unusable', () {
      final report = _build([
        ...sixEntries().skip(1),
        ScoutEntry(
          matchId: '',
          teamNumber: 100,
          tbaMatchKey: '2026test_qm1',
          fieldValues: const <String, dynamic>{
            'scouter': 'A',
            'autoFuelScored': 'abc',
            'teleopFuelScored': 15,
          },
        ),
      ], official);

      expect(report.equations, 1);
      expect(report.skipped, 1);
    });

    test('one scout covering two robots counts twice in that alliance', () {
      final report = _build([
        fuelEntry(1, 100, 'A', 10),
        fuelEntry(1, 101, 'A', 10),
        fuelEntry(1, 102, 'B', 20),
        ...sixEntries().skip(3),
      ], official);

      final a = report.scouts.firstWhere((s) => s.name == 'A');
      expect(report.equations, 2);
      expect(a.robots, 2);

      expect(a.miss, greaterThan(0));
      expect(
        a.miss,
        greaterThan(report.scouts.firstWhere((s) => s.name == 'B').miss),
      );
    });

    test('a missing robot outranks a duplicate when counting', () {
      final report = _build([
        fuelEntry(1, 100, 'A', 20),
        fuelEntry(1, 100, 'G', 20),
        fuelEntry(1, 101, 'B', 20),
        ...sixEntries().skip(3),
      ], official);

      expect(report.incomplete, 1);
      expect(report.skipped, 0);
    });

    test('a playoff entry needs its TBA key to match', () {
      final playoff = ScouterOpr.officialFuel([
        tbaMatch(
          1,
          compLevel: 'sf',
          key: '2026test_sf2m1',
          red: [100, 101, 102],
          blue: [103, 104, 105],
          redFuel: 60,
          blueFuel: 60,
        ),
      ]);
      final keyed = <ScoutEntry>[
        for (var i = 0; i < 6; i++)
          fuelEntry(1, 100 + i, 'S$i', 20, matchKey: '2026test_sf2m1'),
      ];
      final typed = <ScoutEntry>[
        for (var i = 0; i < 6; i++)
          ScoutEntry(
            matchId: '',
            teamNumber: 100 + i,
            fieldValues: <String, dynamic>{
              'scouter': 'S$i',
              'matchNumber': 'sf1',
              'autoFuelScored': 5,
              'teleopFuelScored': 15,
            },
          ),
      ];

      expect(_build(keyed, playoff).equations, 2);
      expect(_build(typed, playoff).equations, 0);
    });
  });

  group('officialFuel', () {
    test('reads hubScore.totalCount for each alliance', () {
      final fuel = ScouterOpr.officialFuel([
        tbaMatch(
          3,
          red: [1, 2, 3],
          blue: [4, 5, 6],
          redFuel: 120,
          blueFuel: 95,
        ),
      ]);

      expect(fuel.map((f) => (f.alliance, f.fuel)).toList(), [
        ('red', 120),
        ('blue', 95),
      ]);
      expect(fuel.first.teams, [1, 2, 3]);
      expect(fuel.last.teams, [4, 5, 6]);
      expect(fuel.first.matchKey, '2026test_qm3');
    });

    test('skips an alliance whose breakdown has no hubScore', () {
      final fuel = ScouterOpr.officialFuel([
        tbaMatch(1, red: [1, 2, 3], blue: [4, 5, 6], blueFuel: 50),
        tbaMatch(2, red: [1, 2, 3], blue: [4, 5, 6]),
      ]);

      expect(fuel, hasLength(1));
      expect(fuel.single.alliance, 'blue');
    });
  });

  group('names', () {
    test('normalizeName trims and collapses whitespace', () {
      expect(ScouterOpr.normalizeName('  Evan   S  '), 'Evan S');
    });

    test(
      '"Evan " and "evan" are one scout, shown as the commonest spelling',
      () {
        final entries = <ScoutEntry>[
          fuelEntry(1, 100, 'Evan ', 20),
          fuelEntry(1, 101, 'B', 20),
          fuelEntry(1, 102, 'C', 20),
          fuelEntry(1, 103, 'evan', 20),
          fuelEntry(1, 104, 'Evan', 20),
          fuelEntry(1, 105, 'F', 20),
        ];
        final official = ScouterOpr.officialFuel([
          tbaMatch(
            1,
            red: [100, 101, 102],
            blue: [103, 104, 105],
            redFuel: 60,
            blueFuel: 60,
          ),
        ]);

        final report = _build(entries, official);

        expect(report.scouts, hasLength(4));
        final evan = report.scouts.singleWhere(
          (s) => s.name.toLowerCase() == 'evan',
        );
        expect(evan.name, 'Evan');
        expect(evan.robots, 3);
      },
    );
  });

  group('scores', () {
    test('bands follow the size of the miss', () {
      ScouterBand band(double miss) =>
          ScouterScore(name: 'x', miss: miss, robots: 10).band;

      expect(band(4), ScouterBand.ok);
      expect(band(-4), ScouterBand.ok);
      expect(band(4.1), ScouterBand.checkIn);
      expect(band(-12), ScouterBand.checkIn);
      expect(band(12.1), ScouterBand.coach);
    });

    test('fewer than six robots is not enough data', () {
      expect(
        const ScouterScore(name: 'x', miss: 0, robots: 5).hasEnoughData,
        isFalse,
      );
      expect(
        const ScouterScore(name: 'x', miss: 0, robots: 6).hasEnoughData,
        isTrue,
      );
    });
  });
}
