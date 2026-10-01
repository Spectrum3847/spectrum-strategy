import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/post_match_report.dart';
import 'package:spectrumstrategy/src/services/post_match_report_sync_service.dart';
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

  group('rejected vs offline sync', () {
    test('a push the server rejects reports rejected, not offline', () async {
      sync.simulateRejection = true;
      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'a',
        teleop: '',
        endgame: '',
        notes: '',
      );
      await Future<void>.delayed(Duration.zero);

      expect(sync.pushes, isEmpty);
      expect(controller.syncStatus.state, PostMatchReportSyncState.rejected);
    });

    test('a 401-shaped failure still reports offline, not rejected', () async {
      sync.simulateOutage = true;
      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'a',
        teleop: '',
        endgame: '',
        notes: '',
      );
      await Future<void>.delayed(Duration.zero);

      expect(sync.pushes, isEmpty);
      expect(controller.syncStatus.state, PostMatchReportSyncState.offline);
    });

    test('a denied read reports noAccess', () async {
      sync.emitStatus(
        const PostMatchReportSyncStatus(
          state: PostMatchReportSyncState.noAccess,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.syncStatus.state, PostMatchReportSyncState.noAccess);
    });

    test('a rejected report stops being retried once _repushUnsynced has seen '
        'the rejection, and resumes only on a direct edit', () async {
      sync.simulateRejection = true;
      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'a',
        teleop: '',
        endgame: '',
        notes: '',
      );
      await Future<void>.delayed(Duration.zero);
      expect(sync.pushes, isEmpty);

      sync.emitStatus(
        const PostMatchReportSyncStatus(
          state: PostMatchReportSyncState.offline,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      sync.emitStatus(
        const PostMatchReportSyncStatus(state: PostMatchReportSyncState.synced),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sync.pushes, isEmpty);

      sync.simulateRejection = false;
      sync.emitStatus(
        const PostMatchReportSyncStatus(
          state: PostMatchReportSyncState.offline,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      sync.emitStatus(
        const PostMatchReportSyncStatus(state: PostMatchReportSyncState.synced),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sync.pushes, isEmpty);

      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'edited',
        teleop: '',
        endgame: '',
        notes: '',
      );
      await Future<void>.delayed(Duration.zero);
      expect(sync.pushes, hasLength(1));
    });
  });

  group('persisted pending report ids', () {
    test('a report confirmed by a remote snapshot is not re-pushed on the '
        'next repush pass', () async {
      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'a',
        teleop: '',
        endgame: '',
        notes: '',
      );
      await Future<void>.delayed(Duration.zero);
      expect(sync.pushes, hasLength(1));

      sync.emitRemote([
        PostMatchReport(
          id: '2026miket_qm14',
          eventKey: '2026miket',
          matchId: 'qm14',
          auto: 'a',
          updatedAt: sync.pushes.single.updatedAt,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      sync.pushes.clear();

      sync.emitStatus(
        const PostMatchReportSyncStatus(
          state: PostMatchReportSyncState.offline,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      sync.emitStatus(
        const PostMatchReportSyncStatus(state: PostMatchReportSyncState.synced),
      );
      await Future<void>.delayed(Duration.zero);

      expect(sync.pushes, isEmpty);
    });

    test('bootstrap with an existing local report and no persisted pending '
        'state pushes nothing', () async {
      final freshStorage = FakePostMatchReportStorage();
      await freshStorage.saveReport(
        PostMatchReport(
          id: '2026miket_qm1',
          eventKey: '2026miket',
          matchId: 'qm1',
          auto: 'already on disk',
          updatedAt: DateTime.utc(2026, 6, 1),
        ),
      );
      final freshSync = FakePostMatchReportSyncService();
      final freshController = await ready(freshSync, withStorage: freshStorage);
      await Future<void>.delayed(Duration.zero);

      expect(freshSync.pushes, isEmpty);
      addTearDown(freshController.dispose);
    });

    test('a report pending from a failed push is retried after relaunch, '
        'and a report nobody edited is not', () async {
      final sharedStorage = FakePostMatchReportStorage();

      await sharedStorage.saveReport(
        PostMatchReport(
          id: '2026miket_qm1',
          eventKey: '2026miket',
          matchId: 'qm1',
          auto: 'untouched',
          updatedAt: DateTime.utc(2026, 6, 1),
        ),
      );

      final firstSync = FakePostMatchReportSyncService()..simulateOutage = true;
      final firstController = await ready(
        firstSync,
        withStorage: sharedStorage,
      );
      await firstController.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'pending edit',
        teleop: '',
        endgame: '',
        notes: '',
      );
      await Future<void>.delayed(Duration.zero);
      expect(firstSync.pushes, isEmpty);
      firstController.dispose();

      final relaunchSync = FakePostMatchReportSyncService();
      final relaunched = await ready(relaunchSync, withStorage: sharedStorage);
      await Future<void>.delayed(Duration.zero);

      expect(relaunchSync.pushes.map((r) => r.id), contains('2026miket_qm14'));
      expect(
        relaunchSync.pushes.map((r) => r.id),
        isNot(contains('2026miket_qm1')),
      );
      addTearDown(relaunched.dispose);
    });
  });
}
