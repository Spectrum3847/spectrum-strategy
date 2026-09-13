import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:spectrumstrategy/src/models/trex_trait.dart';
import 'package:spectrumstrategy/src/models/trex_trait_report.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/trex_trait_report_controller.dart';

import 'support/fake_trex_trait_report_storage.dart';
import 'support/fake_trex_trait_report_sync_service.dart';

TrexTraitReport _report({
  String? id,
  int teamNumber = 254,
  String trait = 'autonomous',
}) => TrexTraitReport(
  id: id,
  trait: trait,
  teamNumber: teamNumber,
  matchNumber: 1,
  report: 'Fast auton to the depot bump.',
  updatedAt: DateTime.utc(2026, 8, 1),
);

Future<EventController> _eventControllerWithKey(String eventKey) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'selected_event_key': eventKey,
  });
  final controller = EventController(
    client: StatboticsClient(
      httpClient: MockClient((_) async => http.Response('down', 503)),
      sleep: (_) async {},
    ),
  );
  await controller.bootstrap();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrexTraitReportController', () {
    test('bootstrap loads reports already on disk', () async {
      final storage = FakeTrexTraitReportStorage();
      await storage.saveReport(_report(id: 'r1'));
      final controller = TrexTraitReportController(storage: storage);

      await controller.bootstrap();

      expect(controller.isReady, isTrue);
      expect(controller.reports, hasLength(1));
      expect(controller.reports.single.id, 'r1');
    });

    test('submitReport saves locally and pushes to the sync service', () async {
      final storage = FakeTrexTraitReportStorage();
      final sync = FakeTrexTraitReportSyncService();
      final controller = TrexTraitReportController(
        storage: storage,
        syncService: sync,
      );
      await controller.bootstrap();

      final saved = await controller.submitReport(_report(id: 'r1'));

      expect(saved, isTrue);
      expect(controller.reports, hasLength(1));
      expect(storage.rawReports.keys, contains('r1'));
      expect(sync.pushed.map((r) => r.id), contains('r1'));
    });

    test(
      'a failed local save rolls the report back and tracks the failure',
      () async {
        final storage = FakeTrexTraitReportStorage();
        final controller = TrexTraitReportController(storage: storage);
        await controller.bootstrap();
        storage.failNextSave = true;

        final saved = await controller.submitReport(_report(id: 'r1'));

        expect(saved, isFalse);
        expect(controller.reports, isEmpty);
        expect(controller.lastError, isNotNull);
        expect(controller.failedWrites.hasFailures, isTrue);
      },
    );

    test('submitReport stamps the signed-in uid and display name', () async {
      final storage = FakeTrexTraitReportStorage();
      final sync = FakeTrexTraitReportSyncService(
        currentUserUid: 'uid-me',
        currentUserDisplayName: 'Scout',
      );
      final controller = TrexTraitReportController(
        storage: storage,
        syncService: sync,
      );
      await controller.bootstrap();

      await controller.submitReport(_report(id: 'r1'));

      final saved = controller.reports.single;
      expect(saved.authorUid, 'uid-me');
      expect(saved.authorDisplayName, 'Scout');
    });

    test('submitReport stamps the active event key', () async {
      final storage = FakeTrexTraitReportStorage();
      final eventController = await _eventControllerWithKey('2026miket');
      final controller = TrexTraitReportController(
        storage: storage,
        eventController: eventController,
      );
      await controller.bootstrap();

      await controller.submitReport(_report(id: 'r1'));

      expect(controller.reports.single.eventKey, '2026miket');
    });

    test(
      'submitReport with no event selected saves with an empty event key',
      () async {
        final storage = FakeTrexTraitReportStorage();
        final eventController = await _eventControllerWithKey('');
        final controller = TrexTraitReportController(
          storage: storage,
          eventController: eventController,
        );
        await controller.bootstrap();

        await controller.submitReport(_report(id: 'r1'));

        expect(controller.reports.single.eventKey, isEmpty);
      },
    );

    test(
      "submitReport keeps a report's own event key over the active event",
      () async {
        final storage = FakeTrexTraitReportStorage();
        final eventController = await _eventControllerWithKey('2026miket');
        final controller = TrexTraitReportController(
          storage: storage,
          eventController: eventController,
        );
        await controller.bootstrap();
        final report = _report(id: 'r1').copyWith(eventKey: '2026txhou');

        await controller.submitReport(report);

        expect(controller.reports.single.eventKey, '2026txhou');
      },
    );

    test(
      'submitReport with nobody signed in saves with empty author fields',
      () async {
        final storage = FakeTrexTraitReportStorage();
        final sync = FakeTrexTraitReportSyncService();
        final controller = TrexTraitReportController(
          storage: storage,
          syncService: sync,
        );
        await controller.bootstrap();

        final saved = await controller.submitReport(_report(id: 'r1'));

        expect(saved, isTrue);
        final report = controller.reports.single;
        expect(report.authorUid, isEmpty);
        expect(report.authorDisplayName, isEmpty);
      },
    );

    test('a remote report merges in and is grouped by team', () async {
      final storage = FakeTrexTraitReportStorage();
      final sync = FakeTrexTraitReportSyncService();
      final controller = TrexTraitReportController(
        storage: storage,
        syncService: sync,
      );
      await controller.bootstrap();

      sync.emitRemote([
        _report(id: 'remote-1', teamNumber: 254, trait: TrexTrait.defense.key),
        _report(
          id: 'remote-2',
          teamNumber: 118,
          trait: TrexTrait.fuelScoring.key,
        ),
      ]);

      await Future<void>.delayed(Duration.zero);
      await controller.saveNow();

      expect(controller.reportsForTeam(254), hasLength(1));
      expect(controller.reportsForTeam(118), hasLength(1));
      expect(controller.reportsForTeam(999), isEmpty);

      expect(storage.rawReports.keys, containsAll(['remote-1', 'remote-2']));
    });

    test(
      'a synced report that drops out of a later remote snapshot is removed',
      () async {
        final storage = FakeTrexTraitReportStorage();
        final sync = FakeTrexTraitReportSyncService();
        final controller = TrexTraitReportController(
          storage: storage,
          syncService: sync,
        );
        await controller.bootstrap();

        sync.emitRemote([_report(id: 'remote-1', teamNumber: 254)]);
        await Future<void>.delayed(Duration.zero);
        await controller.saveNow();
        expect(controller.reports, hasLength(1));

        sync.emitRemote(const <TrexTraitReport>[]);
        await Future<void>.delayed(Duration.zero);
        await controller.saveNow();

        expect(controller.reports, isEmpty);
        expect(storage.rawReports.keys, isNot(contains('remote-1')));
      },
    );

    test(
      'a local-only report survives a remote snapshot that lacks it',
      () async {
        final storage = FakeTrexTraitReportStorage();
        final sync = FakeTrexTraitReportSyncService();
        final controller = TrexTraitReportController(
          storage: storage,
          syncService: sync,
        );
        await controller.bootstrap();
        await controller.submitReport(_report(id: 'local-1'));

        sync.emitRemote(const <TrexTraitReport>[]);
        await Future<void>.delayed(Duration.zero);
        await controller.saveNow();

        expect(controller.reports, hasLength(1));
        expect(controller.reports.single.id, 'local-1');
      },
    );

    test('an older remote report does not clobber a newer local one', () async {
      final storage = FakeTrexTraitReportStorage();
      final sync = FakeTrexTraitReportSyncService();
      final controller = TrexTraitReportController(
        storage: storage,
        syncService: sync,
      );
      await controller.bootstrap();
      final newer = TrexTraitReport(
        id: 'r1',
        trait: 'autonomous',
        teamNumber: 254,
        matchNumber: 1,
        report: 'Newer write-up.',
        updatedAt: DateTime.utc(2026, 8, 2),
      );
      await controller.submitReport(newer);

      final stale = TrexTraitReport(
        id: 'r1',
        trait: 'autonomous',
        teamNumber: 254,
        matchNumber: 1,
        report: 'Stale write-up.',
        updatedAt: DateTime.utc(2026, 8, 1),
      );
      sync.emitRemote([stale]);
      await Future<void>.delayed(Duration.zero);
      await controller.saveNow();

      expect(controller.reports.single.report, 'Newer write-up.');
    });

    test('deleteReport removes locally and pushes the delete', () async {
      final storage = FakeTrexTraitReportStorage();
      final sync = FakeTrexTraitReportSyncService();
      final controller = TrexTraitReportController(
        storage: storage,
        syncService: sync,
      );
      await controller.bootstrap();
      await controller.submitReport(_report(id: 'r1'));

      final deleted = await controller.deleteReport('r1');

      expect(deleted, isTrue);
      expect(controller.reports, isEmpty);
      expect(storage.rawReports.keys, isNot(contains('r1')));
      expect(sync.deleted.map((r) => r.id), contains('r1'));
    });

    test('deleteReport for an id already gone counts as deleted', () async {
      final controller = TrexTraitReportController(
        storage: FakeTrexTraitReportStorage(),
      );
      await controller.bootstrap();

      final deleted = await controller.deleteReport('missing');

      expect(deleted, isTrue);
    });

    test(
      'a failed local delete rolls the report back and tracks the failure',
      () async {
        final storage = FakeTrexTraitReportStorage();
        final controller = TrexTraitReportController(storage: storage);
        await controller.bootstrap();
        await controller.submitReport(_report(id: 'r1'));
        storage.failNextDelete = true;

        final deleted = await controller.deleteReport('r1');

        expect(deleted, isFalse);
        expect(controller.reports, hasLength(1));
        expect(controller.lastError, isNotNull);
        expect(controller.failedWrites.hasFailures, isTrue);
      },
    );
  });
}
