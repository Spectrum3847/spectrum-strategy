import '../models/trex_trait.dart';
import '../models/trex_trait_report.dart';
import '../scouting/models/pit_scout_entry.dart';
import '../scouting/models/scout_config.dart';
import '../scouting/models/scout_entry.dart';
import '../scouting/models/team_analysis.dart';
import '../scouting/services/scouting_analysis.dart';

class TeamLookupNote {
  const TeamLookupNote({required this.heading, required this.text});

  final String heading;
  final String text;
}

class TeamLookupNotes {
  const TeamLookupNotes._();

  static List<TeamLookupNote> notesForTeam({
    required int teamNumber,
    required List<ScoutEntry> scoutEntries,
    PitScoutEntry? pitEntry,
    ScoutConfig? pitConfig,
    List<TrexTraitReport> trexReports = const <TrexTraitReport>[],
  }) {
    final notes = <TeamLookupNote>[
      for (final note in ScoutingAnalysis.notesForTeam(
        teamNumber,
        scoutEntries,
      ))
        TeamLookupNote(heading: _scoutingHeading(note), text: note.text),
    ];

    final pit = pitEntry;
    if (pit != null) {
      for (final answer in _pitAnswers(pit, pitConfig)) {
        notes.add(
          TeamLookupNote(
            heading: 'Pit scouting: ${answer.$1}',
            text: answer.$2,
          ),
        );
      }
    }

    for (final report in trexReports) {
      if (report.teamNumber != teamNumber || report.report.trim().isEmpty) {
        continue;
      }
      notes.add(
        TeamLookupNote(
          heading: 'T-Rex: ${_traitLabel(report.trait)}',
          text: report.report.trim(),
        ),
      );
    }

    return notes;
  }

  static String _scoutingHeading(TeamNote note) {
    final parts = <String>[
      if (note.matchId.isNotEmpty) 'Match ${note.matchId}',
      if (note.phase != null) note.phase!.label,
      if (note.author.isNotEmpty) 'by ${note.author}',
    ];
    return parts.isEmpty ? 'Scouting note' : parts.join(', ');
  }

  static List<(String, String)> _pitAnswers(
    PitScoutEntry entry,
    ScoutConfig? config,
  ) {
    if (config == null) return const <(String, String)>[];
    final result = <(String, String)>[];
    for (final field in config.allFields) {
      if (!entry.fieldValues.containsKey(field.code)) continue;
      final label = field.labelForStored(entry.fieldValues[field.code]);
      if (label.isEmpty) continue;
      result.add((field.title, label));
    }
    return result;
  }

  static String _traitLabel(String key) => TrexTrait.byKey(key)?.label ?? key;
}
