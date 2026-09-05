import '../models/pit_scout_entry.dart';
import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import '../models/team_analysis.dart';
import 'robot_type.dart';
import 'team_summary_stats.dart';

class RankedTeamRow {
  const RankedTeamRow({
    required this.teamNumber,
    this.teamName,
    this.iqmAuto,
    this.iqmTeleop,
  });

  final int teamNumber;
  final String? teamName;
  final double? iqmAuto;
  final double? iqmTeleop;
}

class ScoutingMeetingStats {
  const ScoutingMeetingStats._();

  static const _ryCardCode = 'ryCard';

  static List<RankedTeamRow> rankedTeams({
    required Iterable<ScoutEntry> scoutEntries,
    ScoutConfig? config,
    Map<int, String> teamNames = const <int, String>{},
  }) {
    final byTeam = <int, List<ScoutEntry>>{};
    for (final entry in scoutEntries) {
      (byTeam[entry.teamNumber] ??= <ScoutEntry>[]).add(entry);
    }
    if (byTeam.isEmpty) return const <RankedTeamRow>[];

    final analyses = <int, TeamAnalysis>{
      for (final team in byTeam.entries)
        team.key: TeamAnalysis.fromEntries(
          team.key,
          team.value,
          config: config,
        ),
    };
    final summaries = <int, TeamSummaryRow>{
      for (final row in TeamSummaryStats.build(
        scoutEntries,
        teamNumbers: byTeam.keys,
        config: config,
      ))
        row.teamNumber: row,
    };

    final teams = byTeam.keys.toList()
      ..sort((a, b) {
        final scoreA = analyses[a]?.iqmTotalScore ?? -1;
        final scoreB = analyses[b]?.iqmTotalScore ?? -1;
        final byScore = scoreB.compareTo(scoreA);
        if (byScore != 0) return byScore;
        return a.compareTo(b);
      });

    return <RankedTeamRow>[
      for (final team in teams)
        RankedTeamRow(
          teamNumber: team,
          teamName: teamNames[team],
          iqmAuto: summaries[team]?.iqmAuto,
          iqmTeleop: summaries[team]?.iqmTeleop,
        ),
    ];
  }

  static List<int> tankDrivetrainTeams({
    required Map<int, PitScoutEntry> pitEntryByTeam,
    ScoutConfig? pitConfig,
  }) {
    ScoutConfigField? driveTrainField;
    if (pitConfig != null) {
      for (final field in pitConfig.allFields) {
        if (field.code == RobotType.driveTrainCode) {
          driveTrainField = field;
          break;
        }
      }
    }
    final teams = <int>[];
    for (final entry in pitEntryByTeam.values) {
      final raw = entry.fieldValues[RobotType.driveTrainCode];
      if (raw == null) continue;
      final label = driveTrainField != null
          ? driveTrainField.labelForStored(raw)
          : raw.toString();
      if (label.toLowerCase().contains('tank')) teams.add(entry.teamNumber);
    }
    teams.sort();
    return teams;
  }

  static List<int> cardedTeams(Iterable<ScoutEntry> scoutEntries) {
    final teams = <int>{};
    for (final entry in scoutEntries) {
      final raw = entry.fieldValues[_ryCardCode];
      final carded = raw is bool
          ? raw
          : raw?.toString().toLowerCase() == 'true';
      if (carded) teams.add(entry.teamNumber);
    }
    final sorted = teams.toList()..sort();
    return sorted;
  }
}
