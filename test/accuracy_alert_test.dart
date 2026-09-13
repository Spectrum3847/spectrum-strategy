import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/accuracy_alert.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';

import 'support/fake_accuracy_alert_service.dart';
import 'support/fake_scouting_storage.dart';

void main() {
  group('AccuracyAlert model', () {
    test('decodes a cron-written document', () {
      final alert = AccuracyAlert.fromJson(<String, dynamic>{
        'entryId': 'entry-1',
        'teamNumber': 3847,
        'tbaMatchKey': '2025flor_qm14',
        'authorUid': 'uid-1',
        'authorDisplayName': 'Jane',
        'flaggedFields': [
          {'fieldCode': 'auto_amp', 'scoutedValue': 3, 'officialValue': 0},
        ],
        'createdAt': '2025-04-05T10:00:00.000Z',
      });

      expect(alert.entryId, 'entry-1');
      expect(alert.teamNumber, 3847);
      expect(alert.tbaMatchKey, '2025flor_qm14');
      expect(alert.authorUid, 'uid-1');
      expect(alert.authorDisplayName, 'Jane');
      expect(alert.flaggedFields, hasLength(1));
      expect(alert.flaggedFields.first.fieldCode, 'auto_amp');
      expect(alert.flaggedFields.first.scoutedValue, 3);
      expect(alert.flaggedFields.first.officialValue, 0);
      expect(alert.createdAt, DateTime.utc(2025, 4, 5, 10, 0));
      expect(alert.updatedAt, alert.createdAt);
      expect(alert.acknowledged, isFalse);
    });

    test('fromJson handles missing fields gracefully', () {
      final alert = AccuracyAlert.fromJson(const <String, dynamic>{});
      expect(alert.entryId, '');
      expect(alert.teamNumber, 0);
      expect(alert.tbaMatchKey, '');
      expect(alert.flaggedFields, isEmpty);
      expect(alert.acknowledged, isFalse);
    });
  });

  group('ScoutEntry tbaMatchKey', () {
    test('round-trips through JSON', () {
      final entry = ScoutEntry(
        matchId: 'session-uuid',
        teamNumber: 3847,
        tbaMatchKey: '2025flor_qm14',
      );
      final round = ScoutEntry.fromJson(entry.toJson());
      expect(round.tbaMatchKey, '2025flor_qm14');
    });

    test('is null when not set', () {
      final entry = ScoutEntry(matchId: 'session-uuid', teamNumber: 3847);
      expect(entry.tbaMatchKey, isNull);
      final round = ScoutEntry.fromJson(entry.toJson());
      expect(round.tbaMatchKey, isNull);
    });

    test('copyWith preserves existing tbaMatchKey when not specified', () {
      final entry = ScoutEntry(
        matchId: 'm',
        teamNumber: 1,
        tbaMatchKey: '2025flor_qm1',
      );
      final updated = entry.copyWith(notes: 'updated');
      expect(updated.tbaMatchKey, '2025flor_qm1');
    });

    test('copyWith updates tbaMatchKey when specified', () {
      final entry = ScoutEntry(
        matchId: 'm',
        teamNumber: 1,
        tbaMatchKey: '2025flor_qm1',
      );
      final updated = entry.copyWith(tbaMatchKey: '2025flor_qm2');
      expect(updated.tbaMatchKey, '2025flor_qm2');
    });
  });

  group('ScoutingController with AccuracyAlertService', () {
    test('pendingAlerts returns empty list without alert service', () async {
      final controller = ScoutingController(storage: FakeScoutingStorage());
      await controller.bootstrap();
      expect(controller.pendingAlerts, isEmpty);
    });

    test('pendingAlerts reflects alerts from the service', () async {
      final alertService = FakeAccuracyAlertService();
      final controller = ScoutingController(
        storage: FakeScoutingStorage(),
        alertService: alertService,
      );
      await controller.bootstrap();

      expect(alertService.initializeCalls, 1);

      final alert = AccuracyAlert(
        entryId: 'entry-1',
        teamNumber: 3847,
        tbaMatchKey: '2025flor_qm1',
        authorUid: 'uid-1',
        flaggedFields: <FlaggedField>[
          const FlaggedField(
            fieldCode: 'auto_amp',
            scoutedValue: 3,
            officialValue: 0,
          ),
        ],
        createdAt: DateTime.now().toUtc(),
      );

      alertService.emitAlerts(<AccuracyAlert>[alert]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.pendingAlerts, hasLength(1));
      expect(controller.pendingAlerts.first.entryId, 'entry-1');
    });

    test('acknowledgeAlert delegates to the alert service', () async {
      final alertService = FakeAccuracyAlertService();
      final controller = ScoutingController(
        storage: FakeScoutingStorage(),
        alertService: alertService,
      );
      await controller.bootstrap();

      await controller.acknowledgeAlert('entry-1');
      expect(alertService.acknowledged, contains('entry-1'));
    });

    test(
      'pendingAlerts returns empty list when alert service has no alerts',
      () async {
        final alertService = FakeAccuracyAlertService();
        final controller = ScoutingController(
          storage: FakeScoutingStorage(),
          alertService: alertService,
        );
        await controller.bootstrap();
        expect(controller.pendingAlerts, isEmpty);
      },
    );
  });
}
