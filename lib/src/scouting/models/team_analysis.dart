import 'dart:math' show sqrt;

import '../../theme/strategy_palette.dart';
import 'scout_config.dart';
import 'scout_entry.dart';

double interquartileMean(Iterable<num> values) {
  final sorted = values.map((v) => v.toDouble()).toList()..sort();
  final n = sorted.length;
  if (n == 0) return 0;
  if (n < 4) return sorted.reduce((a, b) => a + b) / n;
  final quartile = n / 4.0;
  final cut = quartile.floor();
  final boundaryWeight = 1 - (quartile - cut);
  var sum = boundaryWeight * (sorted[cut] + sorted[n - 1 - cut]);
  for (var i = cut + 1; i < n - 1 - cut; i++) {
    sum += sorted[i];
  }
  return sum / (n / 2.0);
}

class PhaseStats {
  const PhaseStats({
    this.iqmScore = 0,
    this.avgPenalties = 0,
    Map<String, double>? avgCounters,
    Map<String, int>? totalCounters,
  }) : avgCounters = avgCounters ?? const <String, double>{},
       totalCounters = totalCounters ?? const <String, int>{};

  final double iqmScore;

  final double avgPenalties;

  final Map<String, double> avgCounters;

  final Map<String, int> totalCounters;
}

class TeamAnalysis {
  const TeamAnalysis({
    required this.teamNumber,
    this.entryCount = 0,
    this.matchCount = 0,
    this.lastSeen,
    Set<String>? alliances,
    Map<StrategyPhase, PhaseStats>? byPhase,
    this.iqmTotalScore = 0,
    this.avgTotalPenalties = 0,
    this.scoreStdDev = 0,
  }) : alliances = alliances ?? const <String>{},
       byPhase = byPhase ?? const <StrategyPhase, PhaseStats>{};

  final int teamNumber;

  final int entryCount;

  final int matchCount;

  final DateTime? lastSeen;

  final Set<String> alliances;

  final Map<StrategyPhase, PhaseStats> byPhase;

  final double iqmTotalScore;

  final double avgTotalPenalties;

  final double scoreStdDev;

  bool get hasData => entryCount > 0;

  PhaseStats phaseStats(StrategyPhase phase) =>
      byPhase[phase] ?? const PhaseStats();

