import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/services/playoff_match_info_stats.dart';
import 'package:statbotics_client/statbotics_client.dart';

StatboticsMatch _match({
  String key = '2026txdri1_qf1',
  int matchNumber = 1,
  String compLevel = 'qf',
  required List<int> redTeams,
  required List<int> blueTeams,
}) {
  return StatboticsMatch(
    key: key,
    event: '2026txdri1',
    matchNumber: matchNumber,
    compLevel: compLevel,
    redTeams: redTeams,
    blueTeams: blueTeams,
  );
}

void main() {
  group('PlayoffMatchInfoStats.playoffMatchesFor', () {
    test('excludes qualification matches and other teams', () {
      final matches = [
        _match(
          key: 'qm1',
          compLevel: 'qm',
          redTeams: [3847, 1, 2],
          blueTeams: [4, 5, 6],
        ),
        _match(
          key: 'qf1',
          matchNumber: 1,
          redTeams: [3847, 1, 2],
          blueTeams: [4, 5, 6],
        ),
        _match(
          key: 'qf2',
          matchNumber: 2,
          redTeams: [7, 8, 9],
          blueTeams: [10, 11, 12],
        ),
      ];

      final result = PlayoffMatchInfoStats.playoffMatchesFor(matches, 3847);

      expect(result, hasLength(1));
      expect(result.single.key, 'qf1');
    });

    test('returns empty when myTeamNumber is null', () {
      expect(PlayoffMatchInfoStats.playoffMatchesFor([], null), isEmpty);
    });
  });

  group('PlayoffMatchInfoStats.allianceRowsFor', () {
    test('builds our alliance once from the first playoff match', () {
      final matches = [
        _match(
          key: 'qf1',
          matchNumber: 1,
          redTeams: [3847, 111, 222],
          blueTeams: [4, 5, 6],
        ),

        _match(
          key: 'qf2',
          matchNumber: 2,
          redTeams: [3847, 111, 222],
          blueTeams: [7, 8, 9],
        ),
      ];

      final rows = PlayoffMatchInfoStats.allianceRowsFor(
        matches: matches,
        myTeamNumber: 3847,
        scoutEntries: const [],
      );

      expect(rows.map((r) => r.teamNumber), containsAllInOrder([111, 222]));
      expect(rows, hasLength(2));
    });

    test('empty when 3847 has no playoff match', () {
      final rows = PlayoffMatchInfoStats.allianceRowsFor(
        matches: const [],
        myTeamNumber: 3847,
        scoutEntries: const [],
      );
      expect(rows, isEmpty);
    });
  });

  group('PlayoffMatchInfoStats.build', () {
    test('one entry per playoff match, in order', () {
      final matches = [
        _match(
          key: 'qf1',
          matchNumber: 1,
          redTeams: [3847, 1, 2],
          blueTeams: [4, 5, 6],
        ),
        _match(
          key: 'qf2',
          matchNumber: 2,
          redTeams: [3847, 1, 2],
          blueTeams: [7, 8, 9],
        ),
      ];

      final entries = PlayoffMatchInfoStats.build(
        matches: matches,
        myTeamNumber: 3847,
        scoutEntries: const [],
      );

      expect(entries, hasLength(2));
      expect(entries[0].match.key, 'qf1');
      expect(entries[0].opponents.map((r) => r.teamNumber), [4, 5, 6]);
      expect(entries[1].match.key, 'qf2');
      expect(entries[1].opponents.map((r) => r.teamNumber), [7, 8, 9]);
    });

    test('stops populating opponent tables once eliminated', () {
      final matches = [
        _match(
          key: 'sf1',
          matchNumber: 1,
          redTeams: [3847, 1, 2],
          blueTeams: [4, 5, 6],
        ),
        _match(
          key: 'sf2',
          matchNumber: 2,
          redTeams: [3847, 1, 2],
          blueTeams: [4, 5, 6],
        ),
        _match(
          key: 'sf3',
          matchNumber: 3,
          redTeams: [3847, 1, 2],
          blueTeams: [4, 5, 6],
        ),
      ];

      final entries = PlayoffMatchInfoStats.build(
        matches: matches,
        myTeamNumber: 3847,
        scoutEntries: const [],

        isEliminatedAfter: (match) => match.key == 'sf2',
      );

      expect(entries.map((e) => e.match.key), ['sf1', 'sf2']);
    });

    test('empty when 3847 has no playoff match', () {
      final entries = PlayoffMatchInfoStats.build(
        matches: const [],
        myTeamNumber: 3847,
        scoutEntries: const [],
      );
      expect(entries, isEmpty);
    });
  });
}
