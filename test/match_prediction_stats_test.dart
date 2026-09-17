import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/match_prediction_stats.dart';

ScoutEntry _entry(int team, String code, num value, {String match = 'qm1'}) {
  return ScoutEntry(
    matchId: match,
    teamNumber: team,
    fieldValues: <String, dynamic>{code: value},
  );
}

const _teleopFuel = ScoutConfigField(
  title: 'Teleop Fuel Scored',
  type: ScoutFieldType.counter,
  code: 'teleopFuelScored',
);

const _autoFuel = ScoutConfigField(
  title: 'Auto Fuel Scored',
  type: ScoutFieldType.counter,
  code: 'autoFuelScored',
);

ScoutConfig _config() {
  return const ScoutConfig(
    title: 'Scout',
    sections: [
      ScoutConfigSection(name: 'Auto', fields: [_teleopFuel, _autoFuel]),
    ],
  );
}

void main() {
  group('MatchPredictionStats.build', () {
    test(
      'sums each alliance IQM auto plus IQM teleop across its three teams',
      () {
        final entries = <ScoutEntry>[
          _entry(1, 'autoFuelScored', 4, match: 'qm1'),
          _entry(1, 'teleopFuelScored', 10, match: 'qm1'),
          _entry(2, 'autoFuelScored', 2, match: 'qm1'),
          _entry(2, 'teleopFuelScored', 8, match: 'qm1'),
          _entry(3, 'autoFuelScored', 0, match: 'qm1'),
          _entry(3, 'teleopFuelScored', 6, match: 'qm1'),
          _entry(4, 'autoFuelScored', 1, match: 'qm1'),
          _entry(4, 'teleopFuelScored', 1, match: 'qm1'),
          _entry(5, 'autoFuelScored', 1, match: 'qm1'),
          _entry(5, 'teleopFuelScored', 1, match: 'qm1'),
          _entry(6, 'autoFuelScored', 1, match: 'qm1'),
          _entry(6, 'teleopFuelScored', 1, match: 'qm1'),
        ];

        final result = MatchPredictionStats.build(
          redTeams: const [1, 2, 3],
          blueTeams: const [4, 5, 6],
          scoutEntries: entries,
          config: _config(),
        );

        expect(result.red.total, 4 + 10 + 2 + 8 + 0 + 6);
        expect(result.blue.total, 1 + 1 + 1 + 1 + 1 + 1);
        expect(result.red.teams.map((r) => r.teamNumber), const [1, 2, 3]);
        expect(result.red.teams.first.iqmAuto, 4);
        expect(result.red.teams.first.iqmTeleop, 10);
        expect(result.red.teams.first.total, 14);
      },
    );

    test('a team with no scout entries contributes 0, not null', () {
      final result = MatchPredictionStats.build(
        redTeams: const [1, 2, 3],
        blueTeams: const [4, 5, 6],
        scoutEntries: const <ScoutEntry>[],
        config: _config(),
      );

      expect(result.red.total, 0);
      expect(result.blue.total, 0);
      for (final row in [...result.red.teams, ...result.blue.teams]) {
        expect(row.iqmAuto, isNull);
        expect(row.iqmTeleop, isNull);
        expect(row.total, 0);
      }
    });

    test('a null config yields zero totals rather than throwing', () {
      final result = MatchPredictionStats.build(
        redTeams: const [1, 2, 3],
        blueTeams: const [4, 5, 6],
        scoutEntries: <ScoutEntry>[_entry(1, 'teleopFuelScored', 10)],
      );

      expect(result.red.total, 0);
      expect(result.blue.total, 0);
    });
  });
}
