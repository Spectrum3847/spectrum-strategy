import '../models/scout_config.dart';
import '../models/scout_entry.dart';

class UsualStart {
  const UsualStart({
    required this.team,
    required this.position,
    required this.count,
    required this.total,
  });

  final int team;
  final String position;
  final int count;
  final int total;
}

class StartConflict {
  const StartConflict({required this.position, required this.starts});

  final String position;
  final List<UsualStart> starts;

  String get message {
    final teams = <String>[for (final s in starts) '${s.team}'];
    final names = teams.length == 2
        ? '${teams[0]} and ${teams[1]}'
        : '${teams.sublist(0, teams.length - 1).join(', ')} and ${teams.last}';
    final counts = starts.map((s) => '${s.count}/${s.total}').join(', ');
    return '$names ${teams.length == 2 ? 'both' : 'all'} usually start '
        '$position ($counts)';
  }
}

class StartPositionConflicts {
  const StartPositionConflicts._();

  static const startingCode = 'starting';
  static const _noShow = 'no show';
  static const _minEntries = 2;

  static Map<int, UsualStart> usualStarts(
    Iterable<ScoutEntry> entries,
    Iterable<int> teams, {
    ScoutConfig? config,
  }) {
    ScoutConfigField? field;
    for (final f in config?.allFields ?? const <ScoutConfigField>[]) {
      if (f.code == startingCode) field = f;
    }
    final wanted = teams.toSet();
    final byTeam = <int, Map<String, int>>{};
    for (final entry in entries) {
      if (!wanted.contains(entry.teamNumber)) continue;
      final raw = entry.fieldValues[startingCode];
      if (raw == null) continue;
      final label = (field?.labelForStored(raw) ?? raw.toString()).trim();
      if (label.isEmpty || label.toLowerCase() == _noShow) continue;
      final counts = byTeam.putIfAbsent(
        entry.teamNumber,
        () => <String, int>{},
      );
      counts[label] = (counts[label] ?? 0) + 1;
    }
    final out = <int, UsualStart>{};
    for (final MapEntry(key: team, value: counts) in byTeam.entries) {
      final total = counts.values.fold(0, (a, b) => a + b);
      if (total < _minEntries) continue;
      final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
      if (top.value * 2 <= total) continue;
      out[team] = UsualStart(
        team: team,
        position: top.key,
        count: top.value,
        total: total,
      );
    }
    return out;
  }

  static List<StartConflict> conflicts(
    Iterable<int> alliance,
    Map<int, UsualStart> usual,
  ) {
    final byPosition = <String, List<UsualStart>>{};
    for (final team in alliance) {
      final start = usual[team];
      if (start == null) continue;
      byPosition.putIfAbsent(start.position, () => <UsualStart>[]).add(start);
    }
    return <StartConflict>[
      for (final MapEntry(key: position, value: starts) in byPosition.entries)
        if (starts.length > 1)
          StartConflict(position: position, starts: starts),
    ];
  }
}
