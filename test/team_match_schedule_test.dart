import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/team_match_schedule.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

StatboticsMatch _match(
  String level,
  int number, {
  required List<int> red,
  required List<int> blue,
}) => StatboticsMatch(
  key: '2026test_$level$number',
  event: '2026test',
  matchNumber: number,
  compLevel: level,
  redTeams: red,
  blueTeams: blue,
);

TbaScheduleMatch _result(
  StatboticsMatch match, {
  int? red,
  int? blue,
  String? winner,
}) => TbaScheduleMatch(
  key: match.key,
  compLevel: match.compLevel,
  matchNumber: match.matchNumber,
  redTeams: match.redTeams,
  blueTeams: match.blueTeams,
  redScore: red,
  blueScore: blue,
  winningAlliance: winner,
);

void main() {
  final q1 = _match('qm', 1, red: [3847, 1, 2], blue: [3, 4, 5]);
  final q2 = _match('qm', 2, red: [6, 7, 8], blue: [9, 10, 11]);
  final q3 = _match('qm', 3, red: [1, 2, 3], blue: [3847, 4, 5]);
  final q4 = _match('qm', 4, red: [3847, 6, 7], blue: [8, 9, 10]);
  final q5 = _match('qm', 5, red: [3847, 9, 10], blue: [1, 2, 3]);
  final q6 = _match('qm', 6, red: [3847, 4, 6], blue: [1, 7, 8]);
  final f1 = _match('f', 1, red: [3847, 1, 2], blue: [3, 4, 5]);
  final sorted = [q1, q2, q3, q4, q5, q6, f1];

  final results = <String, TbaScheduleMatch>{
    q1.key: _result(q1, red: 100, blue: 80, winner: 'red'),
    q2.key: _result(q2, red: 50, blue: 60, winner: 'blue'),
    q3.key: _result(q3, red: 90, blue: 70, winner: 'red'),
    q4.key: _result(q4, red: 75, blue: 75),
    q5.key: _result(q5),

    q6.key: _result(q6, red: -1, blue: -1),
    f1.key: _result(f1, red: 120, blue: 110, winner: 'red'),
  };

  TeamMatchSchedule build(int team) => TeamMatchSchedule.build(
    team: team,
    sortedMatches: sorted,
    resultFor: (key) => results[key],
  );

  test('keeps only the team\'s matches, in schedule order', () {
    final schedule = build(3847);
    expect(schedule.matches.map((m) => m.match.key), [
      q1.key,
      q3.key,
      q4.key,
      q5.key,
      q6.key,
      f1.key,
    ]);
    expect(schedule.matches.map((m) => m.onRed), [
      true,
      false,
      true,
      true,
      true,
      true,
    ]);
  });

  test('reads each result from the team\'s side', () {
    final byKey = {for (final m in build(3847).matches) m.match.key: m};

    expect(byKey[q1.key]!.outcome, TeamMatchOutcome.win);
    expect(byKey[q1.key]!.ourScore, 100);
    expect(byKey[q1.key]!.theirScore, 80);

    expect(byKey[q3.key]!.outcome, TeamMatchOutcome.loss);
    expect(byKey[q3.key]!.ourScore, 70);
    expect(byKey[q3.key]!.theirScore, 90);

    expect(byKey[q4.key]!.outcome, TeamMatchOutcome.tie);

    expect(byKey[q5.key]!.isPlayed, isFalse);
    expect(byKey[q5.key]!.outcome, isNull);
    expect(byKey[q6.key]!.isPlayed, isFalse);
    expect(byKey[q6.key]!.ourScore, isNull);
  });

  test('the record counts played qualification matches only', () {
    final schedule = build(3847);
    expect(schedule.wins, 1);
    expect(schedule.losses, 1);
    expect(schedule.ties, 1);
    expect(
      schedule.record,
      '1-1-1',
      reason: 'the won final is a playoff and does not count',
    );
  });

  test('no results at all is an empty record, not a missing one', () {
    final schedule = TeamMatchSchedule.build(
      team: 3847,
      sortedMatches: sorted,
      resultFor: (_) => null,
    );
    expect(schedule.matches, hasLength(6));
    expect(schedule.record, '0-0-0');
  });

  test('a team with no matches gets an empty schedule', () {
    final schedule = build(9999);
    expect(schedule.matches, isEmpty);
    expect(schedule.record, '0-0-0');
  });
}
