import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import 'match_info_stats.dart';
import 'team_summary_stats.dart';

class MatchPredictionTeamRow {
  const MatchPredictionTeamRow({
    required this.teamNumber,
    required this.iqmAuto,
    required this.iqmTeleop,
  });

  final int teamNumber;
  final double? iqmAuto;
  final double? iqmTeleop;

  double get total => (iqmAuto ?? 0) + (iqmTeleop ?? 0);
}

class MatchPredictionAlliance {
  const MatchPredictionAlliance({required this.teams});

  final List<MatchPredictionTeamRow> teams;

  double get total => teams.fold(0.0, (sum, row) => sum + row.total);
}

class MatchPredictionResult {
  const MatchPredictionResult({required this.red, required this.blue});

  final MatchPredictionAlliance red;
  final MatchPredictionAlliance blue;
}

class MatchPredictionStats {
  const MatchPredictionStats._();

  static const _teleopFuelCode = 'teleopFuelScored';

  static MatchPredictionResult build({
    required List<int> redTeams,
    required List<int> blueTeams,
    required Iterable<ScoutEntry> scoutEntries,
    ScoutConfig? config,
  }) {
    final entriesByTeam = <int, List<ScoutEntry>>{};
    for (final entry in scoutEntries) {
      (entriesByTeam[entry.teamNumber] ??= <ScoutEntry>[]).add(entry);
    }
    final allTeams = <int>{...redTeams, ...blueTeams};
    final summaryByTeam = <int, TeamSummaryRow>{
      for (final row in TeamSummaryStats.build(
        scoutEntries,
        teamNumbers: allTeams,
        config: config,
      ))
        row.teamNumber: row,
    };
    final teleopField = _fieldFor(config, _teleopFuelCode);

    final rowsByTeam = <int, MatchInfoRow>{
      for (final row in MatchInfoStats.rowsFor(
        allTeams.toList(growable: false),
        summaryByTeam: summaryByTeam,
        entriesByTeam: entriesByTeam,
        teleopField: teleopField,
      ))
        row.teamNumber: row,
    };

    MatchPredictionAlliance allianceFor(List<int> teams) {
      return MatchPredictionAlliance(
        teams: <MatchPredictionTeamRow>[
          for (final team in teams)
            MatchPredictionTeamRow(
              teamNumber: team,
              iqmAuto: rowsByTeam[team]?.iqmAuto,
              iqmTeleop: rowsByTeam[team]?.iqmFuel,
            ),
        ],
      );
    }

    return MatchPredictionResult(
      red: allianceFor(redTeams),
      blue: allianceFor(blueTeams),
    );
  }

  static ScoutConfigField? _fieldFor(ScoutConfig? config, String code) {
    if (config == null) return null;
    for (final field in config.allFields) {
      if (field.code == code) return field;
    }
    return null;
  }
}
