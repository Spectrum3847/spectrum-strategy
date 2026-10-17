import 'package:statbotics_client/statbotics_client.dart';

import '../models/pit_scout_entry.dart';
import '../models/prescout_entry.dart';
import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import '../models/team_analysis.dart' show TeamNote;
import 'robot_type.dart';
import 'scouting_analysis.dart';
import 'team_summary_stats.dart';

class SourcedStat {
  const SourcedStat({this.event, this.prescout});

  final double? event;
  final double? prescout;

  bool get isEmpty => event == null && prescout == null;
}

class MatchInfoRow {
  const MatchInfoRow({
    required this.teamNumber,
    this.teamName,
    this.robotType = '',
    this.maxAuto = const SourcedStat(),
    this.iqmAuto = const SourcedStat(),
    this.teleopAverage = const SourcedStat(),
    this.iqmFuel = const SourcedStat(),
    this.maxTeleop = const SourcedStat(),
    this.autoClimb = false,
    this.endgameClimb = '',
    this.driveCoach = '',
    this.notes = '',
  });

  final int teamNumber;
  final String? teamName;
  final String robotType;

  final SourcedStat maxAuto;
  final SourcedStat iqmAuto;

  final SourcedStat teleopAverage;
  final SourcedStat iqmFuel;
  final SourcedStat maxTeleop;

  final bool autoClimb;

  final String endgameClimb;

  final String driveCoach;

  final String notes;
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

  static const _prescoutAutoFuelCode = 'autoFuelScored';
  static const _prescoutTeleopFuelCode = 'teleopFuelScored';
  static const _prescoutAutoClimbCode = 'autoClimbL1';
  static const _prescoutLowClimbCode = 'lowClimbL1';
  static const _prescoutMiddleClimbCode = 'middleClimbL2';
  static const _prescoutHighClimbCode = 'highClimbL3';
  static const _prescoutSuccessValue = 'successful';

  static const _driveCoachCode = 'driveCoachName';
  static const _pitCommentsCode = 'comments';

