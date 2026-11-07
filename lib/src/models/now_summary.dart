import 'dart:math' show max;

import 'package:statbotics_client/statbotics_client.dart';

import '../scouting/models/scout_entry.dart';
import '../scouting/models/scout_shift_schedule.dart';

const int kNowCoverageWindow = 10;

class NowMatch {
  const NowMatch({
    required this.match,
    required this.ourAlliance,
    required this.partners,
    required this.opponents,
    required this.matchesAway,
  });

  final StatboticsMatch match;

  final String ourAlliance;
  final List<int> partners;
  final List<int> opponents;

  final int? matchesAway;

  String get opposingAlliance => ourAlliance == 'Red' ? 'Blue' : 'Red';
}

class UnscoutedMatch {
  const UnscoutedMatch({required this.match, required this.teams});

  final StatboticsMatch match;
  final List<int> teams;
}

class NowSummary {
  const NowSummary({
    required this.ourQualCount,
    required this.playedThrough,
    required this.next,
    required this.shift,
    required this.shiftMatchesAway,
    required this.unscouted,
  });

  factory NowSummary.build({
    required List<StatboticsMatch> matches,
    required int? myTeam,
    required List<ScoutEntry> entries,
    ScouterShiftRotation? rotation,
  }) {
    final quals = matches.where((m) => m.compLevel == 'qm').toList()
      ..sort((a, b) => a.matchNumber.compareTo(b.matchNumber));

    final scoutedByMatch = <String, Set<int>>{};
    for (final entry in entries) {
      final key = entry.tbaMatchKey?.toLowerCase();
      if (key == null) continue;
      scoutedByMatch.putIfAbsent(key, () => <int>{}).add(entry.teamNumber);
    }

    int? played;
    for (final match in quals) {
      if ((scoutedByMatch[match.key.toLowerCase()]?.length ?? 0) >= 2) {
        played = match.matchNumber;
      }
    }
    final floor = played ?? 0;

    final ours = <StatboticsMatch>[];
    if (myTeam != null) {
      ours.addAll(quals.where((m) => m.allTeams.contains(myTeam)));
    }
    NowMatch? next;
    for (final match in ours) {
      if (match.matchNumber <= floor) continue;
      final isRed = match.redTeams.contains(myTeam);
      final ourSide = isRed ? match.redTeams : match.blueTeams;
      final theirSide = isRed ? match.blueTeams : match.redTeams;
      final between = quals.where((q) {
        return q.matchNumber > floor && q.matchNumber < match.matchNumber;
      });
      next = NowMatch(
        match: match,
        ourAlliance: isRed ? 'Red' : 'Blue',
        partners: ourSide.where((t) => t != myTeam).toList(),
        opponents: theirSide,
        matchesAway: played == null ? null : between.length,
      );
      break;
    }

    final shift = rotation?.upcomingShift(floor + 1);
    int? shiftMatchesAway;
    if (shift != null && played != null) {
      shiftMatchesAway = max(0, shift.startMatch - floor - 1);
    }

    final unscouted = <UnscoutedMatch>[];
    if (played != null) {
      for (final match in quals) {
        final number = match.matchNumber;
        if (number > played || number <= played - kNowCoverageWindow) continue;
        final seen = scoutedByMatch[match.key.toLowerCase()] ?? const <int>{};
        final missing = match.allTeams.where((t) => !seen.contains(t)).toList();
        if (missing.isNotEmpty) {
          unscouted.add(UnscoutedMatch(match: match, teams: missing));
        }
      }
    }

    return NowSummary(
      ourQualCount: ours.length,
      playedThrough: played,
      next: next,
      shift: shift,
      shiftMatchesAway: shiftMatchesAway,
      unscouted: unscouted,
    );
  }

  final int ourQualCount;

  final int? playedThrough;

  final NowMatch? next;

  final ScoutShiftBlock? shift;

  final int? shiftMatchesAway;

  final List<UnscoutedMatch> unscouted;

  int get unscoutedRobots {
    return unscouted.fold(0, (sum, m) => sum + m.teams.length);
  }
}
