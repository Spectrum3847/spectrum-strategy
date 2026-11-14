import 'package:statbotics_client/statbotics_client.dart';

class ScheduledRobot {
  const ScheduledRobot({
    required this.team,
    required this.position,
    required this.alliance,
    required this.slot,
  });

  final int team;
  final String position;

  final String alliance;

  final int slot;

  String get label => 'Team $team ($alliance $slot)';
}

class ScoutSchedule {
  const ScoutSchedule({required this.robotsByMatch});

  const ScoutSchedule.empty()
    : robotsByMatch = const <int, List<ScheduledRobot>>{};

  final Map<int, List<ScheduledRobot>> robotsByMatch;

  bool get isEmpty => robotsByMatch.isEmpty;

  List<int> get matchNumbers {
    final numbers = robotsByMatch.keys.toList()..sort();
    return List<int>.unmodifiable(numbers);
  }

  List<ScheduledRobot> robotsFor(int? matchNumber) => matchNumber == null
      ? const <ScheduledRobot>[]
      : (robotsByMatch[matchNumber] ?? const <ScheduledRobot>[]);

  ScheduledRobot? robotForStation(int? matchNumber, String station) {
    final wanted = normalizeStation(station);
    if (wanted == null) return null;
    for (final robot in robotsFor(matchNumber)) {
      if (robot.position == wanted) return robot;
    }
    return null;
  }

  static String? normalizeStation(String station) {
    final match = _stationPattern.firstMatch(station.trim().toUpperCase());
    if (match == null) return null;
    final alliance = match.group(1)!.startsWith('R') ? 'R' : 'B';
    return '$alliance${match.group(2)}';
  }

  static final RegExp _stationPattern = RegExp(r'^(RED|BLUE|R|B)\s*([123])$');

  static ScoutSchedule fromMatches(Iterable<StatboticsMatch> matches) {
    final byMatch = <int, List<ScheduledRobot>>{};
    for (final match in matches.where((m) => m.compLevel == 'qm')) {
      final robots = <ScheduledRobot>[
        for (var i = 0; i < match.redTeams.length; i++)
          ScheduledRobot(
            team: match.redTeams[i],
            position: 'R${i + 1}',
            alliance: 'Red',
            slot: i + 1,
          ),
        for (var i = 0; i < match.blueTeams.length; i++)
          ScheduledRobot(
            team: match.blueTeams[i],
            position: 'B${i + 1}',
            alliance: 'Blue',
            slot: i + 1,
          ),
      ];
      if (robots.isNotEmpty) byMatch[match.matchNumber] = robots;
    }
    return ScoutSchedule(robotsByMatch: byMatch);
  }
}