  static List<MatchInfoEntry> build({
    required List<StatboticsMatch> matches,
    required int? myTeamNumber,
    required Iterable<ScoutEntry> scoutEntries,
    ScoutConfig? config,
    ScoutConfig? pitConfig,
    Map<int, String> teamNames = const <int, String>{},
    Map<int, PitScoutEntry> pitEntryByTeam = const <int, PitScoutEntry>{},
    Iterable<PrescoutEntry> prescoutEntries = const <PrescoutEntry>[],
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
    final prescoutByTeam = <int, List<PrescoutEntry>>{};
    for (final entry in prescoutEntries) {
      (prescoutByTeam[entry.teamNumber] ??= <PrescoutEntry>[]).add(entry);
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
          prescoutByTeam: prescoutByTeam,
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
    required Map<int, List<PrescoutEntry>> prescoutByTeam,
    required ScoutConfigField? teleopField,
    required ScoutConfigField? driveTrainField,
    required Map<int, String> teamNames,
    required Map<int, PitScoutEntry> pitEntryByTeam,
  }) {
    final onRed = match.redTeams.contains(myTeamNumber);
    final ourAlliance = onRed ? match.redTeams : match.blueTeams;
    final theirAlliance = onRed ? match.blueTeams : match.redTeams;

    final teammates = ourAlliance.toList(growable: false);

    final opponents = theirAlliance
        .where((team) => team != myTeamNumber)
        .toList(growable: false);

    return MatchInfoEntry(
      match: match,
      preMatch: rowsFor(
        teammates,
        summaryByTeam: summaryByTeam,
        entriesByTeam: entriesByTeam,
        prescoutByTeam: prescoutByTeam,
        teleopField: teleopField,
        driveTrainField: driveTrainField,
        teamNames: teamNames,
        pitEntryByTeam: pitEntryByTeam,
      ),
      opponents: rowsFor(
        opponents,
        summaryByTeam: summaryByTeam,
        entriesByTeam: entriesByTeam,
        prescoutByTeam: prescoutByTeam,
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
    Map<int, List<PrescoutEntry>> prescoutByTeam =
        const <int, List<PrescoutEntry>>{},
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
          prescoutEntries: prescoutByTeam[team] ?? const <PrescoutEntry>[],
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
    required List<PrescoutEntry> prescoutEntries,
    required ScoutConfigField? teleopField,
    required ScoutConfigField? driveTrainField,
    required String? teamName,
    required PitScoutEntry? pitEntry,
  }) {
    final teleopValues = _numericValues(entries, teleopField);
    final prescoutAuto = _prescoutNumbers(
      prescoutEntries,
      _prescoutAutoFuelCode,
    );
    final prescoutTeleop = _prescoutNumbers(
      prescoutEntries,
      _prescoutTeleopFuelCode,
    );
    final pitComments = (pitEntry?.fieldValues[_pitCommentsCode] ?? '')
        .toString()
        .trim();

    return MatchInfoRow(
      teamNumber: team,
      teamName: teamName,
      robotType: RobotType.composeFrom(
        pitEntry,
        driveTrainField: driveTrainField,
      ),
      maxAuto: SourcedStat(
        event: summary?.maxAuto,
        prescout: _maxOrNull(prescoutAuto),
      ),
      iqmAuto: SourcedStat(
        event: summary?.iqmAuto,
        prescout: _meanOrNull(prescoutAuto),
      ),
      teleopAverage: SourcedStat(
        event: teleopValues.isEmpty
            ? null
            : teleopValues.reduce((a, b) => a + b) / teleopValues.length,
        prescout: _meanOrNull(prescoutTeleop),
      ),
      iqmFuel: SourcedStat(
        event: summary?.iqmTeleop,
        prescout: _meanOrNull(prescoutTeleop),
      ),
      maxTeleop: SourcedStat(
        event: summary?.maxTeleop,
        prescout: _maxOrNull(prescoutTeleop),
      ),

      autoClimb:
          (summary?.autoClimbRate ?? 0) > 0 ||
          _prescoutSuccessRate(prescoutEntries, _prescoutAutoClimbCode) > 0,
      endgameClimb: _endgameClimbLabel(summary, prescoutEntries),
      driveCoach: (pitEntry?.fieldValues[_driveCoachCode] ?? '')
          .toString()
          .trim(),
      notes: _notesSummary(
        ScoutingAnalysis.notesForTeam(team, entries),
        pitComments,
      ),
    );
  }

  static String _endgameClimbLabel(
    TeamSummaryRow? summary,
    List<PrescoutEntry> prescoutEntries,
  ) {
    final high =
        (summary?.highClimbRate ?? 0) > 0 ||
        _prescoutSuccessRate(prescoutEntries, _prescoutHighClimbCode) > 0;
    if (high) return 'L3';
    final middle =
        (summary?.middleClimbRate ?? 0) > 0 ||
        _prescoutSuccessRate(prescoutEntries, _prescoutMiddleClimbCode) > 0;
    if (middle) return 'L2';
    final low =
        (summary?.lowClimbRate ?? 0) > 0 ||
        _prescoutSuccessRate(prescoutEntries, _prescoutLowClimbCode) > 0;
    if (low) return 'L1';
    return '';
  }

  static String _notesSummary(List<TeamNote> notes, String pitComments) {
    final parts = <String>[
      for (final note in notes) note.text.trim(),
      if (pitComments.isNotEmpty) pitComments,
    ].where((part) => part.isNotEmpty).toList(growable: false);
    if (parts.isEmpty) return '';
    const maxLength = 140;
    final joined = parts.join(' · ');
    return joined.length > maxLength
        ? '${joined.substring(0, maxLength)}…'
        : joined;
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

  static List<double> _prescoutNumbers(
    List<PrescoutEntry> entries,
    String code,
  ) {
    final values = <double>[];
    for (final entry in entries) {
      if (!entry.fieldValues.containsKey(code)) continue;
      final raw = entry.fieldValues[code];
      final value = raw is num
          ? raw.toDouble()
          : num.tryParse(raw?.toString() ?? '')?.toDouble();
      if (value != null) values.add(value);
    }
    return values;
  }

  static double? _maxOrNull(List<double> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);

  static double? _meanOrNull(List<double> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

  static double _prescoutSuccessRate(List<PrescoutEntry> entries, String code) {
    var withValue = 0;
    var successes = 0;
    for (final entry in entries) {
      if (!entry.fieldValues.containsKey(code)) continue;
      withValue++;
      if (entry.fieldValues[code]?.toString().toLowerCase() ==
          _prescoutSuccessValue) {
        successes++;
      }
    }
    return withValue == 0 ? 0 : successes / withValue;
  }
}
