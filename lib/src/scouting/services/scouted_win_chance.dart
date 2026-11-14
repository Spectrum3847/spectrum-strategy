import 'dart:math' show exp, sqrt;

import 'team_summary_stats.dart';

class ScoutedWinChance {
  const ScoutedWinChance({
    required this.redWinProbability,
    required this.missingTeams,
  });

  static const minEntriesPerTeam = 3;

  static const minProbability = 0.01;
  static const maxProbability = 0.99;

  final double? redWinProbability;

  final List<int> missingTeams;

  bool get hasEstimate => redWinProbability != null;

  double? get blueWinProbability =>
      redWinProbability == null ? null : 1 - redWinProbability!;

  static ScoutedWinChance from({
    required List<int> redTeams,
    required List<int> blueTeams,
    required Iterable<TeamSummaryRow> rows,
  }) {
    final byTeam = {for (final row in rows) row.teamNumber: row};
    final missing = <int>[];
    var redMean = 0.0;
    var blueMean = 0.0;
    var variance = 0.0;

    void add(int team, bool red) {
      final row = byTeam[team];
      if (row == null ||
          row.teleopSamples < minEntriesPerTeam ||
          row.autoSamples < minEntriesPerTeam ||
          row.meanTeleop == null ||
          row.meanAuto == null ||
          row.sdTeleop == null ||
          row.sdAuto == null) {
        missing.add(team);
        return;
      }
      final mean = row.meanTeleop! + row.meanAuto!;
      if (red) {
        redMean += mean;
      } else {
        blueMean += mean;
      }
      variance += row.sdTeleop! * row.sdTeleop! + row.sdAuto! * row.sdAuto!;
    }

    for (final team in redTeams) {
      add(team, true);
    }
    for (final team in blueTeams) {
      add(team, false);
    }
    if (missing.isNotEmpty) {
      return ScoutedWinChance(redWinProbability: null, missingTeams: missing);
    }
    final diff = redMean - blueMean;
    final sd = sqrt(variance);
    final raw = sd == 0
        ? (diff > 0 ? 1.0 : (diff < 0 ? 0.0 : 0.5))
        : normalCdf(diff / sd);
    return ScoutedWinChance(
      redWinProbability: raw.clamp(minProbability, maxProbability),
      missingTeams: const <int>[],
    );
  }

  static double normalCdf(double z) {
    final x = z.abs() / sqrt(2);
    final t = 1 / (1 + 0.3275911 * x);
    final poly =
        t *
        (0.254829592 +
            t *
                (-0.284496736 +
                    t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))));
    final erf = 1 - poly * exp(-x * x);
    return z >= 0 ? 0.5 * (1 + erf) : 0.5 * (1 - erf);
  }
}
