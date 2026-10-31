import '../../models/event_stat_table.dart' show teamNumberFromKey;
import '../../scouting/models/pit_scout_entry.dart';
import '../../scouting/models/scout_config.dart';
import '../../scouting/models/team_analysis.dart';
import '../../scouting/services/entry_match.dart';
import '../../scouting/services/robot_type.dart';
import '../../scouting/services/scouting_analysis.dart';
import '../../scouting/services/team_incidents.dart';
import '../../scouting/state/pit_scout_config_controller.dart';
import '../../scouting/state/pit_scouting_controller.dart';
import '../../scouting/state/scout_config_controller.dart';
import '../../scouting/state/scouting_controller.dart';
import '../../state/event_controller.dart';
import '../../state/event_stats_controller.dart';
import '../match_info_view.dart' show mostRecentPitEntryByTeam;

class PickFacts {
  PickFacts({
    required this.eventController,
    required ScoutingController scoutingController,
    required ScoutConfigController configController,
    this.statsController,
    PitScoutingController? pitScoutingController,
    PitScoutConfigController? pitScoutConfigController,
  }) : _analyses = ScoutingAnalysis.aggregateByTeam(
         scoutingController.entries,
         config: configController.config,
       ),
       _incidents = TeamIncidents.byTeam(
         entriesForEvent(scoutingController.entries, eventController.eventKey),
       ),
       _pitByTeam = mostRecentPitEntryByTeam(pitScoutingController?.entries),
       _driveTrainField = _driveTrainIn(pitScoutConfigController);

  final EventController eventController;
  final EventStatsController? statsController;
  final Map<int, TeamAnalysis> _analyses;
  final Map<int, TeamIncidents> _incidents;
  final Map<int, PitScoutEntry> _pitByTeam;
  final ScoutConfigField? _driveTrainField;

  static ScoutConfigField? _driveTrainIn(PitScoutConfigController? controller) {
    for (final field in controller?.config.allFields ?? const []) {
      if (field.code == RobotType.driveTrainCode) return field;
    }
    return null;
  }

  String stat(int team) {
    final analysis = _analyses[team];
    final rank = statsController?.rankFor(team);
    final opr = statsController?.oprFor(team);
    final epa = eventController.displayTeams
        .where((t) => t.team == team)
        .map((t) => t.epa.totalPoints)
        .firstOrNull;
    return <String>[
      if (analysis != null && analysis.hasData)
        'IQM ${analysis.iqmTotalScore.toStringAsFixed(1)} '
            '(n=${analysis.entryCount})'
      else
        'Not scouted',
      ?(rank == null ? null : 'TBA #$rank'),
      ?(opr == null ? null : 'OPR ${opr.toStringAsFixed(1)}'),
      ?(epa == null || epa <= 0 ? null : 'EPA ${epa.toStringAsFixed(1)}'),
    ].join(' · ');
  }

  String? flags(int team) {
    final text = RobotType.composeFrom(
      _pitByTeam[team],
      driveTrainField: _driveTrainField,
    );
    return text.isEmpty ? null : text;
  }

  String? incidents(int team) {
    final found = _incidents[team];
    return found == null || found.isEmpty ? null : found.describe();
  }

  List<({int team, String reason})> dnpSuggestions({
    Set<int> except = const <int>{},
  }) {
    final teams =
        [
          for (final MapEntry(key: team, value: found) in _incidents.entries)
            if (found.suggestsDoNotPick &&
                !except.contains(team) &&
                team != eventController.myTeamNumber)
              (team: team, weight: found.weight, reason: found.describe()),
        ]..sort((a, b) {
          final byWeight = b.weight.compareTo(a.weight);
          return byWeight != 0 ? byWeight : a.team.compareTo(b.team);
        });
    return [for (final t in teams) (team: t.team, reason: t.reason)];
  }

  Set<int> get knownTeams => <int>{
    ...eventController.displayTeams.map((t) => t.team),
    ...eventController.teamNicknames.keys,
    ..._analyses.keys,
  };

  List<int> get officialRanking {
    final rows = <MapEntry<int, int>>[
      for (final row in statsController?.rankings?.rankings ?? const [])
        if (teamNumberFromKey(row.teamKey) case final team?)
          MapEntry(row.rank, team),
    ]..sort((a, b) => a.key.compareTo(b.key));
    return <int>[for (final row in rows) row.value];
  }

  List<int> get ranking {
    final ordered = <int>[];
    final seen = <int>{};
    void add(int team) {
      if (seen.add(team)) ordered.add(team);
    }

    officialRanking.forEach(add);

    final byEpa = [...eventController.displayTeams]
      ..sort(
        (a, b) => (b.epa.totalPoints ?? 0).compareTo(a.epa.totalPoints ?? 0),
      );
    byEpa.map((t) => t.team).forEach(add);

    final byScore = _analyses.values.toList()
      ..sort((a, b) => b.iqmTotalScore.compareTo(a.iqmTotalScore));
    byScore.map((a) => a.teamNumber).forEach(add);
    return ordered;
  }
}
