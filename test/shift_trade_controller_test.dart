import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_shift_schedule.dart';
import 'package:spectrumstrategy/src/scouting/models/shift_trade.dart';
import 'package:spectrumstrategy/src/scouting/state/shift_trade_controller.dart';

import 'support/fake_shift_trade_sync_service.dart';

void main() {
  test('bootstrap loads trades and watchEvent filters to the event', () async {
    final sync = FakeShiftTradeSyncService(uid: 'requester-1');
    final controller = ShiftTradeController(syncService: sync);
    addTearDown(controller.dispose);

    await controller.bootstrap();
    await controller.watchEvent('2026miket');
    expect(controller.trades, isEmpty);

    await controller.requestTrade(
      targetUid: 'target-1',
      targetDisplayName: 'Target',
      requesterBlock: const ScoutShiftBlock(startMatch: 1, endMatch: 6),
    );

    await Future<void>.delayed(Duration.zero);

    expect(controller.trades, hasLength(1));
    expect(controller.trades.single.status, ShiftTradeStatus.pending);
    expect(controller.trades.single.requesterUid, 'requester-1');
  });

  test('requestTrade is a no-op with no signed-in user', () async {
    final sync = FakeShiftTradeSyncService(uid: '');
    final controller = ShiftTradeController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.watchEvent('2026miket');

    await controller.requestTrade(
      targetUid: 'target-1',
      targetDisplayName: 'Target',
      requesterBlock: const ScoutShiftBlock(startMatch: 1, endMatch: 6),
    );

    expect(sync.calls, isEmpty);
    expect(controller.trades, isEmpty);
  });

  test('accept/decline/cancel enqueue in order and one failure does not '
      'block later writes', () async {
    final sync = FakeShiftTradeSyncService(uid: 'requester-1');
    final controller = ShiftTradeController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.watchEvent('2026miket');

    await controller.requestTrade(
      targetUid: 'target-1',
      targetDisplayName: 'Target',
      requesterBlock: const ScoutShiftBlock(startMatch: 1, endMatch: 6),
    );
    await Future<void>.delayed(Duration.zero);
    final trade = controller.trades.single;

    sync.failNext = Exception('offline');
    await controller.accept(trade);
    expect(controller.failedWrites.hasFailures, isTrue);

    await controller.decline(trade);
    expect(controller.failedWrites.hasFailures, isFalse);
    expect(sync.calls, [
      'create:${trade.id}',
      'respond:${trade.id}:accepted',
      'respond:${trade.id}:declined',
    ]);
  });

  test(
    'pendingTradesFor drops resolved trades but keeps pending ones (#1408)',
    () async {
      final sync = FakeShiftTradeSyncService(uid: 'requester-1');
      final controller = ShiftTradeController(syncService: sync);
      addTearDown(controller.dispose);
      await controller.bootstrap();
      await controller.watchEvent('2026miket');

      await controller.requestTrade(
        targetUid: 'target-1',
        targetDisplayName: 'Target one',
        requesterBlock: const ScoutShiftBlock(startMatch: 1, endMatch: 6),
      );
      await controller.requestTrade(
        targetUid: 'target-2',
        targetDisplayName: 'Target two',
        requesterBlock: const ScoutShiftBlock(startMatch: 7, endMatch: 12),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.trades, hasLength(2));

      final toAccept = controller.trades.firstWhere(
        (t) => t.targetUid == 'target-1',
      );
      final toDecline = controller.trades.firstWhere(
        (t) => t.targetUid == 'target-2',
      );
      await controller.accept(toAccept);
      await controller.decline(toDecline);
      await Future<void>.delayed(Duration.zero);

      expect(controller.trades, hasLength(2));
      expect(controller.pendingTradesFor('requester-1'), isEmpty);

      await controller.requestTrade(
        targetUid: 'target-3',
        targetDisplayName: 'Target three',
        requesterBlock: const ScoutShiftBlock(startMatch: 1, endMatch: 3),
      );
      await Future<void>.delayed(Duration.zero);

      final stillPending = controller.pendingTradesFor('requester-1');
      expect(stillPending, hasLength(1));
      expect(stillPending.single.targetUid, 'target-3');
    },
  );

  test('acceptedTradesFor only surfaces resolved-accepted trades involving uid '
      '(#1455)', () async {
    final sync = FakeShiftTradeSyncService(uid: 'requester-1');
    final controller = ShiftTradeController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.watchEvent('2026miket');

    await controller.requestTrade(
      targetUid: 'target-1',
      targetDisplayName: 'Target one',
      requesterBlock: const ScoutShiftBlock(startMatch: 1, endMatch: 6),
    );
    await controller.requestTrade(
      targetUid: 'target-2',
      targetDisplayName: 'Target two',
      requesterBlock: const ScoutShiftBlock(startMatch: 7, endMatch: 12),
    );
    await Future<void>.delayed(Duration.zero);

    final toAccept = controller.trades.firstWhere(
      (t) => t.targetUid == 'target-1',
    );
    final toLeavePending = controller.trades.firstWhere(
      (t) => t.targetUid == 'target-2',
    );
    await controller.accept(toAccept);
    await Future<void>.delayed(Duration.zero);

    final accepted = controller.acceptedTradesFor('requester-1');
    expect(accepted, hasLength(1));
    expect(accepted.single.id, toAccept.id);
    expect(accepted.single.status, ShiftTradeStatus.accepted);
    expect(accepted.any((t) => t.id == toLeavePending.id), isFalse);
    expect(controller.acceptedTradesFor('target-1'), hasLength(1));
    expect(controller.acceptedTradesFor('nobody'), isEmpty);
  });

  test('effectiveSchedule overlays an accepted trade, leaving a pending one '
      'untouched', () async {
    final sync = FakeShiftTradeSyncService(uid: 'u0');
    final controller = ShiftTradeController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.watchEvent('2026miket');

    final schedule = ScoutShiftSchedule.generate(
      eventKey: '2026miket',
      matchCount: 12,

      roster: [
        for (var i = 0; i < 8; i++)
          ScoutShiftRosterEntry(uid: 'u$i', name: 'Scouter $i'),
      ],
    );
    final u0Block = schedule.rotationFor('u0')!.shifts.first;

    await controller.requestTrade(
      targetUid: 'u6',
      targetDisplayName: 'Scouter 6',
      requesterBlock: u0Block,
    );
    await Future<void>.delayed(Duration.zero);
    final trade = controller.trades.single;

    var effective = controller.effectiveSchedule(schedule);
    expect(effective.rotationFor('u0')!.isOnDuty(u0Block.startMatch), isTrue);

    await controller.accept(trade);
    await Future<void>.delayed(Duration.zero);
    effective = controller.effectiveSchedule(schedule);
    expect(effective.rotationFor('u0')!.isOnDuty(u0Block.startMatch), isFalse);
    expect(effective.rotationFor('u6')!.isOnDuty(u0Block.startMatch), isTrue);
  });

  test('effectiveSchedule keeps every roster column aligned after accepting a '
      'trade, even when several scouters share the empty "no linked account" '
      'uid (#1408)', () async {
    final sync = FakeShiftTradeSyncService(uid: 'u0');
    final controller = ShiftTradeController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.watchEvent('2026miket');

    final roster = [
      const ScoutShiftRosterEntry(uid: 'u0', name: 'Scouter 0'),
      for (var i = 1; i < 6; i++)
        ScoutShiftRosterEntry(uid: '', name: 'Scouter $i'),
      const ScoutShiftRosterEntry(uid: 'u6', name: 'Scouter 6'),
      const ScoutShiftRosterEntry(uid: '', name: 'Scouter 7'),
    ];
    final schedule = ScoutShiftSchedule.generate(
      eventKey: '2026miket',
      matchCount: 12,
      roster: roster,
    );
    final u0Block = schedule.rotationFor('u0')!.shifts.first;

    await controller.requestTrade(
      targetUid: 'u6',
      targetDisplayName: 'Scouter 6',
      requesterBlock: u0Block,
    );
    await Future<void>.delayed(Duration.zero);
    await controller.accept(controller.trades.single);
    await Future<void>.delayed(Duration.zero);

    final effective = controller.effectiveSchedule(schedule);

    expect(effective.rotations, hasLength(roster.length));
    for (var i = 0; i < roster.length; i++) {
      expect(effective.rotations[i].name, roster[i].name);
    }

    expect(effective.rotationFor('u0')!.isOnDuty(u0Block.startMatch), isFalse);
    expect(effective.rotationFor('u6')!.isOnDuty(u0Block.startMatch), isTrue);

    final regenerated = ScoutShiftSchedule.generate(
      eventKey: '2026miket',
      matchCount: 12,
      roster: roster,
    );
    final effectiveAfterRegenerate = controller.effectiveSchedule(regenerated);
    expect(effectiveAfterRegenerate.rotations, hasLength(roster.length));
    for (var i = 0; i < roster.length; i++) {
      expect(effectiveAfterRegenerate.rotations[i].name, roster[i].name);
    }
  });

  test('an accepted trade whose counterpart left the roster no-ops instead of '
      'dropping the traded block (#1408)', () async {
    final sync = FakeShiftTradeSyncService(uid: 'u0');
    final controller = ShiftTradeController(syncService: sync);
    addTearDown(controller.dispose);
    await controller.bootstrap();
    await controller.watchEvent('2026miket');

    final roster = [
      const ScoutShiftRosterEntry(uid: 'u0', name: 'Scouter 0'),
      const ScoutShiftRosterEntry(uid: 'u1', name: 'Scouter 1'),
      const ScoutShiftRosterEntry(uid: 'u6', name: 'Scouter 6'),
    ];
    final schedule = ScoutShiftSchedule.generate(
      eventKey: '2026miket',
      matchCount: 12,
      roster: roster,
    );
    final u0Block = schedule.rotationFor('u0')!.shifts.first;

    await controller.requestTrade(
      targetUid: 'u6',
      targetDisplayName: 'Scouter 6',
      requesterBlock: u0Block,
    );
    await Future<void>.delayed(Duration.zero);
    await controller.accept(controller.trades.single);
    await Future<void>.delayed(Duration.zero);

    final withoutTarget = ScoutShiftSchedule(
      eventKey: '2026miket',
      matchCount: 12,
      roster: roster.sublist(0, 2),
      rotations: [schedule.rotationFor('u0')!, schedule.rotationFor('u1')!],
    );
    final effective = controller.effectiveSchedule(withoutTarget);
    expect(effective.rotations, hasLength(2));
    expect(effective.rotationFor('u0')!.shifts, [
      ...withoutTarget.rotationFor('u0')!.shifts,
    ]);
    expect(effective.rotationFor('u0')!.isOnDuty(u0Block.startMatch), isTrue);
  });
}
