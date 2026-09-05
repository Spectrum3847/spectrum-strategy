import 'package:statbotics_client/statbotics_client.dart';

import '../models/pit_scout_entry.dart';
import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import 'robot_type.dart';
import 'team_summary_stats.dart';

class MatchInfoRow {
  const MatchInfoRow({
    required this.teamNumber,
    this.teamName,
    this.robotType = '',
    this.maxAuto,
    this.iqmAuto,
    this.teleopAverage,
    this.iqmFuel,
    this.maxTeleop,
    this.everClimbedAutoL1 = false,
  });

  final int teamNumber;
  final String? teamName;
  final String robotType;

  final double? maxAuto;
  final double? iqmAuto;

  final double? teleopAverage;
  final double? iqmFuel;
  final double? maxTeleop;

  final bool everClimbedAutoL1;
}

class MatchInfoEntry {
  const MatchInfoEntry({
    required this.match,
    required this.preMatch,
    required this.opponents,
  });

  final StatboticsMatch match;
  final List<MatchInfoRow> preMatch;
  final List<MatchInfoRow> opponents;
}

class MatchInfoStats {
  const MatchInfoStats._();

  static const _teleopFuelCode = 'teleopFuelScored';

  static List<MatchInfoEntry> build({
    required List<StatboticsMatch> matches,
    required int? myTeamNumber,
    required Iterable<ScoutEntry> scoutEntries,
    ScoutConfig? config,
    ScoutConfig? pitConfig,
    Map<int, String> teamNames = const <int, String>{},
    Map<int, PitScoutEntry> pitEntryByTeam = const <int, PitScoutEntry>{},
  }) {
    if (myTeamNumber == null) return const <MatchInfoEntry>[];
    final ourMatches = matches
        .where(
          (m) =>
              m.redTeams.contains(myTeamNumber) ||
              m.blueTeams.contains(myTeamNumber),
        )
        .toList(growable: false);
    if (ourMatches.isEmpty) return const <MatchInfoEntry>[];

    final allTeams = <int>{
      for (final m in ourMatches) ...m.redTeams,
      for (final m in ourMatches) ...m.blueTeams,
    };
    final summaryByTeam = <int, TeamSummaryRow>{
      for (final row in TeamSummaryStats.build(
        scoutEntries,
        teamNumbers: allTeams,
        config: config,
      ))
        row.teamNumber: row,
    };
    final entriesByTeam = <int, List<ScoutEntry>>{};
    for (final entry in scoutEntries) {
      (entriesByTeam[entry.teamNumber] ??= <ScoutEntry>[]).add(entry);
    }
    final teleopField = _fieldFor(config, _teleopFuelCode);
    final driveTrainField = _fieldFor(pitConfig, RobotType.driveTrainCode);

    return <MatchInfoEntry>[
      for (final match in ourMatches)
        _entryFor(
          match,
          myTeamNumber,
          summaryByTeam: summaryByTeam,
          entriesByTeam: entriesByTeam,
          teleopField: teleopField,
          driveTrainField: driveTrainField,
          teamNames: teamNames,
          pitEntryByTeam: pitEntryByTeam,
        ),
    ];
  }

  static MatchInfoEntry _entryFor(
    StatboticsMatch match,
    int myTeamNumber, {
    required Map<int, TeamSummaryRow> summaryByTeam,
    required Map<int, List<ScoutEntry>> entriesByTeam,
    required ScoutConfigField? teleopField,
    required ScoutConfigField? driveTrainField,
    required Map<int, String> teamNames,
    required Map<int, PitScoutEntry> pitEntryByTeam,
  }) {
    final onRed = match.redTeams.contains(myTeamNumber);
    final ourAlliance = onRed ? match.redTeams : match.blueTeams;
    final theirAlliance = onRed ? match.blueTeams : match.redTeams;

    final teammates = ourAlliance
        .where((team) => team != myTeamNumber)
        .toList(growable: false);
    final opponents = theirAlliance
        .where((team) => team != myTeamNumber)
        .toList(growable: false);

    return MatchInfoEntry(
      match: match,
      preMatch: rowsFor(
        teammates,
        summaryByTeam: summaryByTeam,
        entriesByTeam: entriesByTeam,
        teleopField: teleopField,
        driveTrainField: driveTrainField,
        teamNames: teamNames,
        pitEntryByTeam: pitEntryByTeam,
      ),
      opponents: rowsFor(
        opponents,
        summaryByTeam: summaryByTeam,
        entriesByTeam: entriesByTeam,
        teleopField: teleopField,
        driveTrainField: driveTrainField,
        teamNames: teamNames,
        pitEntryByTeam: pitEntryByTeam,
      ),
    );
  }

  static List<MatchInfoRow> rowsFor(
    List<int> teamNumbers, {
    required Map<int, TeamSummaryRow> summaryByTeam,
    required Map<int, List<ScoutEntry>> entriesByTeam,
    required ScoutConfigField? teleopField,
    ScoutConfigField? driveTrainField,
    Map<int, String> teamNames = const <int, String>{},
    Map<int, PitScoutEntry> pitEntryByTeam = const <int, PitScoutEntry>{},
  }) {
    return <MatchInfoRow>[
      for (final team in teamNumbers)
        _rowFor(
          team,
          summary: summaryByTeam[team],
          entries: entriesByTeam[team] ?? const <ScoutEntry>[],
          teleopField: teleopField,
          driveTrainField: driveTrainField,
          teamName: teamNames[team],
          pitEntry: pitEntryByTeam[team],
        ),
    ];
  }

  static MatchInfoRow _rowFor(
    int team, {
    required TeamSummaryRow? summary,
    required List<ScoutEntry> entries,
    required ScoutConfigField? teleopField,
    required ScoutConfigField? driveTrainField,
    required String? teamName,
    required PitScoutEntry? pitEntry,
  }) {
    final teleopValues = _numericValues(entries, teleopField);
    return MatchInfoRow(
      teamNumber: team,
      teamName: teamName,
      robotType: RobotType.composeFrom(
        pitEntry,
        driveTrainField: driveTrainField,
      ),
      maxAuto: summary?.maxAuto,
      iqmAuto: summary?.iqmAuto,
      teleopAverage: teleopValues.isEmpty
          ? null
          : teleopValues.reduce((a, b) => a + b) / teleopValues.length,
      iqmFuel: summary?.iqmTeleop,
      maxTeleop: summary?.maxTeleop,

      everClimbedAutoL1: (summary?.autoClimbRate ?? 0) > 0,
    );
  }

  static ScoutConfigField? _fieldFor(ScoutConfig? config, String code) {
    if (config == null) return null;
    for (final field in config.allFields) {
      if (field.code == code) return field;
    }
    return null;
  }

  static List<double> _numericValues(
    List<ScoutEntry> entries,
    ScoutConfigField? field,
  ) {
    if (field == null) return const <double>[];
    final values = <double>[];
    for (final entry in entries) {
      if (!entry.fieldValues.containsKey(field.code)) continue;
      final raw = entry.fieldValues[field.code];
      final value = raw is num
          ? raw.toDouble()
          : num.tryParse(raw?.toString() ?? '')?.toDouble();
      if (value != null) values.add(value);
    }
    return values;
  }
}
