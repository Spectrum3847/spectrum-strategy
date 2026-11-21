import 'package:flutter/foundation.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

enum TeamMatchOutcome { win, loss, tie }

@immutable
class TeamMatch {
  const TeamMatch({required this.match, required this.onRed, this.result});

  final StatboticsMatch match;
  final bool onRed;

  final TbaScheduleMatch? result;

  int? get _redScore => _scoreOrNull(result?.redScore);
  int? get _blueScore => _scoreOrNull(result?.blueScore);

  bool get isPlayed => _redScore != null && _blueScore != null;

  int? get ourScore => onRed ? _redScore : _blueScore;
  int? get theirScore => onRed ? _blueScore : _redScore;

  TeamMatchOutcome? get outcome {
    if (!isPlayed) return null;
    final winner = result?.winningAlliance;
    if (winner == null || winner.isEmpty) return TeamMatchOutcome.tie;
    return (winner == 'red') == onRed
        ? TeamMatchOutcome.win
        : TeamMatchOutcome.loss;
  }

  static int? _scoreOrNull(int? score) =>
      score == null || score < 0 ? null : score;
}

@immutable
class TeamMatchSchedule {
  const TeamMatchSchedule({
    required this.matches,
    required this.wins,
    required this.losses,
    required this.ties,
  });

  factory TeamMatchSchedule.build({
    required int team,
    required List<StatboticsMatch> sortedMatches,
    required TbaScheduleMatch? Function(String matchKey) resultFor,
  }) {
    final matches = <TeamMatch>[];
    var wins = 0, losses = 0, ties = 0;
    for (final match in sortedMatches) {
      final onRed = match.redTeams.contains(team);
      if (!onRed && !match.blueTeams.contains(team)) continue;
      final entry = TeamMatch(
        match: match,
        onRed: onRed,
        result: resultFor(match.key),
      );
      matches.add(entry);
      if (!match.isQualification) continue;
      switch (entry.outcome) {
        case TeamMatchOutcome.win:
          wins++;
        case TeamMatchOutcome.loss:
          losses++;
        case TeamMatchOutcome.tie:
          ties++;
        case null:
          break;
      }
    }
    return TeamMatchSchedule(
      matches: List<TeamMatch>.unmodifiable(matches),
      wins: wins,
      losses: losses,
      ties: ties,
    );
  }

  final List<TeamMatch> matches;
  final int wins;
  final int losses;
  final int ties;

  String get record => '$wins-$losses-$ties';
}
