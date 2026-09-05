import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumstrategy/src/models/trex_trait_report.dart';
import 'package:spectrumstrategy/src/services/desktop_trex_trait_report_sync_service.dart';
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

String _doc(TrexTraitReport report, {DateTime? serverTs}) => jsonEncode({
  'name':
      'projects/demo/databases/(default)/documents/trexTraitReports/'
      '${report.id}',
  'fields': fc.FirestoreValueCodec.encodeFields(<String, dynamic>{
    ...report.toJson(),
    'updatedAtTs': ?serverTs,
  }),
});

void main() {
  final report = TrexTraitReport(
    id: 't1',
    trait: 'defense',
    teamNumber: 3847,
    matchNumber: 1,
    updatedAt: DateTime.utc(2026, 7, 8, 12),
  );

  test(
    'the second poll queries updatedAtTs from the first poll\'s cursor',
    () async {
      final fields = <String>[];
      final service = DesktopTrexTraitReportSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.url.path.endsWith(':runQuery')) {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              final where = body['structuredQuery'] as Map?;
              if (where == null || !where.containsKey('where')) {
                fields.add('(unfiltered runQuery)');
                return http.Response(jsonEncode(<dynamic>[]), 200);
              }
              final filter = ((where['where'] as Map)['fieldFilter'] as Map)
                  .cast<String, dynamic>();
              fields.add((filter['field'] as Map)['fieldPath'] as String);
              return http.Response(jsonEncode(<dynamic>[]), 200);
            }
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
      );

      await service.syncNow();
      await service.syncNow();

      expect(fields, ['(unfiltered runQuery)', 'updatedAtTs']);
    },
  );

  test('the unfiltered fetch recurs periodically, so a document behind the '
      'cursor is not lost until the app restarts', () async {
    final kinds = <String>[];
    final service = DesktopTrexTraitReportSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final query = body['structuredQuery'] as Map?;
          kinds.add(
            query != null && query.containsKey('where') ? 'delta' : 'full',
          );
          return http.Response(jsonEncode(<dynamic>[]), 200);
        }),
      ),
    );

    for (var i = 0; i < 12; i++) {
      await service.syncNow();
    }

    expect(
      kinds.where((k) => k == 'full').length,
      greaterThanOrEqualTo(2),
      reason: 'the unfiltered fetch must recur, not only run at startup',
    );
    expect(kinds.where((k) => k == 'delta').length, greaterThan(4));
  });

  test(
    'a delta poll emits only what changed -- no cache to merge into',
    () async {
      final other = TrexTraitReport(
        id: 't2',
        trait: 'defense',
        teamNumber: 118,
        matchNumber: 2,
        updatedAt: DateTime.utc(2026, 7, 9),
      );
      var calls = 0;
      final service = DesktopTrexTraitReportSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((_) async {
            calls++;
            if (calls == 1) {
              return http.Response(
                jsonEncode([
                  {
                    'document': jsonDecode(
                      _doc(report, serverTs: report.updatedAt),
                    ),
                  },
                ]),
                200,
              );
            }
            return http.Response(
              jsonEncode([
                {
                  'document': jsonDecode(
                    _doc(other, serverTs: other.updatedAt),
                  ),
                },
              ]),
              200,
            );
          }),
        ),
      );

      final snapshots = <List<TrexTraitReport>>[];
      final sub = service.remoteReportsStream.listen(snapshots.add);
      await service.syncNow();
      await service.syncNow();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots[0].map((r) => r.id), ['t1']);
      expect(snapshots[1].map((r) => r.id), ['t2']);
    },
  );

  test('a push advances the cursor immediately, before any poll', () async {
    var sawFilteredRunQuery = false;
    final service = DesktopTrexTraitReportSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          if (request.url.path.endsWith(':runQuery')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if ((body['structuredQuery'] as Map).containsKey('where')) {
              sawFilteredRunQuery = true;
            }
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }
          return http.Response(_doc(report, serverTs: report.updatedAt), 200);
        }),
      ),
      pendingPushQueue: FakePendingPushQueue(),
    );

    await service.push(report);
    await service.syncNow();

    expect(sawFilteredRunQuery, isTrue);
  });

  test(
    'a document with no server timestamp cannot advance the cursor',
    () async {
      final docA = TrexTraitReport(
        id: 'a',
        trait: 'defense',
        teamNumber: 1,
        matchNumber: 1,
        updatedAt: DateTime.utc(2026, 7, 1),
      );
      final docB = TrexTraitReport(
        id: 'b',
        trait: 'defense',
        teamNumber: 2,
        matchNumber: 2,
        updatedAt: DateTime.utc(2099, 1, 1),
      );
      DateTime? capturedFilterValue;
      var calls = 0;
      final service = DesktopTrexTraitReportSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            calls++;
            if (calls == 1) {
              return http.Response(
                jsonEncode([
                  {
                    'document': jsonDecode(
                      _doc(docA, serverTs: docA.updatedAt),
                    ),
                  },

                  {'document': jsonDecode(_doc(docB))},
                ]),
                200,
              );
            }
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final filter =
                ((body['structuredQuery'] as Map)['where']
                        as Map)['fieldFilter']
                    as Map;
            capturedFilterValue ??= DateTime.parse(
              (filter['value'] as Map)['timestampValue'] as String,
            );
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
      );

      await service.syncNow();
      await service.syncNow();

      expect(
        capturedFilterValue!.isBefore(DateTime.utc(2027)),
        isTrue,
        reason: 'the cursor must not have been pushed to 2099 by docB',
      );
    },
  );
}
