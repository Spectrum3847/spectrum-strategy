import 'package:statbotics_client/statbotics_client.dart';

import '../../models/cycle_log.dart';
import '../../scouting/models/scout_config.dart';
import '../../scouting/models/scout_entry.dart';
import '../../scouting/models/team_analysis.dart';
import '../../scouting/services/entry_match.dart';
import '../../theme/strategy_palette.dart';
import 'assistant_backend.dart';

class MatchScorePoint {
  const MatchScorePoint({
    required this.matchLabel,
    required this.totalScore,
    required this.autonScore,
    required this.teleopScore,
    required this.endgameScore,
    required this.penalties,
    required this.alliance,
  });

  final String matchLabel;
  final double totalScore;
  final double autonScore;
  final double teleopScore;
  final double endgameScore;
  final int penalties;

  final String alliance;
}

class CycleTimeSummary {
  const CycleTimeSummary({
    required this.matchesCovered,
    required this.cycleCount,
    required this.meanMs,
    required this.medianMs,
  });

  final int matchesCovered;
  final int cycleCount;
  final double meanMs;
  final double medianMs;

  String get meanLabel => _seconds(meanMs);
  String get medianLabel => _seconds(medianMs);

  static String _seconds(double ms) => '${(ms / 1000).toStringAsFixed(1)}s';
}

class ScoringTrendAnalysis {
  const ScoringTrendAnalysis._();

  static const int minimumMatches = 3;

  static const int minimumCycleLogMatches = 3;

  static List<MatchScorePoint> series(
    int teamNumber,
    Iterable<ScoutEntry> entries, {
    ScoutConfig? config,
  }) {
    final teamEntries = entries
        .where((entry) => entry.teamNumber == teamNumber)
        .toList();
    teamEntries.sort((a, b) {
      final byMatch = _playOrder(a).compareTo(_playOrder(b));
      if (byMatch != 0) return byMatch;

      return a.updatedAt.compareTo(b.updatedAt);
    });
    return [
      for (final entry in teamEntries) _pointFor(teamNumber, entry, config),
    ];
  }

  static CycleTimeSummary? cycleSummary(List<CycleLog> logs) {
    final withEvents = logs.where((log) => log.events.isNotEmpty);
    final matchesCovered = withEvents.map((log) => log.matchKey).toSet();
    if (matchesCovered.length < minimumCycleLogMatches) {
      return null;
    }
    final cycles = <int>[for (final log in withEvents) ...log.cycleTimesMs]
      ..sort();
    if (cycles.isEmpty) {
      return null;
    }
    final mean = cycles.reduce((a, b) => a + b) / cycles.length;
    final median = cycles.length.isOdd
        ? cycles[cycles.length ~/ 2].toDouble()
        : (cycles[cycles.length ~/ 2 - 1] + cycles[cycles.length ~/ 2]) / 2;
    return CycleTimeSummary(
      matchesCovered: matchesCovered.length,
      cycleCount: cycles.length,
      meanMs: mean,
      medianMs: median,
    );
  }

  static AssistantRequest? request({
    required int teamNumber,
    required String eventKey,
    required List<MatchScorePoint> series,
    List<StatboticsTeamYear> seasons = const <StatboticsTeamYear>[],
    List<CycleLog> cycleLogs = const <CycleLog>[],
    int totalMatches = 0,
  }) {
    if (series.length < minimumMatches) {
      return null;
    }
    final cycles = cycleSummary(cycleLogs);
    return AssistantRequest(
      cacheKey: cacheKeyFor(
        teamNumber: teamNumber,
        eventKey: eventKey,
        seasons: seasons,
        cycles: cycles,
      ),
      system: _system,
      prompt: _prompt(
        teamNumber,
        series,
        seasons,
        cycles,
        totalMatches == 0 ? series.length : totalMatches,
      ),
      coverage: series.length,

      minimumChars: 80,
    );
  }

  static String cacheKeyFor({
    required int teamNumber,
    required String eventKey,
    List<StatboticsTeamYear> seasons = const <StatboticsTeamYear>[],
    CycleTimeSummary? cycles,
  }) {
    final years = seasons.map((s) => s.year).toList()..sort();
    final suffix = years.isEmpty ? '' : ':${years.join('-')}';
    final cycleSuffix = cycles == null
        ? ''
        : ':cycles-${cycles.matchesCovered}-${cycles.meanMs.round()}';
    return 'scoring-trend:$eventKey:$teamNumber$suffix$cycleSuffix';
  }

  static const String _system =
      'You explain the shape of an FRC team\'s scoring trend for a strategy '
      'lead. The numbers below are already computed; your job is the reasons, '
      'not the arithmetic. Point only at patterns visible in the tables given '
      'to you: a phase that moved differently from the rest, penalties '
      'clustering in certain matches, an alliance colour change, a run of '
      'matches trending the same direction, a season whose EPA rank sits well '
      'above or below the current one. Never invent a cause the tables do not '
      'show, and say plainly when the numbers do not explain themselves. '
      'The two tables are in different units: per-match totals are this '
      'event\'s scouting points and season rows are EPA, so never compare a '
      'number from one against a number from the other, and never treat a '
      'season\'s EPA points as comparable to another season\'s. Compare '
      'seasons only on the unitless scale, the normalized scale, or the world '
      'rank. A cycle-time table, if present, covers only the handful of '
      'matches someone filmed, never the whole event: never describe it as '
      'the team\'s general or typical cycle time, only as what those specific '
      'filmed matches showed.';

