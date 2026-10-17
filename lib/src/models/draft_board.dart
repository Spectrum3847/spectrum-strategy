class DraftAction {
  const DraftAction.pick(this.team) : declined = false;
  const DraftAction.decline(this.team) : declined = true;

  final int team;
  final bool declined;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'team': team,
    'declined': declined,
  };

  static DraftAction? tryFromJson(Object? raw) {
    if (raw is! Map || raw['team'] is! num) return null;
    final team = (raw['team'] as num).toInt();
    return raw['declined'] == true
        ? DraftAction.decline(team)
        : DraftAction.pick(team);
  }
}

class DraftAlliance {
  const DraftAlliance({required this.captain, this.picks = const <int>[]});

  final int captain;
  final List<int> picks;

  List<int> get teams => <int>[captain, ...picks];
}

class DraftBoard {
  const DraftBoard._({
    required this.alliances,
    required this.turn,
    required this.taken,
    required this.declined,
    required this.picking,
  });

  static const int allianceCount = 8;
  static const int rounds = 3;

  final List<DraftAlliance> alliances;

  final int turn;

  final Set<int> taken;
  final Set<int> declined;

  final int? picking;

  bool get isComplete => picking == null;

  int get round => turn ~/ allianceCount;

  bool canInvite(int team) {
    final at = picking;
    if (at == null || declined.contains(team)) return false;
    if (!taken.contains(team)) return true;
    for (var i = at + 1; i < alliances.length; i++) {
      final alliance = alliances[i];
      if (alliance.captain == team && alliance.picks.isEmpty) return true;
    }
    return false;
  }

  static List<int> get _order => <int>[
    for (var round = 0; round < rounds; round++)
      if (round.isEven)
        for (var i = 0; i < allianceCount; i++) i
      else
        for (var i = allianceCount - 1; i >= 0; i--) i,
  ];

  factory DraftBoard.replay(List<DraftAction> actions, List<int> ranking) {
    final taken = <int>{};
    final declined = <int>{};
    final alliances = <DraftAlliance>[];
    final picks = <int, List<int>>{};

    int? nextCaptain() {
      for (final team in ranking) {
        if (!taken.contains(team)) return team;
      }
      return null;
    }

    void seat() {
      final captain = nextCaptain();
      if (captain == null) return;
      taken.add(captain);
      picks[captain] = <int>[];
      alliances.add(DraftAlliance(captain: captain));
    }

    for (var i = 0; i < allianceCount; i++) {
      seat();
    }

    final order = _order;
    var turn = 0;
    int? onTheClock() {
      while (turn < order.length && order[turn] >= alliances.length) {
        turn++;
      }
      return turn < order.length ? order[turn] : null;
    }

    DraftBoard snapshot() {
      final picking = onTheClock();
      return DraftBoard._(
        alliances: <DraftAlliance>[
          for (final a in alliances)
            DraftAlliance(
              captain: a.captain,
              picks: List<int>.unmodifiable(picks[a.captain]!),
            ),
        ],
        turn: turn,
        taken: Set<int>.unmodifiable(taken),
        declined: Set<int>.unmodifiable(declined),
        picking: picking,
      );
    }

    for (final action in actions) {
      final at = onTheClock();
      if (at == null) break;
      final board = snapshot();
      if (!board.canInvite(action.team)) continue;
      if (action.declined) {
        declined.add(action.team);
        continue;
      }
      final picker = alliances[at].captain;
      final captainSlot = alliances.indexWhere((a) => a.captain == action.team);
      if (captainSlot >= 0) {
        alliances.removeAt(captainSlot);
        picks.remove(action.team);
        seat();
      }
      picks[picker]!.add(action.team);
      taken.add(action.team);
      turn++;
    }
    return snapshot();
  }
}
