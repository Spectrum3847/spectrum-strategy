import 'package:flutter_test/flutter_test.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/services/scouting_coverage.dart';

void main() {
  StatboticsMatch qual(int number, List<int> red, List<int> blue) =>
      StatboticsMatch(
        key: '2026test_qm$number',
        event: '2026test',
        matchNumber: number,
        compLevel: 'qm',
        redTeams: red,
        blueTeams: blue,
      );

  ScoutEntry entry(int team, int matchNumber, {String author = 'Sam'}) =>
      ScoutEntry(
        matchId: 'session-$matchNumber',
        teamNumber: team,
        authorDisplayName: author,
        fieldValues: <String, dynamic>{'matchNumber': matchNumber},
      );

  final schedule = <StatboticsMatch>[
    qual(1, [254, 118, 2056], [971, 1323, 33]),
    qual(2, [3847, 118, 1323], [971, 2056, 33]),
  ];

  test('a fully scouted match reads as complete', () {
    final coverage = ScoutingCoverage.build(
      schedule: <StatboticsMatch>[schedule.first],
      entries: [
        for (final t in <int>[254, 118, 2056, 971, 1323, 33]) entry(t, 1),
      ],
    );

    expect(coverage.matches.single.isComplete, isTrue);
    expect(coverage.matches.single.missingTeams, isEmpty);
    expect(coverage.fraction, 1.0);
  });

  test('holes are reported per team, which is what a lead dispatches on', () {
    final coverage = ScoutingCoverage.build(
      schedule: <StatboticsMatch>[schedule.first],
      entries: [entry(254, 1), entry(971, 1)],
    );

    final match = coverage.matches.single;
    expect(match.isComplete, isFalse);
    expect(match.scoutedCount, 2);
    expect(match.missingTeams, <int>[118, 2056, 1323, 33]);
  });

  test('slots carry their alliance, red before blue', () {
    final coverage = ScoutingCoverage.build(
      schedule: <StatboticsMatch>[schedule.first],
      entries: const <ScoutEntry>[],
    );

    final slots = coverage.matches.single.slots;
    expect(slots.take(3).map((s) => s.alliance), everyElement('Red'));
    expect(slots.skip(3).map((s) => s.alliance), everyElement('Blue'));
  });

  test('an entry for another match does not cover this one', () {
    final coverage = ScoutingCoverage.build(
      schedule: schedule,
      entries: [entry(118, 2)],
    );

    expect(coverage.matches.first.missingTeams, contains(118));
    expect(coverage.matches.last.missingTeams, isNot(contains(118)));
  });

  test('an entry with no match number covers nothing', () {
    final coverage = ScoutingCoverage.build(
      schedule: <StatboticsMatch>[schedule.first],
      entries: [
        ScoutEntry(matchId: 'x', teamNumber: 254, authorDisplayName: 'Sam'),
      ],
    );

    expect(coverage.matches.single.scoutedCount, 0);
  });

  test('a match number stored as a string still matches', () {
    final coverage = ScoutingCoverage.build(
      schedule: <StatboticsMatch>[schedule.first],
      entries: [
        ScoutEntry(
          matchId: 'x',
          teamNumber: 254,
          fieldValues: const <String, dynamic>{'matchNumber': ' 1 '},
        ),
      ],
    );

    expect(coverage.matches.single.scoutedCount, 1);
  });

  test('playoff matches are excluded, not shown as permanent holes', () {
    final coverage = ScoutingCoverage.build(
      schedule: <StatboticsMatch>[
        schedule.first,
        StatboticsMatch(
          key: '2026test_f1m1',
          event: '2026test',
          matchNumber: 1,
          compLevel: 'f',
          redTeams: const <int>[254],
          blueTeams: const <int>[971],
        ),
      ],
      entries: const <ScoutEntry>[],
    );

    expect(coverage.matches, hasLength(1));
    expect(coverage.matches.single.compLevel, 'qm');
  });

  test('an empty schedule is empty coverage, not a divide by zero', () {
    final coverage = ScoutingCoverage.build(
      schedule: const <StatboticsMatch>[],
      entries: [entry(254, 1)],
    );

    expect(coverage.isEmpty, isTrue);
    expect(coverage.fraction, 0);
    expect(coverage.totalSlots, 0);
  });

  test('incomplete matches are ordered worst first', () {
    final coverage = ScoutingCoverage.build(
      schedule: schedule,
      entries: [
        entry(254, 1),
        for (final t in <int>[3847, 118, 1323, 971, 2056]) entry(t, 2),
      ],
    );

    expect(coverage.incompleteMatches.map((m) => m.matchNumber), <int>[1, 2]);
  });
}
