import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/services/scouted_win_chance.dart';
import 'package:spectrumstrategy/src/scouting/services/team_summary_stats.dart';

TeamSummaryRow _row(
  int team, {
  double mean = 20,
  double sd = 5,
  int samples = 4,
}) => TeamSummaryRow(
  teamNumber: team,
  meanAuto: mean / 2,
  meanTeleop: mean / 2,
  sdAuto: sd,
  sdTeleop: sd,
  autoSamples: samples,
  teleopSamples: samples,
);

void main() {
  test('normalCdf matches known values', () {
    expect(ScoutedWinChance.normalCdf(0), closeTo(0.5, 1e-7));
    expect(ScoutedWinChance.normalCdf(1), closeTo(0.841345, 1e-5));
    expect(ScoutedWinChance.normalCdf(-1.96), closeTo(0.024998, 1e-5));
  });

  test('equal alliances are a coin flip', () {
    final chance = ScoutedWinChance.from(
      redTeams: const [1, 2, 3],
      blueTeams: const [4, 5, 6],
      rows: [for (var t = 1; t <= 6; t++) _row(t)],
    );
    expect(chance.redWinProbability, closeTo(0.5, 1e-6));
    expect(chance.blueWinProbability, closeTo(0.5, 1e-6));
  });

  test('sums means and variances then takes the normal CDF', () {
    final rows = [
      for (var t = 1; t <= 3; t++) _row(t, mean: 30),
      for (var t = 4; t <= 6; t++) _row(t, mean: 20),
    ];

    final chance = ScoutedWinChance.from(
      redTeams: const [1, 2, 3],
      blueTeams: const [4, 5, 6],
      rows: rows,
    );
    expect(chance.redWinProbability, closeTo(0.9584, 1e-3));
  });

  test('a team with too few entries gives no estimate and is named', () {
    final chance = ScoutedWinChance.from(
      redTeams: const [1, 2, 3],
      blueTeams: const [4, 5, 6],
      rows: [
        for (var t = 1; t <= 6; t++)
          _row(t, samples: t == 5 ? ScoutedWinChance.minEntriesPerTeam - 1 : 4),
      ],
    );
    expect(chance.hasEstimate, isFalse);
    expect(chance.missingTeams, [5]);
  });

  test('a team with no row is missing', () {
    final chance = ScoutedWinChance.from(
      redTeams: const [1, 2, 3],
      blueTeams: const [4, 5, 6],
      rows: [for (var t = 1; t <= 5; t++) _row(t)],
    );
    expect(chance.missingTeams, [6]);
  });

  test('zero spread never reads as certain', () {
    final chance = ScoutedWinChance.from(
      redTeams: const [1, 2, 3],
      blueTeams: const [4, 5, 6],
      rows: [
        for (var t = 1; t <= 3; t++) _row(t, mean: 40, sd: 0),
        for (var t = 4; t <= 6; t++) _row(t, mean: 10, sd: 0),
      ],
    );
    expect(chance.redWinProbability, ScoutedWinChance.maxProbability);
  });
}
