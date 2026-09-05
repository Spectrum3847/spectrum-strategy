import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/trex_trait.dart';
import 'package:spectrumstrategy/src/models/trex_trait_report.dart';
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

void main() {
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
  });
}
