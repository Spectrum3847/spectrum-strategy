import 'dart:async';
import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_assignment.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_scout_assignment_sync_service.dart';
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

String _doc(ScoutAssignment assignment, {DateTime? serverTs}) => jsonEncode({
  'name':
      'projects/demo/databases/(default)/documents/scoutAssignments/'
      '${assignment.id}',
  'fields': fc.FirestoreValueCodec.encodeFields(<String, dynamic>{
    ...assignment.toJson(),
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
  final assignment = ScoutAssignment(
    id: 'qm1__red1',
    matchKey: 'qm1',
    matchNumber: 1,
    station: 'red1',
    scouterUid: 'u1',
    scouterName: 'One',
    updatedAt: DateTime.utc(2026, 7, 8),
  );

  test(
    'the second poll queries updatedAtTs, not the whole collection',
    () async {
      final fields = <String>[];
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      final service = DesktopScoutAssignmentSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final query = body['structuredQuery'] as Map;
            if (!query.containsKey('where')) {
              fields.add('(unfiltered)');
              return http.Response(jsonEncode(<dynamic>[]), 200);
            }
            final filter = ((query['where'] as Map)['fieldFilter'] as Map)
                .cast<String, dynamic>();
            fields.add((filter['field'] as Map)['fieldPath'] as String);
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
        pollInterval: const Duration(milliseconds: 10),
        pendingPushQueue: FakePendingPushQueue(),
      );
      addTearDown(service.dispose);

      service.watchAll().listen((_) {});
      await _waitUntil(() => fields.length >= 2);

      expect(fields.first, '(unfiltered)');
      expect(fields.skip(1), everyElement('updatedAtTs'));
    },
  );

  test(
    'a delta poll merges into the cache instead of replacing the snapshot',
    () async {
      final second = ScoutAssignment(
        id: 'qm2__red1',
        matchKey: 'qm2',
        matchNumber: 2,
        station: 'red1',
        scouterUid: 'u2',
        scouterName: 'Two',
        updatedAt: DateTime.utc(2026, 7, 9),
      );
      var calls = 0;
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      final service = DesktopScoutAssignmentSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((_) async {
            calls++;
            if (calls == 1) {
              return http.Response(
                jsonEncode([
                  {
                    'document': jsonDecode(
                      _doc(assignment, serverTs: assignment.updatedAt),
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
                    _doc(second, serverTs: second.updatedAt),
                  ),
                },
              ]),
              200,
            );
          }),
        ),
        pollInterval: const Duration(milliseconds: 10),
        pendingPushQueue: FakePendingPushQueue(),
      );
      addTearDown(service.dispose);

      final snapshots = <List<ScoutAssignment>>[];
      service.watchAll().listen(snapshots.add);
      await _waitUntil(() => snapshots.length >= 2);

      expect(snapshots.first.map((a) => a.id), ['qm1__red1']);

      expect(snapshots.last.map((a) => a.id).toSet(), {
        'qm1__red1',
        'qm2__red1',
      });
    },
  );

  test(
    'every tenth poll re-fetches the collection to catch remote deletes',
    () async {
      final fields = <String>[];
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      final service = DesktopScoutAssignmentSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final query = body['structuredQuery'] as Map;
            fields.add(query.containsKey('where') ? 'delta' : 'full');
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
        pollInterval: const Duration(milliseconds: 10),
        pendingPushQueue: FakePendingPushQueue(),
      );
      addTearDown(service.dispose);

      service.watchAll().listen((_) {});
      await _waitUntil(
        () => fields.length >= 21,
        timeout: const Duration(seconds: 10),
      );

      for (var i = 0; i < 21; i++) {
        final expected = (i == 0 || i == 10 || i == 20) ? 'full' : 'delta';
        expect(fields[i], expected, reason: 'poll ${i + 1}');
      }
    },
  );

  test(
    'a local delete evicts the cache so a stale delta cannot resurrect it',
    () async {
      var calls = 0;
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      final service = DesktopScoutAssignmentSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'DELETE') return http.Response('{}', 200);
            calls++;
            if (calls == 1) {
              return http.Response(
                jsonEncode([
                  {
                    'document': jsonDecode(
                      _doc(assignment, serverTs: assignment.updatedAt),
                    ),
                  },
                ]),
                200,
              );
            }
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),

        pollInterval: const Duration(seconds: 30),
        pendingPushQueue: FakePendingPushQueue(),
      );
      addTearDown(service.dispose);

      final snapshots = <List<ScoutAssignment>>[];
      service.watchAll().listen(snapshots.add);
      await _waitUntil(() => snapshots.isNotEmpty);
      expect(snapshots.single.single.id, 'qm1__red1');

      await service.delete('qm1__red1');
      await _waitUntil(() => snapshots.length >= 2);

      expect(snapshots.last, isEmpty);
    },
  );

  test(
    'a delete during a poll fetch is not resurrected by that poll (#1511)',
    () async {
      final gate = Completer<void>();
      var calls = 0;
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      final service = DesktopScoutAssignmentSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'DELETE') return http.Response('{}', 200);
            if (request.method == 'PATCH') {
              return http.Response(
                _doc(assignment, serverTs: assignment.updatedAt),
                200,
              );
            }
            calls++;
            await gate.future;

            return http.Response(
              jsonEncode([
                {
                  'document': jsonDecode(
                    _doc(assignment, serverTs: assignment.updatedAt),
                  ),
                },
              ]),
              200,
            );
          }),
        ),
        pollInterval: const Duration(seconds: 30),
        pendingPushQueue: FakePendingPushQueue(),
      );
      addTearDown(service.dispose);

      await service.upsert(assignment);

      final snapshots = <List<ScoutAssignment>>[];
      service.watchAll().listen(snapshots.add);

      await _waitUntil(() => calls >= 1);

      await service.delete('qm1__red1');
      await _waitUntil(() => snapshots.isNotEmpty);

      expect(snapshots.last, isEmpty);

      gate.complete();
      await _waitUntil(() => snapshots.length >= 2);

      expect(snapshots.last, isEmpty);
    },
  );

  test(
    'an upsert during a full-sync fetch is not discarded by that poll (#1511)',
    () async {
      final gate = Completer<void>();
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      final service = DesktopScoutAssignmentSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'PATCH') {
              return http.Response(
                _doc(assignment, serverTs: assignment.updatedAt),
                200,
              );
            }

            await gate.future;

            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
        pollInterval: const Duration(seconds: 30),
        pendingPushQueue: FakePendingPushQueue(),
      );
      addTearDown(service.dispose);

      final snapshots = <List<ScoutAssignment>>[];
      service.watchAll().listen(snapshots.add);
      await Future<void>.delayed(Duration.zero);
      await service.upsert(assignment);
      gate.complete();
      await _waitUntil(() => snapshots.isNotEmpty);

      expect(snapshots.last.map((a) => a.id), ['qm1__red1']);
    },
  );

  test(
    'a document with no server timestamp cannot advance the cursor',
    () async {
      final docA = ScoutAssignment(
        id: 'a',
        matchKey: 'qm1',
        matchNumber: 1,
        station: 'red1',
        scouterUid: 'u1',
        scouterName: 'One',
        updatedAt: DateTime.utc(2026, 7, 1),
      );
      final docB = ScoutAssignment(
        id: 'b',
        matchKey: 'qm2',
        matchNumber: 2,
        station: 'red2',
        scouterUid: 'u2',
        scouterName: 'Two',
        updatedAt: DateTime.utc(2099, 1, 1),
      );
      DateTime? capturedFilterValue;
      var calls = 0;
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      final service = DesktopScoutAssignmentSyncService(
        authService: auth,
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
        pollInterval: const Duration(milliseconds: 10),
        pendingPushQueue: FakePendingPushQueue(),
      );
      addTearDown(service.dispose);

      service.watchAll().listen((_) {});
      await _waitUntil(() => capturedFilterValue != null);

      expect(
        capturedFilterValue!.isBefore(DateTime.utc(2027)),
        isTrue,
        reason: 'the cursor must not have been pushed to 2099 by docB',
      );
    },
  );
}
