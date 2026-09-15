import '../models/strategy_session.dart';
import 'match_directory.dart';

bool boardInScope({
  required String selectedEventKey,
  required String boardEventKey,
  required bool thisEventOnly,
}) {
  if (!thisEventOnly || selectedEventKey.isEmpty) return true;
  if (boardEventKey.isEmpty) return true;
  return boardEventKey == selectedEventKey;
}

class ScopedBoardLists {
  const ScopedBoardLists({
    required this.matches,
    required this.teamBoards,
    required this.hidden,
  });

  final List<MatchSummary> matches;
  final List<StrategySession> teamBoards;

  final int hidden;

  bool get isEmpty => matches.isEmpty && teamBoards.isEmpty;
}

ScopedBoardLists scopeBoardLists({
  required List<MatchSummary> allMatches,
  required List<StrategySession> remoteBoards,
  required String selectedEventKey,
  required bool thisEventOnly,
}) {
  bool inScope(String key) => boardInScope(
    selectedEventKey: selectedEventKey,
    boardEventKey: key,
    thisEventOnly: thisEventOnly,
  );

  final localIds = <String>{for (final m in allMatches) m.id};
  final matches = <MatchSummary>[
    for (final m in allMatches)
      if (inScope(m.eventKey)) m,
  ];
  final remoteOnly = <StrategySession>[
    for (final b in remoteBoards)
      if (!localIds.contains(b.id)) b,
  ];
  final teamBoards = <StrategySession>[
    for (final b in remoteOnly)
      if (inScope(b.eventKey)) b,
  ];
  return ScopedBoardLists(
    matches: matches,
    teamBoards: teamBoards,
    hidden:
        (allMatches.length - matches.length) +
        (remoteOnly.length - teamBoards.length),
  );
}
