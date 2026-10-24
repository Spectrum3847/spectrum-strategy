import 'package:flutter_test/flutter_test.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/match_hub_stats.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

StatboticsMatch _match({String level = 'qm', int number = 4}) {
  return StatboticsMatch(
    key: '2026x_$level$number',
    event: '2026x',
    matchNumber: number,
    compLevel: level,
    redTeams: const <int>[3847, 118, 2056],
    blueTeams: const <int>[971, 1323, 33],
  );
}

ScoutEntry _entry(int team, {String matchId = 'qm4', String? key, int? total}) {
  return ScoutEntry(
    matchId: matchId,
    teamNumber: team,
    tbaMatchKey: key,
    byPhase: <StrategyPhase, ScoutPhaseData>{
      StrategyPhase.teleop: ScoutPhaseData(score: total ?? 0),
    },
  );
}

void main() {
  group('entriesForMatch', () {
    test('joins on the TBA key, then on the typed match', () {
      final entries = <ScoutEntry>[
        _entry(3847, key: '2026x_qm4'),
        _entry(118, matchId: 'Q4'),
        _entry(971, matchId: '4'),
        _entry(254, matchId: 'qm5'),
        _entry(1678, key: '2026x_qm5'),
      ];

      final found = entriesForMatch(_match(), entries);

      expect(found.map((e) => e.teamNumber), <int>[3847, 118, 971]);
    });

    test('a bare number is not read as a playoff match', () {
      final entries = <ScoutEntry>[_entry(3847, matchId: '4')];

      expect(entriesForMatch(_match(level: 'sf'), entries), isEmpty);
    });
  });

  test('scoutedVersusOfficial sums only the robots that were scouted', () {
    final sides = scoutedVersusOfficial(
      _match(),
      scoutEntries: <ScoutEntry>[
        _entry(3847, key: '2026x_qm4', total: 20),
        _entry(118, key: '2026x_qm4', total: 15),
        _entry(971, key: '2026x_qm4', total: 9),
      ],
      redOfficial: 60,
      blueOfficial: 40,
    );

    expect(sides.red.scoutedTotal, 35);
    expect(sides.red.scoutedRobots, 2);
    expect(sides.red.officialScore, 60);
    expect(sides.blue.scoutedTotal, 9);
    expect(sides.blue.scoutedRobots, 1);
    expect(sides.blue.teamScores[1323], isNull);
  });

  group('startConflicts', () {
    List<ScoutEntry> starts(int team, String spot) => <ScoutEntry>[
      for (var i = 0; i < 2; i++)
        ScoutEntry(
          matchId: 'qm$i',
          teamNumber: team,
          fieldValues: <String, dynamic>{'starting': spot},
        ),
    ];
    final entries = <ScoutEntry>[
      ...starts(3847, 'Center'),
      ...starts(118, 'Center'),
      ...starts(971, 'Left'),
      ...starts(1323, 'Left'),
    ];

    MatchHubData build(int? myTeam) => MatchHubData.build(
      _match(),
      nicknames: const <int, String>{},
      teamEvents: const <int, StatboticsTeamEvent>{},
      scoutEntries: entries,
      myTeamNumber: myTeam,
    );

    test('covers our alliance only when we play', () {
      expect(build(3847).startConflicts.map((c) => c.position), ['Center']);
      expect(build(971).startConflicts.map((c) => c.position), ['Left']);
    });

    test('covers both alliances when we are not in the match', () {
      expect(build(254).startConflicts.map((c) => c.position), [
        'Center',
        'Left',
      ]);
    });
  });
}
