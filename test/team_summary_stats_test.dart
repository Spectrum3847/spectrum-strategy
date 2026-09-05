import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/team_summary_stats.dart';

ScoutEntry _entry(
  int team, {
  String match = 'qm1',
  Map<String, dynamic> fieldValues = const <String, dynamic>{},
}) {
  return ScoutEntry(matchId: match, teamNumber: team, fieldValues: fieldValues);
}

const _teleopFuel = ScoutConfigField(
  title: 'Fuel Scored',
  type: ScoutFieldType.counter,
  code: 'teleopFuelScored',
);

const _autoFuel = ScoutConfigField(
  title: 'Fuel Scored',
  type: ScoutFieldType.counter,
  code: 'autoFuelScored',
);

const _autoClimb = ScoutConfigField(
  title: 'Level 1 Climb',
  type: ScoutFieldType.select,
  code: 'auLow',
  choices: <String, String>{
    'N/A': 'Not Attempted',
    'Failed': 'Failed',
    'Successful': 'Successful',
  },
);

ScoutConfigField _climbLevel(String code) => ScoutConfigField(
  title: 'Climb',
  type: ScoutFieldType.select,
  code: code,
  choices: const <String, String>{
    'N/A': 'Not Attempted',
    'Outpost': 'Outpost',
    'Middle': 'Middle',
    'Depot': 'Depot',
    'Failed': 'Failed',
    'Successful': 'Successful',
  },
  retiredChoiceKeys: const {'Failed', 'Successful'},
);

ScoutConfig _config({List<ScoutConfigField> fields = const []}) {
  return ScoutConfig(
    title: 'Scout',
    sections: [ScoutConfigSection(name: 'Auto', fields: fields)],
  );
}