  factory TeamAnalysis.fromEntries(
    int teamNumber,
    Iterable<ScoutEntry> entries, {
    ScoutConfig? config,
  }) {
    final teamEntries = entries
        .where((entry) => entry.teamNumber == teamNumber)
        .toList();
    if (teamEntries.isEmpty) {
      return TeamAnalysis(
        teamNumber: teamNumber,
        byPhase: <StrategyPhase, PhaseStats>{
          for (final phase in StrategyPhase.values) phase: const PhaseStats(),
        },
      );
    }

    final numericFieldsByPhase = <StrategyPhase, List<ScoutConfigField>>{
      for (final phase in StrategyPhase.values) phase: <ScoutConfigField>[],
    };
    if (config != null) {
      for (final section in config.sections) {
        final phase = _phaseOfSection(section.name);
        if (phase == null) continue;
        numericFieldsByPhase[phase]!.addAll(
          section.fields.where(_isNumericField),
        );
      }
    }

    final count = teamEntries.length;
    final matches = <String>{};
    final alliances = <String>{};
    DateTime? lastSeen;

    final phaseScores = <StrategyPhase, List<double>>{
      for (final phase in StrategyPhase.values) phase: <double>[],
    };
    final totalScores = <double>[];
    final penaltyTotals = <StrategyPhase, int>{
      for (final phase in StrategyPhase.values) phase: 0,
    };
    final counterTotals = <StrategyPhase, Map<String, double>>{
      for (final phase in StrategyPhase.values) phase: <String, double>{},
    };

    for (final entry in teamEntries) {
      if (entry.matchId.isNotEmpty) matches.add(entry.matchId);
      if (entry.effectiveAlliance.isNotEmpty) {
        alliances.add(entry.effectiveAlliance);
      }
      if (lastSeen == null || entry.updatedAt.isAfter(lastSeen)) {
        lastSeen = entry.updatedAt;
      }
      var entryTotal = 0.0;
      for (final phase in StrategyPhase.values) {
        final data = entry.phaseData(phase);
        var score = data.score.toDouble();
        penaltyTotals[phase] = penaltyTotals[phase]! + data.penalties;
        final counters = counterTotals[phase]!;
        for (final counter in data.counters.entries) {
          counters[counter.key] = (counters[counter.key] ?? 0) + counter.value;
        }
        for (final field in numericFieldsByPhase[phase]!) {
          final value = _numericValue(entry.fieldValues[field.code]);
          if (value == null) continue;
          score += value;
          final label = field.title.isNotEmpty ? field.title : field.code;
          counters[label] = (counters[label] ?? 0) + value;
        }
        phaseScores[phase]!.add(score);
        entryTotal += score;
      }
      totalScores.add(entryTotal);
    }

    final byPhase = <StrategyPhase, PhaseStats>{};
    var avgTotalPenalties = 0.0;
    for (final phase in StrategyPhase.values) {
      final totals = counterTotals[phase]!;
      final avgPenalties = penaltyTotals[phase]! / count;
      byPhase[phase] = PhaseStats(
        iqmScore: interquartileMean(phaseScores[phase]!),
        avgPenalties: avgPenalties,
        totalCounters: Map<String, int>.unmodifiable(<String, int>{
          for (final counter in totals.entries)
            counter.key: counter.value.round(),
        }),
        avgCounters: Map<String, double>.unmodifiable(<String, double>{
          for (final counter in totals.entries)
            counter.key: counter.value / count,
        }),
      );
      avgTotalPenalties += avgPenalties;
    }

    final iqmTotalScore = interquartileMean(totalScores);

    var scoreStdDev = 0.0;
    if (count >= 2) {
      final meanTotal = totalScores.reduce((a, b) => a + b) / count;
      final variance =
          totalScores
              .map((total) => (total - meanTotal) * (total - meanTotal))
              .reduce((a, b) => a + b) /
          count;
      scoreStdDev = sqrt(variance);
    }

    return TeamAnalysis(
      teamNumber: teamNumber,
      entryCount: count,
      matchCount: matches.length,
      lastSeen: lastSeen,
      alliances: Set<String>.unmodifiable(alliances),
      byPhase: Map<StrategyPhase, PhaseStats>.unmodifiable(byPhase),
      iqmTotalScore: iqmTotalScore,
      avgTotalPenalties: avgTotalPenalties,
      scoreStdDev: scoreStdDev,
    );
  }

  static StrategyPhase? _phaseOfSection(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('auto')) return StrategyPhase.auton;
    if (lower.contains('tele')) return StrategyPhase.teleop;
    if (lower.contains('end') || lower.contains('climb')) {
      return StrategyPhase.endgame;
    }
    return null;
  }

  static bool _isNumericField(ScoutConfigField field) {
    switch (field.type) {
      case ScoutFieldType.number:
      case ScoutFieldType.counter:
      case ScoutFieldType.multiCounter:
      case ScoutFieldType.range:
        return true;
      case ScoutFieldType.text:
      case ScoutFieldType.boolean:
      case ScoutFieldType.select:
      case ScoutFieldType.actionTracker:
      case ScoutFieldType.tbaMatchNumber:
      case ScoutFieldType.tbaTeamAndRobot:
      case ScoutFieldType.checkboxSelect:
        return false;
    }
  }

  static double? _numericValue(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return num.tryParse(raw)?.toDouble();
    return null;
  }
}

class TeamNote {
  const TeamNote({
    required this.matchId,
    required this.text,
    required this.author,
    required this.updatedAt,
    this.phase,
  });

  final String matchId;

  final StrategyPhase? phase;

  final String text;

  final String author;

  final DateTime updatedAt;
}

class TeamReport {
  const TeamReport({
    required this.entryId,
    required this.matchId,
    required this.fieldTitle,
    required this.text,
    required this.author,
    required this.updatedAt,
    this.strokesByPhase,
  });

  final String entryId;

  final String matchId;

  final String fieldTitle;

  final String text;

  final String author;

  final DateTime updatedAt;

  final Map<String, dynamic>? strokesByPhase;

  bool get hasDrawing => strokesByPhase != null && strokesByPhase!.isNotEmpty;
}

class TeamReportGroup {
  const TeamReportGroup({required this.groupName, required this.reports});

  final String groupName;

  final List<TeamReport> reports;

  bool get isEmpty => reports.isEmpty;
}
