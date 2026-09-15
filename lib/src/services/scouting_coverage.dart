import 'package:statbotics_client/statbotics_client.dart';

import '../scouting/models/scout_entry.dart';
import '../scouting/services/entry_match.dart';

class CoverageSlot {
  const CoverageSlot({
    required this.team,
    required this.alliance,
    required this.scouted,
  });

  final int team;

  final String alliance;

  final bool scouted;
}

class MatchCoverage {
  const MatchCoverage({
    required this.matchNumber,
    required this.compLevel,
    required this.slots,
  });

  final int matchNumber;
  final String compLevel;
  final List<CoverageSlot> slots;

  int get scoutedCount => slots.where((s) => s.scouted).length;

  bool get isComplete => slots.isNotEmpty && scoutedCount == slots.length;

  List<int> get missingTeams => <int>[
    for (final slot in slots)
      if (!slot.scouted) slot.team,
  ];
}

class ScoutingCoverage {
  const ScoutingCoverage({required this.matches});

  const ScoutingCoverage.empty() : matches = const <MatchCoverage>[];

  final List<MatchCoverage> matches;

  bool get isEmpty => matches.isEmpty;

  int get totalSlots => matches.fold<int>(0, (sum, m) => sum + m.slots.length);

  int get scoutedSlots =>
      matches.fold<int>(0, (sum, m) => sum + m.scoutedCount);

  double get fraction => totalSlots == 0 ? 0 : scoutedSlots / totalSlots;

  List<MatchCoverage> get incompleteMatches {
    final open = matches.where((m) => !m.isComplete).toList();
    open.sort((a, b) {
      final byGap = (b.slots.length - b.scoutedCount).compareTo(
        a.slots.length - a.scoutedCount,
      );
      return byGap != 0 ? byGap : a.matchNumber.compareTo(b.matchNumber);
    });
    return List<MatchCoverage>.unmodifiable(open);
  }

  static ScoutingCoverage build({
    required List<StatboticsMatch> schedule,
    required Iterable<ScoutEntry> entries,
  }) {
    final quals = schedule.where((m) => m.compLevel == 'qm').toList()
      ..sort((a, b) => a.matchNumber.compareTo(b.matchNumber));
    if (quals.isEmpty) return const ScoutingCoverage.empty();

    final covered = <String>{};
    for (final entry in entries) {
      final match = _matchNumberOf(entry);
      if (match != null) covered.add('$match:${entry.teamNumber}');
    }

    final matches = <MatchCoverage>[
      for (final match in quals)
        MatchCoverage(
          matchNumber: match.matchNumber,
          compLevel: match.compLevel,
          slots: <CoverageSlot>[
            for (final team in match.redTeams)
              CoverageSlot(
                team: team,
                alliance: 'Red',
                scouted: covered.contains('${match.matchNumber}:$team'),
              ),
            for (final team in match.blueTeams)
              CoverageSlot(
                team: team,
                alliance: 'Blue',
                scouted: covered.contains('${match.matchNumber}:$team'),
              ),
          ],
        ),
    ];

    return ScoutingCoverage(matches: List<MatchCoverage>.unmodifiable(matches));
  }

  static int? _matchNumberOf(ScoutEntry entry) => matchNumberOfEntry(entry);
}
