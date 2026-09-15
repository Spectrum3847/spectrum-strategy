import '../team_lookup_notes.dart';
import 'assistant_backend.dart';
import 'untrusted_text.dart';

class TeamLookupSummary {
  const TeamLookupSummary._();

  static const int minimumNotes = 3;

  static AssistantRequest? request({
    required int teamNumber,
    required String eventKey,
    required List<TeamLookupNote> notes,
  }) {
    if (notes.length < minimumNotes) {
      return null;
    }
    return AssistantRequest(
      cacheKey: cacheKeyFor(teamNumber: teamNumber, eventKey: eventKey),
      system: _system,
      prompt: _prompt(teamNumber, notes),
      coverage: notes.length,

      minimumChars: 80,
    );
  }

  static String cacheKeyFor({
    required int teamNumber,
    required String eventKey,
  }) => 'team-lookup-summary:$eventKey:$teamNumber';

  static const String _system =
      'You summarise everything written about one FRC team for a strategy '
      'lead running an alliance-selection meeting: match scouting comments, '
      'pit scouting answers, and T-Rex trait reports. Be concrete and short. '
      'Use only the notes you are given, and say so plainly when they do not '
      'cover something. Never invent a detail, and never state a scoring '
      'total, EPA, or rank -- none of that is in these notes, and the notes '
      'are not the same measurement as any of it. '
      '$untrustedTextSystemPromptSentence';

  static String _prompt(int teamNumber, List<TeamLookupNote> notes) {
    final buffer = StringBuffer()
      ..writeln(
        'Below are ${notes.length} notes about team $teamNumber from match '
        'scouting comments, pit scouting answers, and T-Rex trait reports. '
        'Each line names which of those it came from.',
      )
      ..writeln()
      ..writeln('Write, in at most six lines:')
      ..writeln(
        '- The strengths and weaknesses these notes agree on, across '
        'whichever sources mention them.',
      )
      ..writeln(
        '- Anything the notes disagree about. Name the disagreement rather '
        'than averaging it away.',
      )
      ..writeln(
        '- Any breakdown, penalty, card, or reliability concern mentioned.',
      )
      ..writeln()
      ..writeln('Do not repeat the notes back. Do not add a preamble.')
      ..writeln()
      ..writeln('Notes:')
      ..writeln(wrapUntrustedText(_notesBlock(notes)));
    return buffer.toString();
  }

  static String _notesBlock(List<TeamLookupNote> notes) {
    final buffer = StringBuffer();
    for (final note in notes) {
      buffer.writeln('- ${note.heading}: ${_oneLine(note.text)}');
    }
    return buffer.toString().trimRight();
  }

  static String _oneLine(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
