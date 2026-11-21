import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumstrategy/src/services/desktop_usage_rollup_service.dart';
import 'package:spectrumstrategy/src/services/usage_rollup_service.dart';

fc.Firestore _firestore(MockClient client) => fc.Firestore(
  projectId: 'demo',
  idTokenProvider: () async => 'tok',
  httpClient: client,
);

String _rollupDoc() => jsonEncode({
  'name': 'projects/demo/databases/(default)/documents/telemetryRollup/current',
  'fields': fc.FirestoreValueCodec.encodeFields(<String, dynamic>{
    'updatedAt': '2026-08-16T06:25:00Z',
    'windowDays': 30,
    'eventsCounted': 12,
    'deviceCount': 3,
    'tabs': [
      {'name': 'Scout', 'count': 7},
    ],
  }),
});

void main() {
  group('DesktopUsageRollupService', () {
    test('reads the rollup document', () async {
      String? path;
      final service = DesktopUsageRollupService(
        firestore: _firestore(
          MockClient((request) async {
            path = request.url.path;
            return http.Response(_rollupDoc(), 200);
          }),
        ),
      );

      final rollup = await service.fetch();

      expect(path, endsWith('/telemetryRollup/current'));
      expect(rollup.eventsCounted, 12);
      expect(rollup.deviceCount, 3);
    });

    test('a missing document says the daily job has not run', () async {
      final service = DesktopUsageRollupService(
        firestore: _firestore(
          MockClient((_) async => http.Response('not found', 404)),
        ),
      );

      await expectLater(
        service.fetch(),
        throwsA(
          isA<UsageRollupUnavailable>().having(
            (e) => e.message,
            'message',
            usageRollupMissing,
          ),
        ),
      );
    });

    test('a refused read says the tab is for developers', () async {
      final service = DesktopUsageRollupService(
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': {
                  'code': 403,
                  'status': 'PERMISSION_DENIED',
                  'message': 'denied',
                },
              }),
              403,
            ),
          ),
        ),
      );

      await expectLater(
        service.fetch(),
        throwsA(
          isA<UsageRollupUnavailable>().having(
            (e) => e.message,
            'message',
            usageRollupDenied,
          ),
        ),
      );
    });
  });

  group('usageRollupServiceFor', () {
    test('uses REST where a REST client exists, FlutterFire otherwise', () {
      final rest = _firestore(MockClient((_) async => http.Response('', 200)));

      expect(
        usageRollupServiceFor(rest: rest),
        isA<DesktopUsageRollupService>(),
      );
      expect(usageRollupServiceFor(), isA<FirestoreUsageRollupService>());
    });
  });
}