  static String _prompt(
    int teamNumber,
    List<MatchScorePoint> series,
    List<StatboticsTeamYear> seasons,
    CycleTimeSummary? cycles,
    int totalMatches,
  ) {
    final buffer = StringBuffer()
      ..writeln(
        'Below is team $teamNumber\'s total score per match at one event, in '
        'the order the matches were played, already computed from scouting '
        'data. Each line also breaks the total into auton, teleop and '
        'endgame, the penalties called that match, and which alliance the '
        'team played on.',
      )
      ..writeln()
      ..writeln(
        'Write, in at most five lines, why the trend looks the way it does. '
        'Name the matches you are pointing at. If the numbers do not show a '
        'clear reason, say so instead of guessing.',
      );

    if (seasons.isEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'No season-by-season history is available for this team, so do not '
          'speculate about previous seasons.',
        );
    } else {
      buffer
        ..writeln()
        ..writeln(
          'A season history table follows the matches. Use it only to say '
          'whether this event reads as normal, better or worse for this team '
          'than its recent seasons, and say which season you mean. Judge that '
          'on the unitless scale, the normalized scale or the world rank, '
          'never on EPA points, which mean different things in different '
          'games.',
        );
    }

    buffer
      ..writeln()
      ..writeln(
        'Matches (total / auton / teleop / endgame / penalties / alliance), '
        'in this event\'s scouting points:',
      );

    for (final point in series) {
      buffer.writeln(
        '- ${point.matchLabel}: ${_n(point.totalScore)} / '
        '${_n(point.autonScore)} / ${_n(point.teleopScore)} / '
        '${_n(point.endgameScore)} / ${point.penalties} pen / '
        '${point.alliance.isEmpty ? 'unknown alliance' : point.alliance}',
      );
    }

    if (seasons.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Season history (EPA, newest first):');
      for (final season in seasons) {
        buffer.writeln('- ${_seasonLine(season)}');
      }
    }

    if (cycles != null) {
      buffer
        ..writeln()
        ..writeln(
          'Cycle time table, from film review. This covers only '
          '${cycles.matchesCovered} of $totalMatches matches at this event '
          '-- whichever ones someone filmed with the cycle logger, not the '
          'whole event. Treat it as a sample from those matches only, never '
          'as this team\'s general cycle time.',
        )
        ..writeln('- filmed matches: ${cycles.matchesCovered} of $totalMatches')
        ..writeln('- cycles logged: ${cycles.cycleCount}')
        ..writeln('- mean cycle: ${cycles.meanLabel}')
        ..writeln('- median cycle: ${cycles.medianLabel}');
    }

    return buffer.toString();
  }

  static String _seasonLine(StatboticsTeamYear season) {
    final parts = <String>[];
    final unitless = season.epa.unitless;
    if (unitless != null) {
      parts.add('unitless EPA ${_n(unitless)}');
    }
    final norm = season.epa.norm;
    if (norm != null) {
      parts.add('normalized EPA ${_n(norm)} (1500 is average)');
    }
    final rank = season.epaRank;
    if (rank != null) {
      final count = season.epaRankTeamCount;
      parts.add(
        count == null ? 'world rank $rank' : 'world rank $rank of $count',
      );
    }
    parts.add('record ${season.wins}-${season.losses}-${season.ties}');
    final total = season.epa.totalPoints;
    if (total != null) {
      parts.add(
        'EPA ${_n(total)} points in that season\'s game, not comparable '
        'across seasons',
      );
    }
    final phases = <String>[
      if (season.epa.autoPoints != null) 'auton ${_n(season.epa.autoPoints!)}',
      if (season.epa.teleopPoints != null)
        'teleop ${_n(season.epa.teleopPoints!)}',
      if (season.epa.endgamePoints != null)
        'endgame ${_n(season.epa.endgamePoints!)}',
    ];
    if (phases.isNotEmpty) {
      parts.add('phase split ${phases.join(' / ')}');
    }
    return '${season.year}: ${parts.join(', ')}';
  }

  static String _n(double value) => value.toStringAsFixed(1);

  static int _playOrder(ScoutEntry entry) {
    final label = parseMatchLabel(matchGroupKeyOfEntry(entry));
    if (label == null) return 1 << 30;
    const levelRank = <String, int>{'qm': 0, 'qf': 1, 'sf': 2, 'f': 3};
    final rank = levelRank[label.level ?? 'qm'] ?? 4;
    return rank * 1000 + label.number;
  }

  static MatchScorePoint _pointFor(
    int teamNumber,
    ScoutEntry entry,
    ScoutConfig? config,
  ) {
    final analysis = TeamAnalysis.fromEntries(teamNumber, [
      entry,
    ], config: config);
    return MatchScorePoint(
      matchLabel: matchLabelOfEntry(entry),
      totalScore: analysis.iqmTotalScore,
      autonScore: analysis.phaseStats(StrategyPhase.auton).iqmScore,
      teleopScore: analysis.phaseStats(StrategyPhase.teleop).iqmScore,
      endgameScore: analysis.phaseStats(StrategyPhase.endgame).iqmScore,
      penalties: analysis.avgTotalPenalties.round(),
      alliance: entry.effectiveAlliance,
    );
  }
}
