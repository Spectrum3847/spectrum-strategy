import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/entry_delivery.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';

import 'support/fake_scouting_storage.dart';
import 'support/fake_scouting_sync_service.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 2));

void main() {
  late FakeScoutingSyncService sync;
  late ScoutingController controller;

  Future<ScoutingController> start({ScoutingSyncService? service}) async {
    final c = ScoutingController(
      storage: FakeScoutingStorage(),
      syncService: service,
    );
    await c.bootstrap();
    return c;
  }

  Future<ScoutEntry> save({String notes = ''}) async {
    await controller.saveEntry(
      ScoutEntry(id: 'e-1', matchId: 'match-1', teamNumber: 3847, notes: notes),
    );
    await _settle();
    return controller.entries.single;
  }

  setUp(() {
    sync = FakeScoutingSyncService();
  });

  test('an entry with no sync service stays saved on this device', () async {
    controller = await start();
    final entry = await save();

    expect(controller.deliveryOf(entry), EntryDelivery.savedOnly);
    expect(controller.unconfirmedCount, 1);
  });

  test('an entry waits as pending while the push cannot go out', () async {
    sync.simulateOutage = true;
    controller = await start(service: sync);
    final entry = await save();

    expect(controller.deliveryOf(entry), EntryDelivery.pending);
    expect(controller.unconfirmedCount, 1);
    expect(controller.rejectedCount, 0);
  });

  test('an accepted push is sent, and a snapshot confirms it', () async {
    controller = await start(service: sync);
    final entry = await save();
    expect(controller.deliveryOf(entry), EntryDelivery.sent);
    expect(controller.unconfirmedCount, 1);

    sync.emitRemote(<ScoutEntry>[entry]);
    await _settle();

    expect(controller.deliveryOf(entry), EntryDelivery.confirmed);
    expect(controller.unconfirmedCount, 0);
  });

  test('an entry from another device counts as confirmed', () async {
    controller = await start(service: sync);
    sync.emitRemote(<ScoutEntry>[
      ScoutEntry(id: 'r-1', matchId: 'match-1', teamNumber: 254),
    ]);
    await _settle();

    expect(controller.entries, hasLength(1));
    expect(controller.unconfirmedCount, 0);
  });

  test('editing a confirmed entry makes it unconfirmed again', () async {
    controller = await start(service: sync);
    final first = await save();
    sync.emitRemote(<ScoutEntry>[first]);
    await _settle();
    expect(controller.deliveryOf(first), EntryDelivery.confirmed);

    await _tick();
    final edited = await save(notes: 'edited');
    expect(controller.deliveryOf(edited), EntryDelivery.sent);
    expect(controller.unconfirmedCount, 1);

    sync.emitRemote(<ScoutEntry>[edited]);
    await _settle();
    expect(controller.deliveryOf(edited), EntryDelivery.confirmed);
  });

  test('a refused push is rejected with the reason the server gave', () async {
    sync.simulateRejection = true;
    controller = await start(service: sync);
    final entry = await save();

    expect(controller.deliveryOf(entry), EntryDelivery.rejected);
    expect(
      controller.rejectionReasonOf(entry.id),
      'permission-denied: push rejected',
    );
    expect(controller.rejectedCount, 1);
    expect(controller.unconfirmedCount, 1);
  });

  test('a snapshot older than the refused version keeps it rejected', () async {
    sync.simulateRejection = true;
    controller = await start(service: sync);
    final entry = await save();

    sync.emitRemote(<ScoutEntry>[
      entry.copyWith(
        updatedAt: entry.updatedAt.subtract(const Duration(minutes: 1)),
      ),
    ]);
    await _settle();

    final current = controller.entries.single;
    expect(controller.deliveryOf(current), EntryDelivery.rejected);
    expect(controller.rejectedCount, 1);
  });

  test(
    'a late refusal of an older version does not reject the sent one',
    () async {
      controller = await start(service: sync);
      sync.simulateRejection = true;
      sync.rejectionGate = Completer<void>();
      await controller.saveEntry(
        ScoutEntry(
          id: 'e-1',
          matchId: 'match-1',
          teamNumber: 3847,
          notes: 'v1',
        ),
      );
      await _tick();

      sync.simulateRejection = false;
      await controller.saveEntry(
        controller.entries.single.copyWith(notes: 'v2'),
      );
      await _settle();
      sync.rejectionGate!.complete();
      await _settle();

      expect(
        controller.deliveryOf(controller.entries.single),
        EntryDelivery.sent,
      );
      expect(controller.rejectedCount, 0);
      expect(controller.failedWrites.hasFailures, isFalse);
    },
  );

  test('a snapshot with the refused version clears the rejection', () async {
    sync.simulateRejection = true;
    controller = await start(service: sync);
    final entry = await save();

    sync.emitRemote(<ScoutEntry>[entry]);
    await _settle();

    expect(controller.deliveryOf(entry), EntryDelivery.confirmed);
    expect(controller.rejectedCount, 0);
    expect(controller.rejectionReasonOf(entry.id), isNull);
  });

  test('showing a QR marks the entry sent by QR, not confirmed', () async {
    sync.simulateOutage = true;
    controller = await start(service: sync);
    final entry = await save();
    var notified = false;
    controller.addListener(() => notified = true);

    controller.markSharedByQr(entry);

    expect(notified, isTrue);
    expect(controller.deliveryOf(entry), EntryDelivery.sentByQr);
    expect(controller.unconfirmedCount, 1);
  });

  test('editing an entry after its QR was shown clears sent by QR', () async {
    sync.simulateOutage = true;
    controller = await start(service: sync);
    final entry = await save();
    controller.markSharedByQr(entry);

    await _tick();
    final edited = await save(notes: 'edited');

    expect(controller.deliveryOf(edited), EntryDelivery.pending);
  });
}
