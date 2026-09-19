library;

import 'package:tba_client/tba_client.dart';

const String oprStatName = 'OPR';
const String dprStatName = 'DPR';
const String ccwmStatName = 'CCWM';

const List<String> defaultStatColumns = <String>[oprStatName, 'foulPoints'];

class EventStatTable {
  const EventStatTable({
    required this.eventKey,
    required this.statNames,
    required this.valuesByStat,
  });

  const EventStatTable.empty()
    : eventKey = '',
      statNames = const <String>[],
      valuesByStat = const <String, Map<int, num>>{};

  factory EventStatTable.from({
    required String eventKey,
    TbaEventOprs? oprs,
    TbaEventCoprs? coprs,
  }) {
    final valuesByStat = <String, Map<int, num>>{};
    final statNames = <String>[];

    void add(String statName, Map<String, num> byTeamKey) {
      final byTeam = <int, num>{};
      byTeamKey.forEach((teamKey, value) {
        final team = teamNumberFromKey(teamKey);
        if (team != null) byTeam[team] = value;
      });

      if (byTeam.isEmpty) return;
      statNames.add(statName);

      valuesByStat[statName] = Map<int, num>.unmodifiable(byTeam);
    }

    if (oprs != null) {
      add(oprStatName, oprs.oprs);
      add(dprStatName, oprs.dprs);
      add(ccwmStatName, oprs.ccwms);
    }
    if (coprs != null) {
      for (final statName in coprs.statNames) {
        if (valuesByStat.containsKey(statName)) continue;
        add(statName, coprs[statName] ?? const <String, num>{});
      }
    }

    return EventStatTable(
      eventKey: eventKey,
      statNames: List<String>.unmodifiable(statNames),
      valuesByStat: Map<String, Map<int, num>>.unmodifiable(valuesByStat),
    );
  }

  final String eventKey;

  final List<String> statNames;

  final Map<String, Map<int, num>> valuesByStat;

  bool get isEmpty => statNames.isEmpty;

  List<int> get teams {
    final teams = <int>{};
    for (final byTeam in valuesByStat.values) {
      teams.addAll(byTeam.keys);
    }
    final sorted = teams.toList()..sort();
    return List<int>.unmodifiable(sorted);
  }

  num? valueFor(int team, String statName) => valuesByStat[statName]?[team];

  List<String> visibleColumns(Set<String> selected) =>
      List<String>.unmodifiable(statNames.where(selected.contains));
}

int? teamNumberFromKey(String teamKey) {
  if (!teamKey.startsWith('frc')) return null;
  return int.tryParse(teamKey.substring(3));
}
