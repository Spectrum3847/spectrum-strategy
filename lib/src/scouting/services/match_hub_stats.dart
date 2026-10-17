import 'package:statbotics_client/statbotics_client.dart';

import '../../models/match_preview.dart';
import '../models/pit_scout_entry.dart';
import '../models/prescout_entry.dart';
import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import '../models/team_analysis.dart';
import 'entry_match.dart';
import 'match_info_stats.dart';
import 'match_prediction_stats.dart';
import 'scouting_analysis.dart';

class MatchScoutedSide {
  const MatchScoutedSide({required this.teamScores, this.officialScore});

  final Map<int, double?> teamScores;
  final int? officialScore;

  int get scoutedRobots => teamScores.values.whereType<double>().length;

  double get scoutedTotal =>
      teamScores.values.whereType<double>().fold(0.0, (a, b) => a + b);
}

class MatchHubData {
  const MatchHubData({
    required this.match,
    required this.preview,
    required this.rows,
    required this.scoutedPrediction,
    required this.ourAlliance,
  });

  factory MatchHubData.build(
    StatboticsMatch match, {
    required Map<int, String> nicknames,
    required Map<int, StatboticsTeamEvent> teamEvents,
    required Iterable<ScoutEntry> scoutEntries,
    required int? myTeamNumber,
    ScoutConfig? config,
    ScoutConfig? pitConfig,
    Map<int, PitScoutEntry> pitEntryByTeam = const <int, PitScoutEntry>{},
    Iterable<PrescoutEntry> prescoutEntries = const <PrescoutEntry>[],
  }) {
    return MatchHubData(
      match: match,
      preview: MatchPreview.fromMatch(
        match,
        nicknames: nicknames,
        teamEvents: teamEvents,
        analyses: ScoutingAnalysis.aggregateByTeam(
          scoutEntries,
          config: config,
        ),
      ),
      rows: _rowsByTeam(
        match,
        scoutEntries: scoutEntries,
        config: config,
        pitConfig: pitConfig,
        teamNames: nicknames,
        pitEntryByTeam: pitEntryByTeam,
        prescoutEntries: prescoutEntries,
      ),
      scoutedPrediction: MatchPredictionStats.build(
        redTeams: match.redTeams,
        blueTeams: match.blueTeams,
        scoutEntries: scoutEntries,
        config: config,
      ),
      ourAlliance: match.redTeams.contains(myTeamNumber)
          ? 'Red'
          : match.blueTeams.contains(myTeamNumber)
          ? 'Blue'
          : null,
    );
  }

  final StatboticsMatch match;
  final MatchPreview preview;

  final Map<int, MatchInfoRow> rows;

  final MatchPredictionResult scoutedPrediction;

  final String? ourAlliance;

  List<MatchPreviewTeam> get ourTeams => switch (ourAlliance) {
    'Red' => preview.red,
    'Blue' => preview.blue,
    _ => const <MatchPreviewTeam>[],
  };

  List<MatchPreviewTeam> get opponentTeams => switch (ourAlliance) {
    'Red' => preview.blue,
    'Blue' => preview.red,
    _ => const <MatchPreviewTeam>[],
  };

  List<String> factsFor(MatchPreviewTeam team) {
    final row = rows[team.teamNumber];
    final facts = <String>[];
    final epa = team.epaTotal;
    if (epa != null) facts.add('EPA ${_one(epa)} points');
    if (team.isScouted) {
      final n = team.matchesScouted;
      facts.add(
        'Scouted in $n match${n == 1 ? '' : 'es'}, '
        'typical score ${_one(team.scoutedScore!)}',
      );
    } else {
      facts.add('Not scouted yet');
    }
    if (row != null) {
      final auto = row.iqmAuto.event;
      final teleop = row.iqmFuel.event;
      if (auto != null || teleop != null) {
        facts.add(
          'Typical auto ${auto == null ? '--' : _one(auto)}, '
          'teleop ${teleop == null ? '--' : _one(teleop)}',
        );
      }
      if (row.robotType.isNotEmpty) facts.add('Robot type: ${row.robotType}');
      if (row.endgameClimb.isNotEmpty) {
        facts.add('Best endgame climb seen: ${row.endgameClimb}');
      }
      if (row.autoClimb) facts.add('Has climbed in auto');
      if (row.notes.isNotEmpty) facts.add('Scout notes: ${row.notes}');
    }
    return facts;
  }

  static String _one(double value) => value.toStringAsFixed(1);

  static Map<int, MatchInfoRow> _rowsByTeam(
    StatboticsMatch match, {
    required Iterable<ScoutEntry> scoutEntries,
    required ScoutConfig? config,
    required ScoutConfig? pitConfig,
    required Map<int, String> teamNames,
    required Map<int, PitScoutEntry> pitEntryByTeam,
    required Iterable<PrescoutEntry> prescoutEntries,
  }) {
    final anchor = match.redTeams.firstOrNull ?? match.blueTeams.firstOrNull;
    if (anchor == null) return const <int, MatchInfoRow>{};
    final entries = MatchInfoStats.build(
      matches: <StatboticsMatch>[match],
      myTeamNumber: anchor,
      scoutEntries: scoutEntries,
      config: config,
      pitConfig: pitConfig,
      teamNames: teamNames,
      pitEntryByTeam: pitEntryByTeam,
      prescoutEntries: prescoutEntries,
    );
    if (entries.isEmpty) return const <int, MatchInfoRow>{};
    final entry = entries.first;
    return <int, MatchInfoRow>{
      for (final row in <MatchInfoRow>[...entry.preMatch, ...entry.opponents])
        row.teamNumber: row,
    };
  }
}

List<ScoutEntry> entriesForMatch(
  StatboticsMatch match,
  Iterable<ScoutEntry> entries,
) {
  return <ScoutEntry>[
    for (final entry in entries)
      if (_belongsTo(match, entry)) entry,
  ];
}

bool _belongsTo(StatboticsMatch match, ScoutEntry entry) {
  final group = matchGroupKeyOfEntry(entry);
  return group == match.key.toLowerCase() ||
      group == '${match.compLevel}${match.matchNumber}' ||
      (match.isQualification && group == 'm${match.matchNumber}');
}

({MatchScoutedSide red, MatchScoutedSide blue}) scoutedVersusOfficial(
  StatboticsMatch match, {
  required Iterable<ScoutEntry> scoutEntries,
  required int? redOfficial,
  required int? blueOfficial,
  ScoutConfig? config,
}) {
  final inMatch = entriesForMatch(match, scoutEntries);
  MatchScoutedSide side(List<int> teams, int? official) {
    return MatchScoutedSide(
      teamScores: <int, double?>{
        for (final team in teams) team: _scoutedScore(team, inMatch, config),
      },
      officialScore: official,
    );
  }

  return (
    red: side(match.redTeams, redOfficial),
    blue: side(match.blueTeams, blueOfficial),
  );
}

double? _scoutedScore(
  int team,
  Iterable<ScoutEntry> inMatch,
  ScoutConfig? config,
) {
  final analysis = TeamAnalysis.fromEntries(team, inMatch, config: config);
  return analysis.hasData ? analysis.iqmTotalScore : null;
}
