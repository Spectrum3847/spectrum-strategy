import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/cycle_log.dart';
import 'package:spectrumstrategy/src/state/cycle_log_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

import 'support/fake_cycle_log_storage.dart';

void main() {
  test('appendEvent accumulates events for a (matchKey, team)', () async {
    final controller = CycleLogController(storage: FakeCycleLogStorage());
    await controller.bootstrap();

    await controller.recordEvent(
      matchKey: 'm1',
      team: 3847,
      kind: CycleEventKind.intake,
      offsetMs: 1000,
      phase: StrategyPhase.teleop,
    );
    await controller.recordEvent(
      matchKey: 'm1',
      team: 3847,
      kind: CycleEventKind.score,
      offsetMs: 3000,
      phase: StrategyPhase.teleop,
    );

    final log = controller.logFor('m1', 3847)!;
    expect(log.events, hasLength(2));
    expect(log.cycleTimesMs, <int>[2000]);
    expect(controller.logFor('m1', 254), isNull);
  });

  test('logs survive a fresh controller over the same storage', () async {
    final storage = FakeCycleLogStorage();
    final first = CycleLogController(storage: storage);
    await first.bootstrap();
    await first.appendEvent(
      'm1',
      3847,
      const CycleEvent(
        kind: CycleEventKind.feed,
        offsetMs: 500,
        phase: StrategyPhase.auton,
      ),
    );

    final second = CycleLogController(storage: storage);
    await second.bootstrap();
    final log = second.logFor('m1', 3847)!;
    expect(log.countOf(CycleEventKind.feed), 1);
    expect(log.events.single.phase, StrategyPhase.auton);
  });

  test('clearLog removes the log and deletes it from storage', () async {
    final storage = FakeCycleLogStorage();
    final controller = CycleLogController(storage: storage);
    await controller.bootstrap();
    await controller.appendEvent(
      'm1',
      3847,
      const CycleEvent(
        kind: CycleEventKind.intake,
        offsetMs: 0,
        phase: StrategyPhase.teleop,
      ),
    );

    await controller.clearLog('m1', 3847);
    expect(controller.logFor('m1', 3847), isNull);
    expect(storage.deletedKeys, contains('m1|3847'));

    final reloaded = CycleLogController(storage: storage);
    await reloaded.bootstrap();
    expect(reloaded.logFor('m1', 3847), isNull);
  });

  test('persisted snapshots reflect state at enqueue time, in order', () async {
    final storage = FakeCycleLogStorage();
    final controller = CycleLogController(storage: storage);
    await controller.bootstrap();

    storage.firstSaveGate = Completer<void>();
    final first = controller.appendEvent(
      'm1',
      3847,
      const CycleEvent(
        kind: CycleEventKind.intake,
        offsetMs: 1000,
        phase: StrategyPhase.teleop,
      ),
    );
    final second = controller.appendEvent(
      'm1',
      3847,
      const CycleEvent(
        kind: CycleEventKind.score,
        offsetMs: 3000,
        phase: StrategyPhase.teleop,
      ),
    );

    storage.firstSaveGate!.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(storage.savedLogs, hasLength(2));
    expect(storage.savedLogs[0].events, hasLength(1));
    expect(storage.savedLogs[1].events, hasLength(2));
  });

  test(
    'a failed save marks failedWrites, and a later success clears it',
    () async {
      final storage = FakeCycleLogStorage();
      final controller = CycleLogController(storage: storage);
      await controller.bootstrap();
      expect(controller.failedWrites.hasFailures, isFalse);

      storage.failNextSave = StateError('disk full');
      await controller.appendEvent(
        'm1',
        3847,
        const CycleEvent(
          kind: CycleEventKind.intake,
          offsetMs: 0,
          phase: StrategyPhase.teleop,
        ),
      );

      expect(controller.failedWrites.hasFailures, isTrue);
      expect(controller.failedWrites.unlandedCount, 1);

      await controller.appendEvent(
        'm1',
        3847,
        const CycleEvent(
          kind: CycleEventKind.score,
          offsetMs: 2000,
          phase: StrategyPhase.teleop,
        ),
      );

      expect(controller.failedWrites.hasFailures, isFalse);
    },
  );
}