void main() {
  group('TeamSummaryStats.build', () {
    test('empty entries and no teams yields no rows', () {
      final rows = TeamSummaryStats.build(
        const <ScoutEntry>[],
        teamNumbers: const <int>[],
        config: _config(),
      );
      expect(rows, isEmpty);
    });

    test('a team with no entries still gets a row, all null', () {
      final rows = TeamSummaryStats.build(
        const <ScoutEntry>[],
        teamNumbers: const [254],
        config: _config(fields: [_teleopFuel]),
      );
      expect(rows, hasLength(1));
      expect(rows.single.teamNumber, 254);
      expect(rows.single.iqmTeleop, isNull);
      expect(rows.single.maxTeleop, isNull);
    });

    test('a team only present in entries still appears (roster fallback)', () {
      final rows = TeamSummaryStats.build(
        [
          _entry(3847, fieldValues: {'teleopFuelScored': 10}),
        ],
        teamNumbers: const <int>[],
        config: _config(fields: [_teleopFuel]),
      );
      expect(rows.map((r) => r.teamNumber), [3847]);
    });

    test('rows are sorted by team number ascending', () {
      final rows = TeamSummaryStats.build(
        [_entry(9999), _entry(1)],
        teamNumbers: const [254],
        config: _config(),
      );
      expect(rows.map((r) => r.teamNumber), [1, 254, 9999]);
    });

    test('null config leaves every stat null', () {
      final rows = TeamSummaryStats.build(
        [
          _entry(254, fieldValues: {'teleopFuelScored': 10}),
        ],
        teamNumbers: const [254],
      );
      expect(rows.single.iqmTeleop, isNull);
      expect(rows.single.autoClimbRate, isNull);
    });

    test('a field code missing from the config leaves that stat null', () {
      final rows = TeamSummaryStats.build(
        [
          _entry(254, fieldValues: {'teleopFuelScored': 10}),
        ],
        teamNumbers: const [254],
        config: _config(fields: [_autoFuel]),
      );
      expect(rows.single.iqmTeleop, isNull);
    });

    group('IQM and max, small datasets', () {
      test('a single entry: IQM is that value, no quartile trim below 4', () {
        final rows = TeamSummaryStats.build(
          [
            _entry(254, match: 'qm1', fieldValues: {'teleopFuelScored': 7}),
          ],
          teamNumbers: const [254],
          config: _config(fields: [_teleopFuel]),
        );
        expect(rows.single.iqmTeleop, 7);
        expect(rows.single.maxTeleop, 7);
      });

      test('three entries (below the n=4 quartile cutoff): plain mean', () {
        final rows = TeamSummaryStats.build(
          [
            _entry(254, match: 'qm1', fieldValues: {'teleopFuelScored': 10}),
            _entry(254, match: 'qm2', fieldValues: {'teleopFuelScored': 20}),
            _entry(254, match: 'qm3', fieldValues: {'teleopFuelScored': 60}),
          ],
          teamNumbers: const [254],
          config: _config(fields: [_teleopFuel]),
        );
        expect(rows.single.iqmTeleop, 30);
        expect(rows.single.maxTeleop, 60);
      });

      test('four entries: exact quartile boundary trims the extremes', () {
        final rows = TeamSummaryStats.build(
          [
            _entry(254, match: 'qm1', fieldValues: {'teleopFuelScored': 1}),
            _entry(254, match: 'qm2', fieldValues: {'teleopFuelScored': 2}),
            _entry(254, match: 'qm3', fieldValues: {'teleopFuelScored': 3}),
            _entry(254, match: 'qm4', fieldValues: {'teleopFuelScored': 100}),
          ],
          teamNumbers: const [254],
          config: _config(fields: [_teleopFuel]),
        );

        expect(rows.single.iqmTeleop, 2.5);
        expect(rows.single.maxTeleop, 100);
      });

      test('an entry missing the field key does not count as a zero', () {
        final rows = TeamSummaryStats.build(
          [
            _entry(254, match: 'qm1', fieldValues: {'teleopFuelScored': 10}),
            _entry(254, match: 'qm2'),
          ],
          teamNumbers: const [254],
          config: _config(fields: [_teleopFuel]),
        );
        expect(rows.single.iqmTeleop, 10);
        expect(rows.single.maxTeleop, 10);
      });
    });

    group('climb success rates', () {
      test('auLow: only the literal "Successful" choice counts', () {
        final rows = TeamSummaryStats.build(
          [
            _entry(254, match: 'qm1', fieldValues: {'auLow': 'Successful'}),
            _entry(254, match: 'qm2', fieldValues: {'auLow': 'Failed'}),
            _entry(254, match: 'qm3', fieldValues: {'auLow': 'N/A'}),
          ],
          teamNumbers: const [254],
          config: _config(fields: [_autoClimb]),
        );
        expect(rows.single.autoClimbRate, closeTo(1 / 3, 1e-9));
      });

      test(
        'eLow: a named position or the retired Successful choice both count',
        () {
          final rows = TeamSummaryStats.build(
            [
              _entry(254, match: 'qm1', fieldValues: {'eLow': 'Outpost'}),
              _entry(254, match: 'qm2', fieldValues: {'eLow': 'Middle'}),
              _entry(254, match: 'qm3', fieldValues: {'eLow': 'Depot'}),

              _entry(254, match: 'qm4', fieldValues: {'eLow': 'Successful'}),

              _entry(254, match: 'qm5', fieldValues: {'eLow': 'Failed'}),
              _entry(254, match: 'qm6', fieldValues: {'eLow': 'N/A'}),
            ],
            teamNumbers: const [254],
            config: _config(fields: [_climbLevel('eLow')]),
          );
          expect(rows.single.lowClimbRate, closeTo(4 / 6, 1e-9));
        },
      );

      test('an entry missing the field key is excluded from the rate', () {
        final rows = TeamSummaryStats.build(
          [
            _entry(254, match: 'qm1', fieldValues: {'eMiddle': 'Outpost'}),
            _entry(254, match: 'qm2'),
          ],
          teamNumbers: const [254],
          config: _config(fields: [_climbLevel('eMiddle')]),
        );
        expect(rows.single.middleClimbRate, 1.0);
      });

      test('no entry carries the field: rate is null, not zero', () {
        final rows = TeamSummaryStats.build(
          [_entry(254, match: 'qm1')],
          teamNumbers: const [254],
          config: _config(fields: [_climbLevel('eHigh')]),
        );
        expect(rows.single.highClimbRate, isNull);
      });
    });

    test('per-team grouping keeps one team from leaking into another', () {
      final rows = TeamSummaryStats.build(
        [
          _entry(254, match: 'qm1', fieldValues: {'teleopFuelScored': 100}),
          _entry(1678, match: 'qm1', fieldValues: {'teleopFuelScored': 1}),
        ],
        teamNumbers: const [254, 1678],
        config: _config(fields: [_teleopFuel]),
      );
      final byTeam = {for (final r in rows) r.teamNumber: r};
      expect(byTeam[254]!.iqmTeleop, 100);
      expect(byTeam[1678]!.iqmTeleop, 1);
    });
  });

  group('TeamSummaryStats.gradeFractions', () {
    test('fewer than two present values grades nothing', () {
      final rows = TeamSummaryStats.build(
        [
          _entry(254, fieldValues: {'teleopFuelScored': 10}),
        ],
        teamNumbers: const [254, 1678],
        config: _config(fields: [_teleopFuel]),
      );
      expect(
        TeamSummaryStats.gradeFractions(rows, (r) => r.iqmTeleop),
        isEmpty,
      );
    });

    test('every present value tied grades nothing', () {
      final rows = TeamSummaryStats.build(
        [
          _entry(254, fieldValues: {'teleopFuelScored': 10}),
          _entry(1678, fieldValues: {'teleopFuelScored': 10}),
        ],
        teamNumbers: const [254, 1678],
        config: _config(fields: [_teleopFuel]),
      );
      expect(
        TeamSummaryStats.gradeFractions(rows, (r) => r.iqmTeleop),
        isEmpty,
      );
    });

    test('spread maps the lowest to 0 and the highest to 1', () {
      final rows = TeamSummaryStats.build(
        [
          _entry(1, fieldValues: {'teleopFuelScored': 0}),
          _entry(2, fieldValues: {'teleopFuelScored': 50}),
          _entry(3, fieldValues: {'teleopFuelScored': 100}),
        ],
        teamNumbers: const [1, 2, 3],
        config: _config(fields: [_teleopFuel]),
      );
      final fractions = TeamSummaryStats.gradeFractions(
        rows,
        (r) => r.iqmTeleop,
      );
      expect(fractions[1], 0);
      expect(fractions[2], 0.5);
      expect(fractions[3], 1);
    });

    test('a team with no value is absent from the fraction map', () {
      final rows = TeamSummaryStats.build(
        [
          _entry(1, fieldValues: {'teleopFuelScored': 0}),
          _entry(2, fieldValues: {'teleopFuelScored': 100}),
        ],
        teamNumbers: const [1, 2, 3],
        config: _config(fields: [_teleopFuel]),
      );
      final fractions = TeamSummaryStats.gradeFractions(
        rows,
        (r) => r.iqmTeleop,
      );
      expect(fractions.containsKey(3), isFalse);
    });
  });
}
