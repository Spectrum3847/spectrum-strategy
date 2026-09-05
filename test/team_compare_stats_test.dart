import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/team_compare_stats.dart';

ScoutEntry _entry(
  int team, {
  String matchId = 'session-uuid',
  String? tbaMatchKey,
  Map<String, dynamic> fieldValues = const <String, dynamic>{},
}) {
  return ScoutEntry(
    matchId: matchId,
    teamNumber: team,
    tbaMatchKey: tbaMatchKey,
    fieldValues: fieldValues,
  );
}

const _starting = ScoutConfigField(
  title: 'Robot Starting Position',
  type: ScoutFieldType.select,
  code: 'starting',
  choices: <String, String>{
    'Depot Trench': 'Depot Trench',
    'Outpost Trench': 'Outpost Trench',
  },
);

const _autoClimb = ScoutConfigField(
  title: 'Level 1 Climb',
  type: ScoutFieldType.select,
  code: 'auLow',
  choices: <String, String>{'N/A': 'Not Attempted', 'Successful': 'Successful'},
);

ScoutConfig _config() {
  return const ScoutConfig(
    title: 'Scout',
    sections: [
      ScoutConfigSection(name: 'Autonomous', fields: [_starting, _autoClimb]),
    ],
  );
}

void main() {
  group('TeamCompareStats.rowsFor', () {
    test('no entries for the team yields no rows', () {
      expect(
        TeamCompareStats.rowsFor(254, const <ScoutEntry>[], config: _config()),
        isEmpty,
      );
    });

    test('entries for other teams do not leak in', () {
      final rows = TeamCompareStats.rowsFor(254, [
        _entry(1678, tbaMatchKey: '2026txhou_qm1'),
      ], config: _config());
      expect(rows, isEmpty);
    });

    test('rows are ordered by match number ascending', () {
      final rows = TeamCompareStats.rowsFor(254, [
        _entry(254, tbaMatchKey: '2026txhou_qm3'),
        _entry(254, tbaMatchKey: '2026txhou_qm1'),
        _entry(254, tbaMatchKey: '2026txhou_qm2'),
      ], config: _config());
      expect(rows.map((r) => r.matchLabel), ['Match 1', 'Match 2', 'Match 3']);
    });

    test(
      'entries with no resolvable match number sort after resolved ones',
      () {
        final rows = TeamCompareStats.rowsFor(254, [
          _entry(254, matchId: 'a-session-uuid'),
          _entry(254, tbaMatchKey: '2026txhou_qm1'),
        ], config: _config());
        expect(rows.first.matchLabel, 'Match 1');
      },
    );

    test('a select field resolves its stored key to a label', () {
      final rows = TeamCompareStats.rowsFor(254, [
        _entry(
          254,
          tbaMatchKey: '2026txhou_qm1',
          fieldValues: {'starting': 'Depot Trench', 'auLow': 'Successful'},
        ),
      ], config: _config());
      expect(rows.single.startingPosition, 'Depot Trench');
      expect(rows.single.autoClimb, 'Successful');
    });

    test('a field the entry never recorded reads as a dash', () {
      final rows = TeamCompareStats.rowsFor(254, [
        _entry(254, tbaMatchKey: '2026txhou_qm1'),
      ], config: _config());
      expect(rows.single.startingPosition, '--');
      expect(rows.single.climbPosition, '--');
    });

    test('numeric fields parse, missing ones stay null', () {
      final rows = TeamCompareStats.rowsFor(254, [
        _entry(
          254,
          tbaMatchKey: '2026txhou_qm1',
          fieldValues: {'autoFuelScored': 5, 'teleopFuelScored': 30},
        ),
      ], config: _config());
      expect(rows.single.autoFuel, 5);
      expect(rows.single.teleopFuel, 30);
      expect(rows.single.fuelAccuracy, isNull);
    });

    test('boolean fields carry a real value, missing ones stay null', () {
      final rows = TeamCompareStats.rowsFor(254, [
        _entry(
          254,
          tbaMatchKey: '2026txhou_qm1',
          fieldValues: {'tRdefense': true},
        ),
      ], config: _config());
      expect(rows.single.defense, isTrue);
      expect(rows.single.passerPusher, isNull);
    });
  });

  group('TeamCompareStats.fuelSeries', () {
    test('pulls auto and teleop fuel in row order, gaps preserved as null', () {
      final rows = TeamCompareStats.rowsFor(254, [
        _entry(
          254,
          tbaMatchKey: '2026txhou_qm1',
          fieldValues: {'autoFuelScored': 5, 'teleopFuelScored': 20},
        ),
        _entry(254, tbaMatchKey: '2026txhou_qm2'),
      ], config: _config());
      final (auto, teleop) = TeamCompareStats.fuelSeries(rows);
      expect(auto, [5, null]);
      expect(teleop, [20, null]);
    });
  });
}
