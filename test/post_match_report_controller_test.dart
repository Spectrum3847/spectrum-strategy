import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/post_match_report.dart';
import 'package:spectrumstrategy/src/state/post_match_report_controller.dart';

import 'support/fake_post_match_report_storage.dart';
import 'support/fake_post_match_report_sync_service.dart';

void main() {
  late FakePostMatchReportSyncService sync;
  late FakePostMatchReportStorage storage;
  late PostMatchReportController controller;

  Future<PostMatchReportController> ready(
    FakePostMatchReportSyncService service, {
    FakePostMatchReportStorage? withStorage,
  }) async {
    final c = PostMatchReportController(
      storage: withStorage ?? FakePostMatchReportStorage(),
      syncService: service,
    );
    await c.bootstrap();
    return c;
  }

  setUp(() async {
    sync = FakePostMatchReportSyncService();
    storage = FakePostMatchReportStorage();
    controller = await ready(sync, withStorage: storage);
  });

  tearDown(() => controller.dispose());

  group('bootstrap', () {
    test('is ready once local storage has loaded', () {
      expect(controller.isReady, isTrue);
      expect(controller.reports, isEmpty);
    });

    test('reportFor an unwritten match reads as empty, not null', () {
      final report = controller.reportFor('2026miket', 'qm14');

      expect(report.isEmpty, isTrue);
      expect(report.id, '2026miket_qm14');
    });
  });

  group('save', () {
    test('applies locally before the write lands', () async {
      final saving = controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'Scored two',
        teleop: 'Cycled steadily',
        endgame: 'Climbed',
        notes: 'Nothing broke',
      );

      final report = controller.reportFor('2026miket', 'qm14');
      expect(report.auto, 'Scored two');
      expect(report.teleop, 'Cycled steadily');
      expect(report.endgame, 'Climbed');
      expect(report.notes, 'Nothing broke');

      expect(await saving, isTrue);
    });

    test('writes every section together in one call', () async {
      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'Scored two',
        teleop: 'Cycled steadily',
        endgame: 'Climbed',
        notes: 'Nothing broke',
      );

      expect(sync.pushes, hasLength(1));
      final pushed = sync.pushes.single;
      expect(pushed.auto, 'Scored two');
      expect(pushed.teleop, 'Cycled steadily');
      expect(pushed.endgame, 'Climbed');
      expect(pushed.notes, 'Nothing broke');
    });

    test('lands on this device even with no sync service', () async {
      final c = PostMatchReportController(
        storage: FakePostMatchReportStorage(),
      );
      await c.bootstrap();

      final saved = await c.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'Scored two',
        teleop: '',
        endgame: '',
        notes: '',
      );

      expect(saved, isTrue);
      expect(c.reportFor('2026miket', 'qm14').auto, 'Scored two');
      c.dispose();
    });

    test('persists to local storage, not just memory', () async {
      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'Scored two',
        teleop: '',
        endgame: '',
        notes: '',
      );

      final reloaded = PostMatchReportController(storage: storage);
      await reloaded.bootstrap();

      expect(reloaded.reportFor('2026miket', 'qm14').auto, 'Scored two');
      reloaded.dispose();
    });

    test('records the author from the signed-in user', () async {
      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'Scored two',
        teleop: '',
        endgame: '',
        notes: '',
      );

      expect(sync.pushes.single.authorUid, 'uid-1');
      expect(sync.pushes.single.authorDisplayName, 'Lead');
    });

    test('editing a second match does not disturb the first', () async {
      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'first match',
        teleop: '',
        endgame: '',
        notes: '',
      );
      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm15',
        auto: 'second match',
        teleop: '',
        endgame: '',
        notes: '',
      );

      expect(controller.reportFor('2026miket', 'qm14').auto, 'first match');
      expect(controller.reportFor('2026miket', 'qm15').auto, 'second match');
      expect(controller.reports, hasLength(2));
    });

    test('a failed local save rolls back to the last confirmed value and marks the tracker', () async {
      expect(controller.failedWrites.hasFailures, isFalse);

      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'first save',
        teleop: '',
        endgame: '',
        notes: '',
      );

      storage.failNextSave = StateError('disk full');
      final saved = await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'edit that never lands',
        teleop: '',
        endgame: '',
        notes: '',
      );

      expect(saved, isFalse);
      expect(controller.failedWrites.hasFailures, isTrue);
      expect(controller.failedWrites.unlandedCount, 1);

      expect(controller.reportFor('2026miket', 'qm14').auto, 'first save');

      final secondSave = await controller.save(
        eventKey: '2026miket',
        matchId: 'qm15',
        auto: 'Scored two',
        teleop: '',
        endgame: '',
        notes: '',
      );

      expect(secondSave, isTrue);
      expect(controller.failedWrites.hasFailures, isFalse);
    });

    test(
      'a failed save on a report that never existed leaves nothing behind',
      () async {
        storage.failNextSave = StateError('disk full');

        final saved = await controller.save(
          eventKey: '2026miket',
          matchId: 'qm20',
          auto: 'edit that never lands',
          teleop: '',
          endgame: '',
          notes: '',
        );

        expect(saved, isFalse);
        expect(controller.reportFor('2026miket', 'qm20').isEmpty, isTrue);
        expect(controller.reports, isEmpty);
      },
    );
  });

  group('reportsForEvent', () {
    test('filters to one event, leaving other events out', () async {
      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'a',
        teleop: '',
        endgame: '',
        notes: '',
      );
      await controller.save(
        eventKey: '2026txhou',
        matchId: 'qm1',
        auto: 'b',
        teleop: '',
        endgame: '',
        notes: '',
      );

      final filtered = controller.reportsForEvent('2026miket');
      expect(filtered, hasLength(1));
      expect(filtered.single.matchId, 'qm14');
    });
  });

  group('write ordering', () {
    test('two quick saves land on local storage in the order made', () async {
      final laggyStorage = FakePostMatchReportStorage(delayFirst: true);
      final c = PostMatchReportController(
        storage: laggyStorage,
        syncService: FakePostMatchReportSyncService(),
      );
      await c.bootstrap();

      final first = c.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'first',
        teleop: '',
        endgame: '',
        notes: '',
      );
      final second = c.save(
        eventKey: '2026miket',
        matchId: 'qm15',
        auto: 'second',
        teleop: '',
        endgame: '',
        notes: '',
      );
      await Future.wait([first, second]);

      expect(laggyStorage.saved.map((r) => r.auto), ['first', 'second']);
      c.dispose();
    });
  });

  group('remote snapshots', () {
    test('a newer remote report replaces the local one', () async {
      sync.emitRemote([
        PostMatchReport(
          id: '2026miket_qm14',
          eventKey: '2026miket',
          matchId: 'qm14',
          auto: 'from another device',
          updatedAt: DateTime.utc(2026, 8, 16),
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.reportFor('2026miket', 'qm14').auto,
        'from another device',
      );
    });

    test(
      'a stale remote report does not overwrite a newer local edit',
      () async {
        await controller.save(
          eventKey: '2026miket',
          matchId: 'qm14',
          auto: 'local edit',
          teleop: '',
          endgame: '',
          notes: '',
        );

        sync.emitRemote([
          PostMatchReport(
            id: '2026miket_qm14',
            eventKey: '2026miket',
            matchId: 'qm14',
            auto: 'stale',
            updatedAt: DateTime.utc(2020, 1, 1),
          ),
        ]);
        await Future<void>.delayed(Duration.zero);

        expect(controller.reportFor('2026miket', 'qm14').auto, 'local edit');
      },
    );
  });
}
