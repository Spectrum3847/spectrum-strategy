import 'package:flutter_test/flutter_test.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/models/now_summary.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_shift_schedule.dart';

const _event = '2026test';

StatboticsMatch _qual(int n, List<int> red, List<int> blue) {
  return StatboticsMatch(
    key: '${_event}_qm$n',
    event: _event,
    matchNumber: n,
    compLevel: 'qm',
    redTeams: red,
    blueTeams: blue,
  );
}

ScoutEntry _entry(int team, int match) => ScoutEntry(
  matchId: 'm$match',
  teamNumber: team,
  tbaMatchKey: '${_event}_qm$match',
);

final _matches = [
  _qual(1, [1, 2, 3], [4, 5, 6]),
  _qual(2, [7, 8, 9], [10, 11, 12]),
  _qual(3, [1, 8, 9], [4, 11, 12]),
  _qual(4, [7, 2, 3], [10, 5, 6]),
  StatboticsMatch(
    key: '${_event}_sf1m1',
    event: _event,
    matchNumber: 1,
    compLevel: 'sf',
    redTeams: const [1, 2, 3],
    blueTeams: const [4, 5, 6],
  ),
];

void main() {
  group('NowSummary', () {
    test('a match counts as played once two robots have an entry', () {
      final one = NowSummary.build(
        matches: _matches,
        myTeam: 1,
        entries: [_entry(7, 2)],
      );
      final two = NowSummary.build(
        matches: _matches,
        myTeam: 1,
        entries: [_entry(7, 2), _entry(8, 2)],
      );

      expect(one.playedThrough, isNull);
      expect(two.playedThrough, 2);
    });

    test('splits our next match into partners and opponents', () {
      final summary = NowSummary.build(
        matches: _matches,
        myTeam: 1,
        entries: [_entry(7, 2), _entry(8, 2)],
      );

      final next = summary.next!;
      expect(next.match.matchNumber, 3);
      expect(next.ourAlliance, 'Red');
      expect(next.opposingAlliance, 'Blue');
      expect(next.partners, [8, 9]);
      expect(next.opponents, [4, 11, 12]);
      expect(next.matchesAway, 0);
      expect(summary.ourQualCount, 2);
    });

    test('counts the matches between now and ours', () {
      final summary = NowSummary.build(
        matches: _matches,
        myTeam: 2,
        entries: [_entry(1, 1), _entry(4, 1)],
      );

      expect(summary.next!.match.matchNumber, 4);
      expect(summary.next!.matchesAway, 2);
    });

    test('has no distance until scouting shows progress', () {
      final summary = NowSummary.build(
        matches: _matches,
        myTeam: 2,
        entries: const [],
      );

      expect(summary.next!.match.matchNumber, 1);
      expect(summary.next!.matchesAway, isNull);
    });

    test('has no next match without a team, or once ours are played', () {
      final noTeam = NowSummary.build(
        matches: _matches,
        myTeam: null,
        entries: const [],
      );
      final done = NowSummary.build(
        matches: _matches,
        myTeam: 7,
        entries: [_entry(1, 4), _entry(2, 4)],
      );

      expect(noTeam.next, isNull);
      expect(done.next, isNull);
      expect(done.ourQualCount, 2);
    });

    test('ignores playoff matches', () {
      final summary = NowSummary.build(
        matches: _matches,
        myTeam: 1,
        entries: [_entry(7, 3), _entry(8, 3)],
      );

      expect(summary.next, isNull);
      expect(summary.ourQualCount, 2);
    });

    test('lists the unscouted robots of recent played matches', () {
      final summary = NowSummary.build(
        matches: _matches,
        myTeam: 1,
        entries: [_entry(7, 2), _entry(8, 2), _entry(9, 2)],
      );

      expect(summary.unscouted.map((m) => m.match.matchNumber), [1, 2]);
      expect(summary.unscouted.last.teams, [10, 11, 12]);
      expect(summary.unscoutedRobots, 9);
    });

    test('reports no unscouted robots before any match is played', () {
      final summary = NowSummary.build(
        matches: _matches,
        myTeam: 1,
        entries: const [],
      );

      expect(summary.unscouted, isEmpty);
    });

    group('shift', () {
      ScouterShiftRotation rotation(List<ScoutShiftBlock> shifts) {
        return ScouterShiftRotation(uid: 'u', name: 'Sam', shifts: shifts);
      }

      const early = ScoutShiftBlock(startMatch: 1, endMatch: 2);
      const current = ScoutShiftBlock(startMatch: 3, endMatch: 4);
      const late = ScoutShiftBlock(startMatch: 8, endMatch: 10);

      test('is the next block, with matches until it starts', () {
        final summary = NowSummary.build(
          matches: _matches,
          myTeam: 1,
          entries: [_entry(7, 2), _entry(8, 2)],
          rotation: rotation([early, late]),
        );

        expect(summary.shift!.startMatch, 8);
        expect(summary.shiftMatchesAway, 5);
      });

      test('is on duty when it covers the next match', () {
        final summary = NowSummary.build(
          matches: _matches,
          myTeam: 1,
          entries: [_entry(7, 2), _entry(8, 2)],
          rotation: rotation([current]),
        );

        expect(summary.shift!.startMatch, 3);
        expect(summary.shiftMatchesAway, 0);
      });

      test('is null once every block has ended', () {
        final summary = NowSummary.build(
          matches: _matches,
          myTeam: 1,
          entries: [_entry(1, 4), _entry(2, 4)],
          rotation: rotation([early, current]),
        );

        expect(summary.shift, isNull);
      });

      test('has no distance when progress is unknown', () {
        final summary = NowSummary.build(
          matches: _matches,
          myTeam: 1,
          entries: const [],
          rotation: rotation([early, late]),
        );

        expect(summary.shift!.startMatch, 1);
        expect(summary.shiftMatchesAway, isNull);
      });
    });
  });
}
