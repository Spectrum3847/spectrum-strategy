class TeamLoader {
  static const int _minTeamNumber = 1;
  static const int _maxTeamNumber = 99999;

  static List<int> parseTeamNumbers(String input) {
    final matches = RegExp(r'\d+').allMatches(input);
    final teams = <int>{};
    for (final match in matches) {
      final parsed = int.tryParse(match.group(0)!);
      if (parsed == null ||
          parsed < _minTeamNumber ||
          parsed > _maxTeamNumber) {
        continue;
      }
      teams.add(parsed);
    }
    final result = teams.toList()..sort();
    return result;
  }
}
