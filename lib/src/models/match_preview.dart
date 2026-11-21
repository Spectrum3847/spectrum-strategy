import 'package:statbotics_client/statbotics_client.dart';

import '../scouting/models/team_analysis.dart';

class MatchPreviewTeam {
  const MatchPreviewTeam({
    required this.teamNumber,
    required this.nickname,
    required this.isRed,
    this.epaTotal,
    this.epaAuto,
    this.epaTeleop,
    this.analysis,
  });

  final int teamNumber;

  final String nickname;

  final bool isRed;

  final double? epaTotal;
  final double? epaAuto;
  final double? epaTeleop;

  final TeamAnalysis? analysis;

  bool get isScouted => (analysis?.entryCount ?? 0) > 0;

  double? get scoutedScore => isScouted ? analysis!.iqmTotalScore : null;

  int get matchesScouted => analysis?.matchCount ?? 0;
}

class MatchPreview {
  const MatchPreview({
    required this.matchKey,
    required this.matchLabel,
    required this.red,
    required this.blue,
  });

  factory MatchPreview.fromMatch(
    StatboticsMatch match, {
    required Map<int, String> nicknames,
    required Map<int, StatboticsTeamEvent> teamEvents,
    required Map<int, TeamAnalysis> analyses,
  }) {
    MatchPreviewTeam build(int team, {required bool isRed}) {
      final epa = teamEvents[team]?.epa;
      return MatchPreviewTeam(
        teamNumber: team,
        nickname: nicknames[team] ?? '',
        isRed: isRed,
        epaTotal: epa?.totalPoints,
        epaAuto: epa?.autoPoints,
        epaTeleop: epa?.teleopPoints,
        analysis: analyses[team],
      );
    }

    return MatchPreview(
      matchKey: match.key,
      matchLabel: _label(match),
      red: <MatchPreviewTeam>[
        for (final team in match.redTeams) build(team, isRed: true),
      ],
      blue: <MatchPreviewTeam>[
        for (final team in match.blueTeams) build(team, isRed: false),
      ],
    );
  }

  final String matchKey;

  final String matchLabel;

  final List<MatchPreviewTeam> red;
  final List<MatchPreviewTeam> blue;

  List<MatchPreviewTeam> get allTeams => <MatchPreviewTeam>[...red, ...blue];

  double? get redEpa => _sumEpa(red);
  double? get blueEpa => _sumEpa(blue);

  static double? _sumEpa(List<MatchPreviewTeam> teams) {
    double? total;
    for (final team in teams) {
      final value = team.epaTotal;
      if (value == null) continue;
      total = (total ?? 0) + value;
    }
    return total;
  }

  List<MatchPreviewTeam> get unscouted => allTeams
      .where((MatchPreviewTeam t) => !t.isScouted)
      .toList(growable: false);

  static String _label(StatboticsMatch match) {
    final level = switch (match.compLevel.toLowerCase()) {
      'qm' => 'Qual',
      'qf' => 'QF',
      'sf' => 'SF',
      'f' => 'F',
      final other => other.toUpperCase(),
    };
    return '$level ${match.matchNumber}';
  }
}
