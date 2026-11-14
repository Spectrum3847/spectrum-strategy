import 'package:statbotics_client/statbotics_client.dart';

import '../models/pit_scout_entry.dart';
import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import 'match_info_stats.dart';
import 'robot_type.dart';
import 'team_summary_stats.dart';

class PlayoffMatchInfoEntry {
  const PlayoffMatchInfoEntry({required this.match, required this.opponents});

  final StatboticsMatch match;
  final List<MatchInfoRow> opponents;
}

class PlayoffMatchInfoStats {
  const PlayoffMatchInfoStats._();

  static const playoffLevels = <String>{'ef', 'qf', 'sf', 'f'};

  static List<StatboticsMatch> playoffMatchesFor(
    List<StatboticsMatch> matches,
    int? myTeamNumber,
  ) {
    if (myTeamNumber == null) return const <StatboticsMatch>[];
    return matches
        .where(
          (m) =>
              playoffLevels.contains(m.compLevel) &&
              (m.redTeams.contains(myTeamNumber) ||
                  m.blueTeams.contains(myTeamNumber)),
        )
        .toList(growable: false);
  }

  static List<MatchInfoRow> allianceRowsFor({
    required List<StatboticsMatch> matches,
    required int? myTeamNumber,
    required Iterable<ScoutEntry> scoutEntries,
    ScoutConfig? config,
    ScoutConfig? pitConfig,
    Map<int, String> teamNames = const <int, String>{},
    Map<int, PitScoutEntry> pitEntryByTeam = const <int, PitScoutEntry>{},
  }) {
    final ourMatches = playoffMatchesFor(matches, myTeamNumber);
    if (ourMatches.isEmpty || myTeamNumber == null) {
      return const <MatchInfoRow>[];
    }
    final first = ourMatches.first;
    final onRed = first.redTeams.contains(myTeamNumber);
    final teammates = (onRed ? first.redTeams : first.blueTeams)
        .where((team) => team != myTeamNumber)
        .toList(growable: false);
    return _rowsFor(
      teammates,
      scoutEntries: scoutEntries,
      config: config,
      pitConfig: pitConfig,
      teamNames: teamNames,
      pitEntryByTeam: pitEntryByTeam,
    );
  }

  static List<PlayoffMatchInfoEntry> build({
    required List<StatboticsMatch> matches,
    required int? myTeamNumber,
    required Iterable<ScoutEntry> scoutEntries,
    ScoutConfig? config,
    ScoutConfig? pitConfig,
    Map<int, String> teamNames = const <int, String>{},
    Map<int, PitScoutEntry> pitEntryByTeam = const <int, PitScoutEntry>{},
    bool Function(StatboticsMatch match)? isEliminatedAfter,
  }) {
    final ourMatches = playoffMatchesFor(matches, myTeamNumber);
    if (ourMatches.isEmpty || myTeamNumber == null) {
      return const <PlayoffMatchInfoEntry>[];
    }

    final entries = <PlayoffMatchInfoEntry>[];
    for (final match in ourMatches) {
      final onRed = match.redTeams.contains(myTeamNumber);
      final opponents = (onRed ? match.blueTeams : match.redTeams)
          .where((team) => team != myTeamNumber)
          .toList(growable: false);
      entries.add(
        PlayoffMatchInfoEntry(
          match: match,
          opponents: _rowsFor(
            opponents,
            scoutEntries: scoutEntries,
            config: config,
            pitConfig: pitConfig,
            teamNames: teamNames,
            pitEntryByTeam: pitEntryByTeam,
          ),
        ),
      );
      if (isEliminatedAfter?.call(match) ?? false) break;
    }
    return entries;
  }

  static List<MatchInfoRow> _rowsFor(
    List<int> teamNumbers, {
    required Iterable<ScoutEntry> scoutEntries,
    ScoutConfig? config,
    ScoutConfig? pitConfig,
    Map<int, String> teamNames = const <int, String>{},
    Map<int, PitScoutEntry> pitEntryByTeam = const <int, PitScoutEntry>{},
  }) {
    if (teamNumbers.isEmpty) return const <MatchInfoRow>[];
    final summaryByTeam = <int, TeamSummaryRow>{
      for (final row in TeamSummaryStats.build(
        scoutEntries,
        teamNumbers: teamNumbers,
        config: config,
      ))
        row.teamNumber: row,
    };
    final entriesByTeam = <int, List<ScoutEntry>>{};
    for (final entry in scoutEntries) {
      (entriesByTeam[entry.teamNumber] ??= <ScoutEntry>[]).add(entry);
    }
    return MatchInfoStats.rowsFor(
      teamNumbers,
      summaryByTeam: summaryByTeam,
      entriesByTeam: entriesByTeam,
      teleopField: _fieldFor(config, 'teleopFuelScored'),
      driveTrainField: _fieldFor(pitConfig, RobotType.driveTrainCode),
      teamNames: teamNames,
      pitEntryByTeam: pitEntryByTeam,
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
