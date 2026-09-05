import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/trait_config.dart';
import 'package:spectrumstrategy/src/scouting/models/team_analysis.dart';
import 'package:spectrumstrategy/src/services/assistant/trait_draft.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

void main() {
  const traits = [
    TraitDefinition(key: 'cycleTime', label: 'Cycle time'),
    TraitDefinition(key: 'defense', label: 'Defense'),
    TraitDefinition(key: 'driverSkill', label: 'Driver skill'),
  ];

  group('request', () {
    test('is not built with no qualitative traits', () {
      expect(
        TraitDraft.request(
          eventKey: '2026miket',
          matchId: 'qm14',
          teamNumber: 254,
          qualitativeTraits: const [],
          analysis: const TeamAnalysis(teamNumber: 254, entryCount: 4),
          notes: const [],
        ),
        isNull,
      );
    });

    test('is not built when too little is scouted', () {
      expect(
        TraitDraft.request(
          eventKey: '2026miket',
          matchId: 'qm14',
          teamNumber: 254,
          qualitativeTraits: traits,
          analysis: TeamAnalysis(
            teamNumber: 254,
            entryCount: TraitDraft.minimumEntries - 1,
          ),
          notes: const [],
        ),
        isNull,
      );
    });

    test('carries the team, phase numbers, and comments', () {
      final request = TraitDraft.request(
        eventKey: '2026miket',
        matchId: 'qm14',
        teamNumber: 254,
        qualitativeTraits: traits,
        analysis: const TeamAnalysis(
          teamNumber: 254,
          entryCount: 4,
          matchCount: 4,
          byPhase: {StrategyPhase.teleop: PhaseStats(iqmScore: 32.4)},
        ),
        notes: [
          TeamNote(
            matchId: 'qm10',
            text: 'tipped reaching for the high goal',
            author: 'scouter one',
            updatedAt: DateTime.utc(2026, 8, 1),
          ),
        ],
      )!;

      expect(request.prompt, contains('Team 254'));
      expect(request.prompt, contains('32.4'));
      expect(request.prompt, contains('tipped reaching for the high goal'));
      expect(request.prompt, contains('cycleTime:'));
      expect(request.coverage, 4);
    });

    test('the same team in two matches does not share a cache key', () {
      expect(
        TraitDraft.cacheKeyFor(
          eventKey: '2026miket',
          matchId: 'qm14',
          teamNumber: 254,
        ),
        isNot(
          TraitDraft.cacheKeyFor(
            eventKey: '2026miket',
            matchId: 'qm15',
            teamNumber: 254,
          ),
        ),
      );
    });
  });

  group('parse', () {
    test('reads one line per requested trait', () {
      final parsed = TraitDraft.parse(
        'cycleTime: fast, consistent cycles\n'
        'defense: plays it occasionally\n'
        'driverSkill: confident in traffic',
        traits,
      );

      expect(parsed['cycleTime'], 'fast, consistent cycles');
      expect(parsed['defense'], 'plays it occasionally');
      expect(parsed['driverSkill'], 'confident in traffic');
    });

    test('drops a trait the model said it could not answer', () {
      final parsed = TraitDraft.parse(
        'cycleTime: not enough data\n'
        'defense: plays it occasionally\n'
        'driverSkill: not enough data',
        traits,
      );

      expect(parsed.containsKey('cycleTime'), isFalse);
      expect(parsed['defense'], 'plays it occasionally');
      expect(parsed.containsKey('driverSkill'), isFalse);
    });

    test('ignores a key that was never asked for', () {
      final parsed = TraitDraft.parse(
        'cycleTime: fast\nsomeOtherTrait: made up',
        traits,
      );

      expect(parsed.containsKey('someOtherTrait'), isFalse);
    });

    test('ignores stray text with no colon', () {
      final parsed = TraitDraft.parse(
        'Here is what I found:\ncycleTime: fast',
        traits,
      );

      expect(parsed['cycleTime'], 'fast');
      expect(parsed.length, 1);
    });
  });

  group('numericDraft', () {
    const trait = TraitDefinition(
      key: 'teleopScoring',
      label: 'Teleop scoring',
      source: TraitSource.phaseScore,
      phase: 'teleop',
    );

    test('is null with no analysis at all', () {
      expect(TraitDraft.numericDraft(trait, null), isNull);
    });

    test('is null when the team has no scouted entries', () {
      expect(
        TraitDraft.numericDraft(trait, const TeamAnalysis(teamNumber: 254)),
        isNull,
      );
    });

    test('is null for a qualitative trait, which is never computed', () {
      expect(
        TraitDraft.numericDraft(
          const TraitDefinition(key: 'defense', label: 'Defense'),
          const TeamAnalysis(teamNumber: 254, entryCount: 4),
        ),
        isNull,
      );
    });

    test('reads the phase mean for a phaseScore trait', () {
      final draft = TraitDraft.numericDraft(
        trait,
        const TeamAnalysis(
          teamNumber: 254,
          entryCount: 4,
          byPhase: {StrategyPhase.teleop: PhaseStats(iqmScore: 32.4)},
        ),
      );

      expect(draft, contains('32.4'));
      expect(draft, contains('teleop'));
    });
  });
}
