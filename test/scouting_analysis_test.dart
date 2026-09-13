import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/team_analysis.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_analysis.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

ScoutEntry _entry({
  required String matchId,
  required int teamNumber,
  String alliance = 'Red',
  DateTime? updatedAt,
  Map<StrategyPhase, ScoutPhaseData>? byPhase,
}) {
  return ScoutEntry(
    matchId: matchId,
    teamNumber: teamNumber,
    alliance: alliance,
    updatedAt: updatedAt,
    byPhase: byPhase,
  );
}

void main() {
  group('TeamAnalysis.fromEntries', () {
    test('returns empty analysis when no entry matches the team', () {
      final analysis = TeamAnalysis.fromEntries(254, const <ScoutEntry>[]);

      expect(analysis.teamNumber, 254);
      expect(analysis.hasData, isFalse);
      expect(analysis.entryCount, 0);
      expect(analysis.matchCount, 0);
      expect(analysis.lastSeen, isNull);
      expect(analysis.iqmTotalScore, 0);
      expect(analysis.avgTotalPenalties, 0);

      for (final phase in StrategyPhase.values) {
        expect(analysis.phaseStats(phase).iqmScore, 0);
      }
    });

    test('aggregates scores, penalties, and counters across entries', () {
      final entries = <ScoutEntry>[
        _entry(
          matchId: 'qm1',
          teamNumber: 254,
          alliance: 'Red',
          updatedAt: DateTime.utc(2026, 1, 1),
          byPhase: {
            StrategyPhase.auton: const ScoutPhaseData(
              score: 10,
              penalties: 1,
              counters: {'cone': 2},
            ),
            StrategyPhase.teleop: const ScoutPhaseData(score: 20),
            StrategyPhase.endgame: const ScoutPhaseData(score: 5),
          },
        ),
        _entry(
          matchId: 'qm2',
          teamNumber: 254,
          alliance: 'Blue',
          updatedAt: DateTime.utc(2026, 1, 2),
          byPhase: {
            StrategyPhase.auton: const ScoutPhaseData(
              score: 20,
              counters: {'cone': 4, 'cube': 1},
            ),
            StrategyPhase.teleop: const ScoutPhaseData(score: 30, penalties: 2),
            StrategyPhase.endgame: const ScoutPhaseData(score: 15),
          },
        ),
      ];

      final analysis = TeamAnalysis.fromEntries(254, entries);

      expect(analysis.hasData, isTrue);
      expect(analysis.entryCount, 2);
      expect(analysis.matchCount, 2);
      expect(analysis.lastSeen, DateTime.utc(2026, 1, 2));
      expect(analysis.alliances, {'Red', 'Blue'});

      expect(analysis.phaseStats(StrategyPhase.auton).iqmScore, 15);
      expect(analysis.phaseStats(StrategyPhase.teleop).iqmScore, 25);
      expect(analysis.phaseStats(StrategyPhase.endgame).iqmScore, 10);
      expect(analysis.iqmTotalScore, 50);

      expect(analysis.phaseStats(StrategyPhase.auton).avgPenalties, 0.5);
      expect(analysis.phaseStats(StrategyPhase.teleop).avgPenalties, 1);
      expect(analysis.avgTotalPenalties, 1.5);

      final autonCounters = analysis.phaseStats(StrategyPhase.auton);
      expect(autonCounters.totalCounters, {'cone': 6, 'cube': 1});
      expect(autonCounters.avgCounters['cone'], 3.0);
      expect(autonCounters.avgCounters['cube'], 0.5);
    });

    test('counts distinct matches when a team is scouted twice per match', () {
      final entries = <ScoutEntry>[
        _entry(matchId: 'qm1', teamNumber: 254),
        _entry(matchId: 'qm1', teamNumber: 254),
        _entry(matchId: 'qm2', teamNumber: 254),
      ];

      final analysis = TeamAnalysis.fromEntries(254, entries);

      expect(analysis.entryCount, 3);
      expect(analysis.matchCount, 2);
    });

    test('ignores entries for other teams', () {
      final entries = <ScoutEntry>[
        _entry(
          matchId: 'qm1',
          teamNumber: 254,
          byPhase: {StrategyPhase.auton: const ScoutPhaseData(score: 10)},
        ),
        _entry(
          matchId: 'qm1',
          teamNumber: 1678,
          byPhase: {StrategyPhase.auton: const ScoutPhaseData(score: 999)},
        ),
      ];

      final analysis = TeamAnalysis.fromEntries(254, entries);

      expect(analysis.entryCount, 1);
      expect(analysis.phaseStats(StrategyPhase.auton).iqmScore, 10);
    });

    test('scoreStdDev is 0 for fewer than 2 entries', () {
      final empty = TeamAnalysis.fromEntries(254, const <ScoutEntry>[]);
      expect(empty.scoreStdDev, 0.0);

      final one = TeamAnalysis.fromEntries(254, [
        _entry(
          matchId: 'qm1',
          teamNumber: 254,
          byPhase: {StrategyPhase.teleop: const ScoutPhaseData(score: 30)},
        ),
      ]);
      expect(one.scoreStdDev, 0.0);
    });

    test('scoreStdDev is the population std dev of per-entry total scores', () {
      final entries = <ScoutEntry>[
        _entry(
          matchId: 'qm1',
          teamNumber: 254,
          byPhase: {StrategyPhase.teleop: const ScoutPhaseData(score: 10)},
        ),
        _entry(
          matchId: 'qm2',
          teamNumber: 254,
          byPhase: {StrategyPhase.teleop: const ScoutPhaseData(score: 30)},
        ),
      ];
      final analysis = TeamAnalysis.fromEntries(254, entries);
      expect(analysis.iqmTotalScore, 20.0);
      expect(analysis.scoreStdDev, closeTo(10.0, 1e-9));
    });

    test('scoreStdDev sums all three phases per entry', () {
      final entries = <ScoutEntry>[
        _entry(
          matchId: 'qm1',
          teamNumber: 254,
          byPhase: {
            StrategyPhase.auton: const ScoutPhaseData(score: 5),
            StrategyPhase.teleop: const ScoutPhaseData(score: 10),
            StrategyPhase.endgame: const ScoutPhaseData(score: 5),
          },
        ),
        _entry(
          matchId: 'qm2',
          teamNumber: 254,
          byPhase: {
            StrategyPhase.auton: const ScoutPhaseData(score: 10),
            StrategyPhase.teleop: const ScoutPhaseData(score: 20),
            StrategyPhase.endgame: const ScoutPhaseData(score: 10),
          },
        ),
      ];
      final analysis = TeamAnalysis.fromEntries(254, entries);
      expect(analysis.iqmTotalScore, 30.0);
      expect(analysis.scoreStdDev, closeTo(10.0, 1e-9));
    });

    test('scoreStdDev is 0 when all entries have the same total score', () {
      final entries = <ScoutEntry>[
        _entry(
          matchId: 'qm1',
          teamNumber: 254,
          byPhase: {StrategyPhase.teleop: const ScoutPhaseData(score: 25)},
        ),
        _entry(
          matchId: 'qm2',
          teamNumber: 254,
          byPhase: {StrategyPhase.teleop: const ScoutPhaseData(score: 25)},
        ),
        _entry(
          matchId: 'qm3',
          teamNumber: 254,
          byPhase: {StrategyPhase.teleop: const ScoutPhaseData(score: 25)},
        ),
      ];
      final analysis = TeamAnalysis.fromEntries(254, entries);
      expect(analysis.scoreStdDev, 0.0);
    });
  });

  group('ScoutingAnalysis', () {
    test('aggregateByTeam produces one analysis per team', () {
      final entries = <ScoutEntry>[
        _entry(matchId: 'qm1', teamNumber: 254),
        _entry(matchId: 'qm2', teamNumber: 254),
        _entry(matchId: 'qm1', teamNumber: 1678),
      ];

      final byTeam = ScoutingAnalysis.aggregateByTeam(entries);

      expect(byTeam.keys.toSet(), {254, 1678});
      expect(byTeam[254]!.entryCount, 2);
      expect(byTeam[1678]!.entryCount, 1);
    });

    test('teamNumbers returns distinct teams sorted ascending', () {
      final entries = <ScoutEntry>[
        _entry(matchId: 'qm1', teamNumber: 1678),
        _entry(matchId: 'qm1', teamNumber: 254),
        _entry(matchId: 'qm2', teamNumber: 254),
      ];

      expect(ScoutingAnalysis.teamNumbers(entries), [254, 1678]);
    });

    test('rankByScore orders by IQM total score, ties break on number', () {
      final entries = <ScoutEntry>[
        _entry(
          matchId: 'qm1',
          teamNumber: 1678,
          byPhase: {StrategyPhase.teleop: const ScoutPhaseData(score: 8)},
        ),
        _entry(
          matchId: 'qm1',
          teamNumber: 254,
          byPhase: {StrategyPhase.teleop: const ScoutPhaseData(score: 50)},
        ),

        _entry(
          matchId: 'qm1',
          teamNumber: 9999,
          byPhase: {StrategyPhase.teleop: const ScoutPhaseData(score: 8)},
        ),
      ];

      final ranked = ScoutingAnalysis.rankByScore(entries);

      expect(ranked.map((a) => a.teamNumber).toList(), [254, 1678, 9999]);
      expect(ranked.first.iqmTotalScore, 50);
    });
  });

  group('ScoutingAnalysis.notesForTeam', () {
    test('collects entry-level and per-phase notes, newest first', () {
      final entries = <ScoutEntry>[
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 254,
          authorDisplayName: 'Alex',
          notes: 'Strong cycler',
          updatedAt: DateTime.utc(2026, 1, 1),
          byPhase: {
            StrategyPhase.auton: const ScoutPhaseData(notes: 'Left on time'),
            StrategyPhase.teleop: const ScoutPhaseData(notes: '  '),
          },
        ),
        ScoutEntry(
          matchId: 'qm2',
          teamNumber: 254,
          authorDisplayName: 'Sam',
          notes: 'Tippy near the end',
          updatedAt: DateTime.utc(2026, 1, 2),
        ),

        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 1678,
          notes: 'Defense bot',
          updatedAt: DateTime.utc(2026, 1, 3),
        ),
      ];

      final notes = ScoutingAnalysis.notesForTeam(254, entries);

      expect(notes.length, 3);
      expect(notes.every((n) => n.text.trim().isNotEmpty), isTrue);

      expect(notes.first.matchId, 'qm2');
      expect(notes.first.text, 'Tippy near the end');
      expect(notes.first.author, 'Sam');
      expect(notes.first.phase, isNull);

      final autonNote = notes.firstWhere((n) => n.phase == StrategyPhase.auton);
      expect(autonNote.text, 'Left on time');
      expect(autonNote.matchId, 'qm1');
    });

    test('returns empty when the team has no notes', () {
      final entries = <ScoutEntry>[
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 254,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ];
      expect(ScoutingAnalysis.notesForTeam(254, entries), isEmpty);
    });
  });
  group('interquartileMean', () {
    test('is 0 for no values and the plain mean below 4 samples', () {
      expect(interquartileMean(const <num>[]), 0);
      expect(interquartileMean(const [7]), 7);
      expect(interquartileMean(const [10, 30]), 20);
      expect(interquartileMean(const [10, 20, 60]), 30);
    });

    test('is the mean of the middle two for 4 samples', () {
      expect(interquartileMean(const [1, 2, 3, 100]), 2.5);
    });

    test('weights the boundary samples fractionally for 5 samples', () {
      expect(interquartileMean(const [1, 2, 3, 4, 5]), closeTo(3, 1e-9));
    });

    test('resists a single outlier where the mean does not', () {
      const scores = [20, 20, 20, 20, 20, 20, 20, 0];
      expect(interquartileMean(scores), 20);
    });
  });

  group('TeamAnalysis.fromEntries with a scout config', () {
    const config = ScoutConfig(
      title: 'Test form',
      sections: [
        ScoutConfigSection(
          name: 'Prematch',
          fields: [
            ScoutConfigField(
              title: 'Starting position',
              type: ScoutFieldType.select,
              code: 'sp',
            ),
          ],
        ),
        ScoutConfigSection(
          name: 'Autonomous',
          fields: [
            ScoutConfigField(
              title: 'Auto Coral',
              type: ScoutFieldType.counter,
              code: 'ac',
            ),
            ScoutConfigField(
              title: 'Left zone',
              type: ScoutFieldType.boolean,
              code: 'lz',
            ),
          ],
        ),
        ScoutConfigSection(
          name: 'Teleop',
          fields: [
            ScoutConfigField(
              title: 'Teleop Coral',
              type: ScoutFieldType.counter,
              code: 'tc',
            ),
            ScoutConfigField(
              title: 'Algae',
              type: ScoutFieldType.counter,
              code: 'al',
            ),
          ],
        ),
        ScoutConfigSection(
          name: 'Endgame',
          fields: [
            ScoutConfigField(
              title: 'Climb level',
              type: ScoutFieldType.number,
              code: 'cl',
            ),
          ],
        ),
      ],
    );

    ScoutEntry formEntry(String matchId, Map<String, dynamic> values) {
      return ScoutEntry(
        matchId: matchId,
        teamNumber: 254,
        alliance: 'Red',
        updatedAt: DateTime.utc(2026, 1, 1),
        fieldValues: values,
      );
    }

    test('derives phase scores from fieldValues via the config', () {
      final entries = [
        formEntry('qm1', {'ac': 2, 'tc': 5, 'al': 3, 'cl': 1, 'sp': 'left'}),
        formEntry('qm2', {'ac': 4, 'tc': 7, 'al': 1, 'cl': 3, 'lz': true}),
      ];

      final analysis = TeamAnalysis.fromEntries(254, entries, config: config);

      expect(analysis.phaseStats(StrategyPhase.auton).iqmScore, 3);
      expect(analysis.phaseStats(StrategyPhase.teleop).iqmScore, 8);
      expect(analysis.phaseStats(StrategyPhase.endgame).iqmScore, 2);
      expect(analysis.iqmTotalScore, 13);

      final teleop = analysis.phaseStats(StrategyPhase.teleop);
      expect(teleop.avgCounters['Teleop Coral'], 6);
      expect(teleop.avgCounters['Algae'], 2);
      expect(teleop.totalCounters['Teleop Coral'], 12);

      expect(
        analysis
            .phaseStats(StrategyPhase.auton)
            .avgCounters
            .containsKey('Left zone'),
        isFalse,
      );
    });

    test('numeric strings parse; junk values are skipped', () {
      final entries = [
        formEntry('qm1', {'ac': '3', 'tc': 'not a number'}),
      ];

      final analysis = TeamAnalysis.fromEntries(254, entries, config: config);

      expect(analysis.phaseStats(StrategyPhase.auton).iqmScore, 3);
      expect(analysis.phaseStats(StrategyPhase.teleop).iqmScore, 0);
    });

    test('without the config, form-only entries have no statistics', () {
      final entries = [
        formEntry('qm1', {'ac': 2, 'tc': 5}),
      ];

      final analysis = TeamAnalysis.fromEntries(254, entries);

      expect(analysis.entryCount, 1);
      expect(analysis.iqmTotalScore, 0);
    });

    test('legacy phase data and fieldValues combine', () {
      final entries = [
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 254,
          updatedAt: DateTime.utc(2026, 1, 1),
          byPhase: {StrategyPhase.auton: const ScoutPhaseData(score: 10)},
          fieldValues: const {'ac': 2},
        ),
      ];

      final analysis = TeamAnalysis.fromEntries(254, entries, config: config);

      expect(analysis.phaseStats(StrategyPhase.auton).iqmScore, 12);
    });
  });
}
