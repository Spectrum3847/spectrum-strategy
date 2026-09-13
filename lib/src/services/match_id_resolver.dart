import 'package:statbotics_client/statbotics_client.dart';

class MatchIdResolver {
  MatchIdResolver(Iterable<StatboticsMatch> schedule)
    : _byKey = <String, StatboticsMatch>{
        for (final match in schedule)
          if (match.key.isNotEmpty) match.key.toLowerCase(): match,
      },
      _byLevelAndNumber = <String, List<StatboticsMatch>>{},
      _byNumber = <int, List<StatboticsMatch>>{} {
    for (final match in _byKey.values) {
      _byNumber
          .putIfAbsent(match.matchNumber, () => <StatboticsMatch>[])
          .add(match);
      final level = _normalizeLevel(match.compLevel);
      if (level == null) continue;
      _byLevelAndNumber
          .putIfAbsent('$level:${match.matchNumber}', () => <StatboticsMatch>[])
          .add(match);
    }
  }

  final Map<String, StatboticsMatch> _byKey;
  final Map<String, List<StatboticsMatch>> _byLevelAndNumber;

  final Map<int, List<StatboticsMatch>> _byNumber;

  static const Map<String, String> _levelAliases = <String, String>{
    'qm': 'qm',
    'q': 'qm',
    'qual': 'qm',
    'quals': 'qm',
    'qualification': 'qm',
    'match': 'qm',
    'm': 'qm',
    'qf': 'qf',
    'quarterfinal': 'qf',
    'sf': 'sf',
    'semifinal': 'sf',
    'p': 'sf',
    'playoff': 'sf',
    'f': 'f',
    'final': 'f',
    'finals': 'f',
  };

  static String? _normalizeLevel(String raw) =>
      _levelAliases[raw.trim().toLowerCase()];

  StatboticsMatch? resolve(String matchId) {
    final found = candidates(matchId);
    return found.length == 1 ? found.first : null;
  }

  List<StatboticsMatch> candidates(String matchId) {
    final text = matchId.trim().toLowerCase();
    if (text.isEmpty) return const <StatboticsMatch>[];

    if (text.contains('_')) {
      final direct = _byKey[text];
      return direct == null
          ? const <StatboticsMatch>[]
          : <StatboticsMatch>[direct];
    }
    return _resolveSuffix(text);
  }

  int? numberOf(String matchId) => resolve(matchId)?.matchNumber;

  List<StatboticsMatch> _resolveSuffix(String text) {
    final match = RegExp(r'^([a-z]*)[\s\-]*(\d+)(?:[\s\-]*m[\s\-]*(\d+))?$')
        .firstMatch(text);
    if (match == null) return const <StatboticsMatch>[];

    final levelText = match.group(1) ?? '';
    final first = int.tryParse(match.group(2)!);
    final second = match.group(3) == null
        ? null
        : int.tryParse(match.group(3)!);
    if (first == null) return const <StatboticsMatch>[];

    if (levelText.isEmpty) {
      final byNumber = _byNumber[second ?? first];
      return byNumber == null
          ? const <StatboticsMatch>[]
          : List<StatboticsMatch>.unmodifiable(byNumber);
    }

    final level = _normalizeLevel(levelText);
    if (level == null) return const <StatboticsMatch>[];

    final number = second ?? first;
    final found = _byLevelAndNumber['$level:$number'];
    if (found == null || found.isEmpty) return const <StatboticsMatch>[];
    if (second == null) return List<StatboticsMatch>.unmodifiable(found);
    final wanted = '$level${first}m$second';
    return List<StatboticsMatch>.unmodifiable(
      found.where((m) => m.key.toLowerCase().endsWith(wanted)),
    );
  }
}
