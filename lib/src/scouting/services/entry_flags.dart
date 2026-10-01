import '../models/scout_entry.dart';
import '../models/scout_schedule.dart';
import 'entry_match.dart';

enum EntryFlagKind { duplicateTeam, duplicateStation, matchNumberOffSchedule }

class EntryFlag {
  const EntryFlag({required this.kind, required this.reason});

  final EntryFlagKind kind;
  final String reason;

  @override
  String toString() => '${kind.name}: $reason';
}

class EntryFlags {
  const EntryFlags(this._byEntryId);

  const EntryFlags.empty() : _byEntryId = const <String, List<EntryFlag>>{};

  final Map<String, List<EntryFlag>> _byEntryId;

  bool get isEmpty => _byEntryId.isEmpty;

  bool get isNotEmpty => _byEntryId.isNotEmpty;

  int get flaggedEntryCount => _byEntryId.length;

  List<EntryFlag> forEntry(ScoutEntry entry) =>
      _byEntryId[entry.id] ?? const <EntryFlag>[];

  EntryFlag? worstFor(ScoutEntry entry) {
    final flags = forEntry(entry);
    if (flags.isEmpty) return null;
    return flags.reduce(
      (EntryFlag a, EntryFlag b) => a.kind.index <= b.kind.index ? a : b,
    );
  }

  static EntryFlags detect(
    Iterable<ScoutEntry> entries, {
    Iterable<int> scheduledMatchNumbers = const <int>[],
  }) {
    final scheduled = scheduledMatchNumbers.toSet();

    final byMatch = <String, List<ScoutEntry>>{};
    for (final entry in entries) {
      byMatch
          .putIfAbsent(matchGroupKeyOfEntry(entry), () => <ScoutEntry>[])
          .add(entry);
    }

    final found = <String, List<EntryFlag>>{};
    void flag(ScoutEntry entry, EntryFlagKind kind, String reason) {
      found
          .putIfAbsent(entry.id, () => <EntryFlag>[])
          .add(EntryFlag(kind: kind, reason: reason));
    }

    for (final group in byMatch.values) {
      final label = matchLabelOfEntry(group.first);
      final byTeam = <int, List<ScoutEntry>>{};
      final byStation = <String, List<ScoutEntry>>{};
      for (final entry in group) {
        if (entry.teamNumber > 0) {
          byTeam.putIfAbsent(entry.teamNumber, () => <ScoutEntry>[]).add(entry);
        }
        final station = stationOfEntry(entry);
        if (station != null) {
          byStation.putIfAbsent(station, () => <ScoutEntry>[]).add(entry);
        }
      }

      for (final team in byTeam.entries) {
        if (team.value.length < 2) continue;
        final reason =
            'Team ${team.key} is on ${team.value.length} rows in $label.';
        for (final entry in team.value) {
          flag(entry, EntryFlagKind.duplicateTeam, reason);
        }
      }
      for (final station in byStation.entries) {
        if (station.value.length < 2) continue;
        final reason =
            'Driver station ${station.key} is on '
            '${station.value.length} rows in $label.';
        for (final entry in station.value) {
          flag(entry, EntryFlagKind.duplicateStation, reason);
        }
      }
    }

    for (final entry in entries) {
      final offSchedule = _matchNumberProblem(entry, scheduled);
      if (offSchedule == null) continue;
      flag(entry, EntryFlagKind.matchNumberOffSchedule, offSchedule);
    }

    for (final flags in found.values) {
      flags.sort(
        (EntryFlag a, EntryFlag b) => a.kind.index.compareTo(b.kind.index),
      );
    }
    return EntryFlags(found);
  }
}

String? _matchNumberProblem(ScoutEntry entry, Set<int> scheduled) {
  final typed = _typedMatchNumber(entry);
  if (typed == null) return null;

  final key = entry.tbaMatchKey?.trim() ?? '';
  if (key.isNotEmpty) {
    final fromKey = parseMatchLabel(key)?.number;
    if (fromKey == null || fromKey == typed) return null;
    return 'Scouted as match $typed, but saved against '
        '${matchLabelOfEntry(entry).toLowerCase()}.';
  }

  if (scheduled.isEmpty || scheduled.contains(typed)) return null;
  return 'Match $typed is not in the loaded schedule.';
}

int? _typedMatchNumber(ScoutEntry entry) {
  final typed = entry.fieldValues['matchNumber'];
  if (typed is num) return typed.toInt();
  if (typed is String) return parseMatchLabel(typed)?.number;
  return null;
}

String? stationOfEntry(ScoutEntry entry) {
  String? found;
  for (final value in entry.fieldValues.values) {
    final station = _stationOfValue(value);
    if (station == null) continue;
    if (found != null && found != station) return null;
    found ??= station;
  }
  return found;
}

String? _stationOfValue(Object? value) {
  if (value is String) return ScoutSchedule.normalizeStation(value);
  if (value is Map) {
    final position = value['robotPosition'];
    if (position is String) return ScoutSchedule.normalizeStation(position);
  }
  return null;
}
