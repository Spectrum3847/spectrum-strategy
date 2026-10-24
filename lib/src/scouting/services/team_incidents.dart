import '../models/scout_entry.dart';
import 'entry_match.dart';
import 'scouting_meeting_stats.dart';

class TeamIncidents {
  const TeamIncidents({
    this.red = const <String>[],
    this.yellow = const <String>[],
    this.unknownCard = const <String>[],
    this.died = const <String>[],
  });

  static const _cardCode = 'ryCard';
  static const _diedCode = 'dieCard';

  final List<String> red;
  final List<String> yellow;

  final List<String> unknownCard;

  final List<String> died;

  bool get isEmpty =>
      red.isEmpty && yellow.isEmpty && unknownCard.isEmpty && died.isEmpty;

  int get weight =>
      red.length * 3 + yellow.length + unknownCard.length + died.length;

  bool get suggestsDoNotPick => weight >= 2;

  String describe() {
    final parts = <String>[
      if (red.isNotEmpty) 'red card ${red.join(', ')}',
      if (yellow.isNotEmpty) 'yellow card ${yellow.join(', ')}',
      if (unknownCard.isNotEmpty) 'card ${unknownCard.join(', ')}',
      if (died.isNotEmpty) 'died ${died.join(', ')}',
    ];
    final text = parts.join(' · ');
    return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
  }

  static Map<int, TeamIncidents> byTeam(Iterable<ScoutEntry> entries) {
    final cards = <int, Map<String, CardColor>>{};
    final deaths = <int, Set<String>>{};
    for (final entry in entries) {
      final match = _matchOf(entry);
      final card = ScoutingMeetingStats.cardColorOf(
        entry.fieldValues[_cardCode],
      );
      if (card != null) {
        final byMatch = cards[entry.teamNumber] ??= <String, CardColor>{};
        final seen = byMatch[match];
        if (seen == null || card.severity > seen.severity) {
          byMatch[match] = card;
        }
      }
      final died = entry.fieldValues[_diedCode];
      if (died == true || died == 'true') {
        (deaths[entry.teamNumber] ??= <String>{}).add(match);
      }
    }

    List<String> labels(Iterable<String> matches) {
      final sorted = matches.toList()..sort(_byScheduleOrder);
      return [for (final m in sorted) _shortLabel(m)];
    }

    final result = <int, TeamIncidents>{};
    for (final team in {...cards.keys, ...deaths.keys}) {
      final byMatch = cards[team] ?? const <String, CardColor>{};
      Iterable<String> withColor(CardColor color) =>
          byMatch.entries.where((e) => e.value == color).map((e) => e.key);
      result[team] = TeamIncidents(
        red: labels(withColor(CardColor.red)),
        yellow: labels(withColor(CardColor.yellow)),
        unknownCard: labels(withColor(CardColor.unknown)),
        died: labels(deaths[team] ?? const <String>{}),
      );
    }
    return result;
  }

  static String _matchOf(ScoutEntry entry) {
    final group = matchGroupKeyOfEntry(entry);
    final parts = _parts(group);
    if (parts != null) return '${parts.level}${parts.set}m${parts.match}';
    return group.isEmpty ? 'entry ${entry.id}' : group;
  }

  static const _levelOrder = <String, int>{'qm': 0, 'qf': 1, 'sf': 2, 'f': 3};

  static ({String level, int set, int match})? _parts(String matchKey) {
    final full = RegExp(r'(?:^|_)(qm|qf|sf|f)(\d+)(?:m(\d+))?$')
        .firstMatch(matchKey);
    final level = full?.group(1);
    final number = full == null ? null : int.parse(full.group(2)!);
    final match = int.tryParse(full?.group(3) ?? '');
    if (level != null && number != null) {
      if (match != null) return (level: level, set: number, match: match);
      return level == 'f'
          ? (level: level, set: 1, match: number)
          : (level: level, set: number, match: 1);
    }
    final label = parseMatchLabel(matchKey);
    if (label == null) return null;
    return label.level == 'f'
        ? (level: 'f', set: 1, match: label.number)
        : (level: label.level ?? 'qm', set: label.number, match: 1);
  }

  static int _byScheduleOrder(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    if (pa == null || pb == null) {
      if (pa == null && pb == null) return a.compareTo(b);
      return pa == null ? 1 : -1;
    }
    final byLevel = (_levelOrder[pa.level] ?? 9).compareTo(
      _levelOrder[pb.level] ?? 9,
    );
    if (byLevel != 0) return byLevel;
    final bySet = pa.set.compareTo(pb.set);
    return bySet != 0 ? bySet : pa.match.compareTo(pb.match);
  }

  static String _shortLabel(String matchKey) {
    final parts = _parts(matchKey);
    if (parts == null) return '(no match number)';
    if (parts.level == 'qm') return 'Q${parts.set}';
    if (parts.level == 'f') return 'F${parts.match}';
    final set = '${parts.level.toUpperCase()}${parts.set}';
    return parts.match == 1 ? set : '$set-${parts.match}';
  }
}
