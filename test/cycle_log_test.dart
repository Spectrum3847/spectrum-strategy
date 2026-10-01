import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/cycle_log.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

CycleEvent _event(CycleEventKind kind, int offsetMs, [StrategyPhase? phase]) =>
    CycleEvent(
      kind: kind,
      offsetMs: offsetMs,
      phase: phase ?? StrategyPhase.teleop,
    );

void main() {
  group('CycleEvent json', () {
    test('round-trips through toJson/fromJson', () {
      const event = CycleEvent(
        kind: CycleEventKind.score,
        offsetMs: 4200,
        phase: StrategyPhase.auton,
      );
      final decoded = CycleEvent.fromJson(event.toJson());
      expect(decoded.kind, CycleEventKind.score);
      expect(decoded.offsetMs, 4200);
      expect(decoded.phase, StrategyPhase.auton);
    });
  });

  group('CycleLog json', () {
    test('round-trips with events preserved in order', () {
      final log = CycleLog(
        matchKey: '2026casj_qm1',
        team: 3847,
        events: <CycleEvent>[
          _event(CycleEventKind.intake, 1000),
          _event(CycleEventKind.score, 3000),
        ],
      );
      final decoded = CycleLog.fromJson(log.toJson());
      expect(decoded.matchKey, '2026casj_qm1');
      expect(decoded.team, 3847);
      expect(decoded.events, hasLength(2));
      expect(decoded.events.first.kind, CycleEventKind.intake);
      expect(decoded.events.last.offsetMs, 3000);
    });

    test('key composes matchKey and team', () {
      expect(CycleLog.keyFor('2026casj_qm1', 3847), '2026casj_qm1|3847');
    });
  });

  group('CycleLog stats', () {
    test('empty log yields null cycle stats and zero counts', () {
      const log = CycleLog(matchKey: 'm', team: 1);
      expect(log.cycleTimesMs, isEmpty);
      expect(log.meanCycleMs, isNull);
      expect(log.medianCycleMs, isNull);
      for (final kind in CycleEventKind.values) {
        expect(log.countOf(kind), 0);
      }
    });

    test('pairs each intake with the next score (mean/median, even count)', () {
      final log = CycleLog(
        matchKey: 'm',
        team: 1,
        events: <CycleEvent>[
          _event(CycleEventKind.intake, 1000),
          _event(CycleEventKind.score, 3000),
          _event(CycleEventKind.intake, 5000),
          _event(CycleEventKind.score, 6000),
        ],
      );
      expect(log.cycleTimesMs, <int>[2000, 1000]);
      expect(log.meanCycleMs, 1500);
      expect(log.medianCycleMs, 1500);
    });

    test('median of odd cycle count is the middle value', () {
      final log = CycleLog(
        matchKey: 'm',
        team: 1,
        events: <CycleEvent>[
          _event(CycleEventKind.intake, 0),
          _event(CycleEventKind.score, 1000),
          _event(CycleEventKind.intake, 2000),
          _event(CycleEventKind.score, 4000),
          _event(CycleEventKind.intake, 5000),
          _event(CycleEventKind.score, 8000),
        ],
      );
      expect(log.medianCycleMs, 2000);
      expect(log.meanCycleMs, 2000);
    });

    test('sorts by offset before deriving cycles', () {
      final log = CycleLog(
        matchKey: 'm',
        team: 1,
        events: <CycleEvent>[
          _event(CycleEventKind.score, 3000),
          _event(CycleEventKind.intake, 1000),
        ],
      );
      expect(log.cycleTimesMs, <int>[2000]);
    });

    test('score with no preceding intake contributes no cycle', () {
      final log = CycleLog(
        matchKey: 'm',
        team: 1,
        events: <CycleEvent>[
          _event(CycleEventKind.score, 500),
          _event(CycleEventKind.intake, 1000),
          _event(CycleEventKind.score, 2500),
        ],
      );
      expect(log.cycleTimesMs, <int>[1500]);
    });

    test('intake with no following score contributes no cycle', () {
      final log = CycleLog(
        matchKey: 'm',
        team: 1,
        events: <CycleEvent>[
          _event(CycleEventKind.intake, 1000),
          _event(CycleEventKind.score, 2000),
          _event(CycleEventKind.intake, 5000),
        ],
      );
      expect(log.cycleTimesMs, <int>[1000]);
    });

    test('a second intake before a score replaces the pending one', () {
      final log = CycleLog(
        matchKey: 'm',
        team: 1,
        events: <CycleEvent>[
          _event(CycleEventKind.intake, 1000),
          _event(CycleEventKind.intake, 2000),
          _event(CycleEventKind.score, 3000),
        ],
      );
      expect(log.cycleTimesMs, <int>[1000]);
    });

    test('counts every kind', () {
      final log = CycleLog(
        matchKey: 'm',
        team: 1,
        events: <CycleEvent>[
          _event(CycleEventKind.intake, 0),
          _event(CycleEventKind.score, 1),
          _event(CycleEventKind.score, 2),
          _event(CycleEventKind.feed, 3),
          _event(CycleEventKind.defense, 4),
          _event(CycleEventKind.defense, 5),
        ],
      );
      expect(log.countOf(CycleEventKind.intake), 1);
      expect(log.countOf(CycleEventKind.score), 2);
      expect(log.countOf(CycleEventKind.feed), 1);
      expect(log.countOf(CycleEventKind.defense), 2);
    });
  });

  group('CycleLog forward-compat', () {
    test('drops an event with an unknown kind instead of throwing', () {
      final json = <String, dynamic>{
        'matchKey': 'Q1',
        'team': 254,
        'events': [
          {'kind': 'intake', 'offsetMs': 0, 'phase': 'teleop'},
          {'kind': 'climb', 'offsetMs': 100, 'phase': 'endgame'},
          {'kind': 'score', 'offsetMs': 200, 'phase': 'teleop'},
        ],
      };
      final log = CycleLog.fromJson(json);
      expect(log.events.length, 2);
      expect(log.countOf(CycleEventKind.intake), 1);
      expect(log.countOf(CycleEventKind.score), 1);

      expect(log.cycleTimesMs, [200]);
    });
  });
}
