import '../../theme/strategy_palette.dart';
import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import '../models/team_analysis.dart';

class ScoutingAnalysis {
  const ScoutingAnalysis._();

  static List<int> teamNumbers(Iterable<ScoutEntry> entries) {
    final teams = <int>{for (final entry in entries) entry.teamNumber};
    final sorted = teams.toList()..sort();
    return sorted;
  }

  static Map<int, TeamAnalysis> aggregateByTeam(
    Iterable<ScoutEntry> entries, {
    ScoutConfig? config,
  }) {
    final byTeam = <int, List<ScoutEntry>>{};
    for (final entry in entries) {
      (byTeam[entry.teamNumber] ??= <ScoutEntry>[]).add(entry);
    }
    return <int, TeamAnalysis>{
      for (final team in byTeam.entries)
        team.key: TeamAnalysis.fromEntries(
          team.key,
          team.value,
          config: config,
        ),
    };
  }

  static TeamAnalysis analyzeTeam(
    int teamNumber,
    Iterable<ScoutEntry> entries, {
    ScoutConfig? config,
  }) {
    return TeamAnalysis.fromEntries(teamNumber, entries, config: config);
  }

  static List<TeamNote> notesForTeam(
    int teamNumber,
    Iterable<ScoutEntry> entries,
  ) {
    final notes = <TeamNote>[];
    for (final entry in entries.where((e) => e.teamNumber == teamNumber)) {
      final entryNote = entry.notes.trim();
      if (entryNote.isNotEmpty) {
        notes.add(
          TeamNote(
            matchId: entry.matchId,
            text: entryNote,
            author: entry.authorDisplayName,
            updatedAt: entry.updatedAt,
          ),
        );
      }
      for (final phase in StrategyPhase.values) {
        final phaseNote = entry.phaseData(phase).notes.trim();
        if (phaseNote.isNotEmpty) {
          notes.add(
            TeamNote(
              matchId: entry.matchId,
              phase: phase,
              text: phaseNote,
              author: entry.authorDisplayName,
              updatedAt: entry.updatedAt,
            ),
          );
        }
      }
    }
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  static List<TeamReportGroup> reportsForTeam(
    int teamNumber,
    Iterable<ScoutEntry> entries,
    ScoutConfig config,
  ) {
    final forTeam = entries
        .where((e) => e.teamNumber == teamNumber)
        .toList(growable: false);
    if (forTeam.isEmpty) return const <TeamReportGroup>[];

    final groups = <TeamReportGroup>[];
    for (final section in config.sections) {
      final textFields = section.fields
          .where((f) => f.type == ScoutFieldType.text)
          .toList(growable: false);
      if (textFields.isEmpty) continue;

      final reports = <TeamReport>[];
      for (final entry in forTeam) {
        for (final field in textFields) {
          final value = entry.fieldValues[field.code];
          if (value is! String) continue;
          final text = value.trim();
          if (text.isEmpty) continue;
          reports.add(
            TeamReport(
              entryId: entry.id,
              matchId: entry.matchId,

              fieldTitle: field.title.trim().isEmpty
                  ? field.code
                  : field.title.trim(),
              text: text,
              author: entry.authorDisplayName,
              updatedAt: entry.updatedAt,
              strokesByPhase: entry.strokesByPhase,
            ),
          );
        }
      }
      if (reports.isEmpty) continue;
      reports.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      groups.add(
        TeamReportGroup(
          groupName: section.name,
          reports: List<TeamReport>.unmodifiable(reports),
        ),
      );
    }
    return List<TeamReportGroup>.unmodifiable(groups);
  }

  static List<TeamAnalysis> rankByScore(
    Iterable<ScoutEntry> entries, {
    ScoutConfig? config,
  }) {
    final analyses = aggregateByTeam(entries, config: config).values.toList();
    analyses.sort((a, b) {
      final byScore = b.iqmTotalScore.compareTo(a.iqmTotalScore);
      if (byScore != 0) return byScore;
      return a.teamNumber.compareTo(b.teamNumber);
    });
    return analyses;
  }
}
