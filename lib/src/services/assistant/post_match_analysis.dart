import 'package:tba_client/tba_client.dart';

import '../../models/post_match_report.dart';
import 'assistant_backend.dart';
import 'untrusted_text.dart';

class PostMatchAnalysis {
  const PostMatchAnalysis._();

  static AssistantRequest? request({
    required String eventKey,
    required String matchId,
    required PostMatchReport report,
    TbaScheduleMatch? tbaMatch,
    int? myTeamNumber,
  }) {
    if (report.isEmpty) {
      return null;
    }
    return AssistantRequest(
      cacheKey: cacheKeyFor(eventKey: eventKey, matchId: matchId),
      system: _system,
      prompt: _prompt(
        report: report,
        tbaMatch: tbaMatch,
        myTeamNumber: myTeamNumber,
      ),

      minimumChars: 80,
    );
  }

  static String cacheKeyFor({
    required String eventKey,
    required String matchId,
  }) => 'post-match-analysis:${eventKey}_$matchId';

  static const String _system =
      'You summarise one FRC match for a strategy lead, from the lead\'s own '
      'written account and the official match result. Be concrete and short. '
      'Use only what is given; never invent a detail, a score, or a cause '
      'that is not in the text below. $untrustedTextSystemPromptSentence';

  static String _prompt({
    required PostMatchReport report,
    TbaScheduleMatch? tbaMatch,
    int? myTeamNumber,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        'Here is a strategy lead\'s account of one match, by phase, and the '
        'official result if it has posted.',
      )
      ..writeln()
      ..writeln(wrapUntrustedText(_accountBlock(report)));

    final result = _resultLine(tbaMatch, myTeamNumber);
    if (result != null) {
      buffer
        ..writeln()
        ..writeln('Official result:')
        ..writeln(result);
    }

    buffer
      ..writeln()
      ..writeln(
        'Write, in at most four lines: what happened, whether the '
        "lead's account lines up with the result, and anything worth "
        'carrying into the next match with this robot. Do not repeat the '
        'account back word for word. Do not add a preamble.',
      );
    return buffer.toString();
  }

  static String _accountBlock(PostMatchReport report) {
    final buffer = StringBuffer();
    _writeSection(buffer, 'Auto', report.auto);
    _writeSection(buffer, 'Teleop', report.teleop);
    _writeSection(buffer, 'Endgame', report.endgame);
    _writeSection(buffer, 'Notes', report.notes);
    return buffer.toString().trimRight();
  }

  static void _writeSection(StringBuffer buffer, String label, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    buffer
      ..writeln('$label:')
      ..writeln(trimmed)
      ..writeln();
  }

  static String? _resultLine(TbaScheduleMatch? match, int? myTeamNumber) {
    if (match == null || !match.isPlayed) {
      return null;
    }
    final ourAlliance = myTeamNumber == null
        ? null
        : match.redTeams.contains(myTeamNumber)
        ? 'red'
        : match.blueTeams.contains(myTeamNumber)
        ? 'blue'
        : null;
    if (ourAlliance == null) {
      return 'Red ${match.redScore} - blue ${match.blueScore}.';
    }
    final ourScore = ourAlliance == 'red' ? match.redScore : match.blueScore;
    final theirScore = ourAlliance == 'red' ? match.blueScore : match.redScore;
    final outcome = match.isTie
        ? 'Tied'
        : match.winningAlliance == ourAlliance
        ? 'Won'
        : 'Lost';
    return '$outcome $ourScore - $theirScore.';
  }
}
