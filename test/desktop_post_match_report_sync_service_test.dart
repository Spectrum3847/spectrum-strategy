import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumstrategy/src/models/post_match_report.dart';
import 'package:spectrumstrategy/src/services/desktop_post_match_report_sync_service.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

import 'support/fake_pending_push_queue.dart';
import 'support/fake_spectrum_auth_service.dart';

fc.Firestore _firestore(MockClient client) => fc.Firestore(
  projectId: 'demo',
  idTokenProvider: () async => 'tok',
  httpClient: client,
);

FakeSpectrumAuthService _signedInAuth() => FakeSpectrumAuthService(
  initialUser: const SpectrumUser(uid: 'uid-1', displayName: 'Dana'),
);

String _doc(String id, PostMatchReport report, {DateTime? serverTs}) =>
    jsonEncode({
      'name':
          'projects/demo/databases/(default)/documents/postMatchReports/$id',
      'fields': fc.FirestoreValueCodec.encodeFields(<String, dynamic>{
        ...report.toJson(),
        'updatedAtTs': ?serverTs,
      }),
    });

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  final report = PostMatchReport(
    id: 'r1',
    eventKey: '2026txhou',
    matchId: 'qm1',
    updatedAt: DateTime.utc(2026, 7, 8, 12),
  );

  test(
    'the first poll fetches the whole collection; the next polls delta',
    () async {
      final fields = <String>[];
      final service = DesktopPostMatchReportSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.url.path.endsWith(':runQuery')) {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              final where = ((body['structuredQuery'] as Map)['where'] as Map)
                  .cast<String, dynamic>();
              final filter = (where['fieldFilter'] as Map)
                  .cast<String, dynamic>();
              fields.add((filter['field'] as Map)['fieldPath'] as String);
              return http.Response(jsonEncode(<dynamic>[]), 200);
            }
            fields.add('(listDocuments)');
            return http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc('r1', report, serverTs: report.updatedAt)),
                ],
              }),
              200,
            );
          }),
        ),
        pollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(service.dispose);

      await service.initialize();
      await _waitUntil(() => fields.length >= 2);

      expect(fields.first, '(listDocuments)');
      expect(fields.skip(1).take(3), everyElement('updatedAtTs'));
    },
  );

  test('a full collection fetch recurs, so a document the cursor passed is not '
      'lost until the app restarts', () async {
    final fields = <String>[];
    final service = DesktopPostMatchReportSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          if (request.url.path.endsWith(':runQuery')) {
            fields.add('delta');
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }
          fields.add('full');
          return http.Response(
            jsonEncode({
              'documents': [
                jsonDecode(_doc('r1', report, serverTs: report.updatedAt)),
              ],
            }),
            200,
          );
        }),
      ),
      pollInterval: const Duration(milliseconds: 5),
    );
    addTearDown(service.dispose);

    await service.initialize();
    await _waitUntil(
      () => fields.where((f) => f == 'full').length >= 2,
      timeout: const Duration(seconds: 5),
    );

    expect(
      fields.where((f) => f == 'full').length,
      greaterThanOrEqualTo(2),
      reason: 'the full fetch must recur, not just happen once at startup',
    );

    expect(fields.where((f) => f == 'delta').length, greaterThan(4));
  });

  test('a push advances the cursor immediately, before any poll', () async {
    var sawRunQuery = false;
    final service = DesktopPostMatchReportSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          if (request.url.path.endsWith(':runQuery')) {
            sawRunQuery = true;
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }
          return http.Response(
            _doc('r1', report, serverTs: report.updatedAt),
            200,
          );
        }),
      ),
      pendingPushQueue: FakePendingPushQueue(),
      pollInterval: const Duration(milliseconds: 10),
    );
    addTearDown(service.dispose);

    await service.push(report);
    await service.initialize();
    await _waitUntil(() => sawRunQuery);

    expect(sawRunQuery, isTrue);
  });

  test(
    'a delta poll emits only what changed -- no cache to merge into',
    () async {
      final other = PostMatchReport(
        id: 'r2',
        eventKey: report.eventKey,
        matchId: 'qm2',
        updatedAt: DateTime.utc(2026, 7, 9),
      );
      var calls = 0;
      final service = DesktopPostMatchReportSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((_) async {
            calls++;
            if (calls == 1) {
              return http.Response(
                jsonEncode({
                  'documents': [
                    jsonDecode(_doc('r1', report, serverTs: report.updatedAt)),
                  ],
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode([
                {
                  'document': jsonDecode(
                    _doc('r2', other, serverTs: other.updatedAt),
                  ),
                },
              ]),
              200,
            );
          }),
        ),
        pollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(service.dispose);

      final snapshots = <List<PostMatchReport>>[];
      service.remoteReportsStream.listen(snapshots.add);
      await service.initialize();
      await _waitUntil(() => snapshots.length >= 2);

      expect(snapshots[0].map((r) => r.id), ['r1']);
      expect(snapshots[1].map((r) => r.id), ['r2']);
    },
  );

  test(
    'a document with no server timestamp cannot advance the cursor',
    () async {
      final docA = report.copyWith(updatedAt: DateTime.utc(2026, 7, 1));
      final docB = report.copyWith(updatedAt: DateTime.utc(2099, 1, 1));
      DateTime? capturedFilterValue;
      var calls = 0;
      final service = DesktopPostMatchReportSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            calls++;
            if (calls == 1) {
              return http.Response(
                jsonEncode({
                  'documents': [
                    jsonDecode(_doc('a', docA, serverTs: docA.updatedAt)),

                    jsonDecode(_doc('b', docB)),
                  ],
                }),
                200,
              );
            }
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final where = ((body['structuredQuery'] as Map)['where'] as Map)
                .cast<String, dynamic>();
            final filter = (where['fieldFilter'] as Map)
                .cast<String, dynamic>();
            capturedFilterValue ??= DateTime.parse(
              (filter['value'] as Map)['timestampValue'] as String,
            );
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
        pollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(service.dispose);

      await service.initialize();
      await _waitUntil(() => capturedFilterValue != null);

      expect(
        capturedFilterValue!.isBefore(DateTime.utc(2027)),
        isTrue,
        reason: 'the cursor must not have been pushed to 2099 by docB',
      );
    },
  );
}
