import 'dart:async';
import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_sync_service.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

import 'support/fake_pending_push_queue.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_spectrum_auth_service.dart';

fc.Firestore _firestore(MockClient client) => fc.Firestore(
  projectId: 'demo',
  idTokenProvider: () async => 'tok',
  httpClient: client,
);

FakeSpectrumAuthService _signedInAuth() => FakeSpectrumAuthService(
  initialUser: const SpectrumUser(uid: 'uid-1', displayName: 'Dana'),
);

String _entryDoc(ScoutEntry entry) => jsonEncode({
  'name':
      'projects/demo/databases/(default)/documents/scoutEntries/'
      '${entry.id}',
  'fields': fc.FirestoreValueCodec.encodeFields(<String, dynamic>{
    ...entry.toJson(),
    'updatedAtTs': entry.updatedAt.toUtc(),
  }),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'push stamps the author and writes updatedAtTs as a timestamp',
    () async {
      late Map<String, dynamic> written;
      late Uri url;
      final service = DesktopScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            url = request.url;
            written = (jsonDecode(request.body) as Map)['fields'] != null
                ? ((jsonDecode(request.body) as Map)['fields'] as Map)
                      .cast<String, dynamic>()
                : <String, dynamic>{};
            return http.Response(
              jsonEncode({
                'name':
                    'projects/demo/databases/(default)/documents/'
                    'scoutEntries/e1',
                'fields': written,
              }),
              200,
            );
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );

      final entry = ScoutEntry(
        id: 'e1',
        matchId: 'Q1',
        teamNumber: 3847,
        updatedAt: DateTime.utc(2026, 7, 8, 12),
      );
      await service.push(entry);

      expect(url.path, endsWith('scoutEntries/e1'));
      final decoded = fc.FirestoreValueCodec.decodeFields(written);
      expect(decoded['authorUid'], 'uid-1');
      expect(decoded['authorDisplayName'], 'Dana');

      expect(written['updatedAtTs'], containsPair('timestampValue', anything));
      expect(decoded['updatedAtTs'], DateTime.utc(2026, 7, 8, 12));
      expect(service.status.state, ScoutingSyncState.synced);
    },
  );

  test('syncNow queries the season and emits decoded entries', () async {
    final entry = ScoutEntry(
      id: 'e2',
      matchId: 'Q2',
      teamNumber: 118,
      updatedAt: DateTime.utc(2026, 3, 1),
    );
    final service = DesktopScoutingSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          expect(request.url.path, endsWith(':runQuery'));
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final where = ((body['structuredQuery'] as Map)['where'] as Map)
              .cast<String, dynamic>();
          final filter = (where['fieldFilter'] as Map).cast<String, dynamic>();
          expect((filter['field'] as Map)['fieldPath'], 'updatedAt');
          expect(filter['op'], 'GREATER_THAN_OR_EQUAL');
          return http.Response(
            jsonEncode([
              {'document': jsonDecode(_entryDoc(entry))},
            ]),
            200,
          );
        }),
      ),
    );

    final remote = service.remoteEntriesStream.first;
    await service.syncNow();
    final entries = await remote;
    expect(entries.single.id, 'e2');
    expect(entries.single.teamNumber, 118);
    expect(entries.single.updatedAt, DateTime.utc(2026, 3, 1));
    expect(service.status.state, ScoutingSyncState.synced);
  });

  test('a 403 reads as noAccess (membership gate), not offline', () async {
    final service = DesktopScoutingSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 403, 'message': 'Missing permissions.'},
            }),
            403,
          ),
        ),
      ),
    );
    await service.syncNow();
    expect(service.status.state, ScoutingSyncState.noAccess);
  });

  test('a network failure reads as offline', () async {
    final service = DesktopScoutingSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((_) async => throw http.ClientException('refused')),
      ),
    );
    await service.syncNow();
    expect(service.status.state, ScoutingSyncState.offline);
  });

  test('signed out: no pushes, signedOut status', () async {
    var requests = 0;
    final service = DesktopScoutingSyncService(
      authService: FakeSpectrumAuthService(),
      firestore: _firestore(
        MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      ),
    );
    await service.push(
      ScoutEntry(
        id: 'e3',
        matchId: 'Q3',
        teamNumber: 1,
        updatedAt: DateTime.utc(2026),
      ),
    );
    await service.syncNow();
    expect(requests, 0);
    expect(service.status.state, ScoutingSyncState.signedOut);
  });

  test('delete removes the document; a failure reads as a status', () async {
    final entry = ScoutEntry(
      id: 'e5',
      matchId: 'Q5',
      teamNumber: 3847,
      updatedAt: DateTime.utc(2026, 7, 9),
    );
    late Uri url;
    late String method;
    final service = DesktopScoutingSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          url = request.url;
          method = request.method;
          return http.Response('{}', 200);
        }),
      ),
    );
    await service.delete(entry);
    expect(method, 'DELETE');
    expect(url.path, endsWith('scoutEntries/e5'));
    expect(service.status.state, ScoutingSyncState.synced);

    final denied = DesktopScoutingSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 403, 'message': 'denied'},
            }),
            403,
          ),
        ),
      ),
    );
    await denied.delete(entry);
    expect(denied.status.state, ScoutingSyncState.noAccess);
  });

  test('overlapping syncNow calls apply in call order, not arrival', () async {
    final entry = ScoutEntry(
      id: 'e9',
      matchId: 'Q9',
      teamNumber: 3847,
      updatedAt: DateTime.utc(2026, 3, 2),
    );
    var calls = 0;
    final service = DesktopScoutingSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((_) async {
          calls++;
          if (calls == 1) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }
          return http.Response(
            jsonEncode([
              {'document': jsonDecode(_entryDoc(entry))},
            ]),
            200,
          );
        }),
      ),
    );

    final snapshots = <List<ScoutEntry>>[];
    final sub = service.remoteEntriesStream.listen(snapshots.add);
    await Future.wait(<Future<void>>[service.syncNow(), service.syncNow()]);

    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(snapshots, hasLength(2));
    expect(snapshots.first, isEmpty);
    expect(snapshots.last.single.id, 'e9');
  });

  test('initialize starts polling once signed in', () async {
    final auth = FakeSpectrumAuthService();
    var queries = 0;
    final service = DesktopScoutingSyncService(
      authService: auth,
      firestore: _firestore(
        MockClient((_) async {
          queries++;
          return http.Response(jsonEncode(<dynamic>[]), 200);
        }),
      ),
      pollInterval: const Duration(milliseconds: 10),
      pendingPushQueue: FakePendingPushQueue(),
    );
    await service.initialize();
    expect(queries, 0);

    await auth.signIn();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(queries, greaterThanOrEqualTo(2));
    await service.dispose();
  });

  test('failed push marks the entry and reports pendingWrites', () async {
    final queue = FakePendingPushQueue();
    final service = DesktopScoutingSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((_) async => throw http.ClientException('offline')),
      ),
      pendingPushQueue: queue,
    );

    final entry = ScoutEntry(
      id: 'e-retry-1',
      matchId: 'Q1',
      teamNumber: 118,
      updatedAt: DateTime.utc(2026, 7, 8, 12),
    );
    await service.push(entry);

    expect(service.status.state, ScoutingSyncState.offline);
    expect(await queue.pending('scoutEntries'), {'e-retry-1'});
    expect(service.status.pendingWrites, 1);
  });

  test('successful push clears the entry from the queue', () async {
    final queue = FakePendingPushQueue();
    await queue.mark('scoutEntries', 'e-retry-2');
    final service = DesktopScoutingSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          return http.Response(
            jsonEncode({
              'name':
                  'projects/demo/databases/(default)/documents/'
                  'scoutEntries/e-retry-2',
              'fields': (jsonDecode(request.body) as Map)['fields'],
            }),
            200,
          );
        }),
      ),
      pendingPushQueue: queue,
    );

    final entry = ScoutEntry(
      id: 'e-retry-2',
      matchId: 'Q1',
      teamNumber: 118,
      updatedAt: DateTime.utc(2026, 7, 8, 12),
    );
    await service.push(entry);

    expect(service.status.state, ScoutingSyncState.synced);
    expect(await queue.pending('scoutEntries'), isEmpty);
    expect(service.status.pendingWrites, 0);
  });

  test('syncNow retries a failed push from local storage', () async {
    final queue = FakePendingPushQueue();
    final storage = FakeScoutingStorage();
    final entry = ScoutEntry(
      id: 'e-retry-3',
      matchId: 'Q1',
      teamNumber: 118,
      updatedAt: DateTime.utc(2026, 7, 8, 12),
    );

    await storage.saveEntry(entry);
    await queue.mark('scoutEntries', 'e-retry-3');

    var pushAttempts = 0;
    final service = DesktopScoutingSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          if (!request.url.path.contains(':runQuery')) {
            pushAttempts++;

            return http.Response(
              jsonEncode({
                'name':
                    'projects/demo/databases/(default)/documents/'
                    'scoutEntries/e-retry-3',
                'fields': fc.FirestoreValueCodec.encodeFields(entry.toJson()),
              }),
              200,
            );
          }

          return http.Response(jsonEncode(<dynamic>[]), 200);
        }),
      ),
      storage: storage,
      pendingPushQueue: queue,
    );

    await service.syncNow();

    expect(pushAttempts, 1);
    expect(await queue.pending('scoutEntries'), isEmpty);
    expect(service.status.state, ScoutingSyncState.synced);
    expect(service.status.pendingWrites, 0);
  });

  test('failed push retries on next tick and clears on success', () async {
    final queue = FakePendingPushQueue();
    final storage = FakeScoutingStorage();
    final entry = ScoutEntry(
      id: 'e-retry-4',
      matchId: 'Q2',
      teamNumber: 3847,
      updatedAt: DateTime.utc(2026, 7, 8, 12),
    );
    await storage.saveEntry(entry);

    var attempts = 0;
    final service = DesktopScoutingSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          if (!request.url.path.contains(':runQuery')) {
            attempts++;
            if (attempts == 1) {
              throw http.ClientException('offline');
            }

            return http.Response(
              jsonEncode({
                'name':
                    'projects/demo/databases/(default)/documents/'
                    'scoutEntries/e-retry-4',
                'fields': fc.FirestoreValueCodec.encodeFields(entry.toJson()),
              }),
              200,
            );
          }
          return http.Response(jsonEncode(<dynamic>[]), 200);
        }),
      ),
      storage: storage,
      pendingPushQueue: queue,
    );

    await service.push(entry);
    expect(await queue.pending('scoutEntries'), {'e-retry-4'});
    expect(attempts, 1);

    await service.syncNow();

    expect(attempts, 2);
    expect(await queue.pending('scoutEntries'), isEmpty);
    expect(service.status.state, ScoutingSyncState.synced);
    expect(service.status.pendingWrites, 0);
  });

  test(
    'the second poll queries updatedAtTs from the first poll\'s cursor',
    () async {
      final entry = ScoutEntry(
        id: 'e-cursor',
        matchId: 'Q1',
        teamNumber: 3847,
        updatedAt: DateTime.utc(2026, 7, 8, 12),
      );
      final fields = <String>[];
      final service = DesktopScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final where = ((body['structuredQuery'] as Map)['where'] as Map)
                .cast<String, dynamic>();
            final filter = (where['fieldFilter'] as Map)
                .cast<String, dynamic>();
            fields.add((filter['field'] as Map)['fieldPath']);
            if (fields.length == 1) {
              return http.Response(
                jsonEncode([
                  {'document': jsonDecode(_entryDoc(entry))},
                ]),
                200,
              );
            }
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
      );

      await service.syncNow();
      await service.syncNow();

      expect(fields, ['updatedAt', 'updatedAtTs']);
    },
  );

  test(
    'a delta poll merges into the cache instead of replacing the snapshot',
    () async {
      final first = ScoutEntry(
        id: 'e-a',
        matchId: 'Q1',
        teamNumber: 1,
        updatedAt: DateTime.utc(2026, 7, 1),
      );
      final second = ScoutEntry(
        id: 'e-b',
        matchId: 'Q2',
        teamNumber: 2,
        updatedAt: DateTime.utc(2026, 7, 2),
      );
      var calls = 0;
      final service = DesktopScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((_) async {
            calls++;
            if (calls == 1) {
              return http.Response(
                jsonEncode([
                  {'document': jsonDecode(_entryDoc(first))},
                ]),
                200,
              );
            }

            return http.Response(
              jsonEncode([
                {'document': jsonDecode(_entryDoc(second))},
              ]),
              200,
            );
          }),
        ),
      );

      final snapshots = <List<ScoutEntry>>[];
      final sub = service.remoteEntriesStream.listen(snapshots.add);
      await service.syncNow();
      await service.syncNow();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots[0].map((e) => e.id), ['e-a']);

      expect(snapshots[1].map((e) => e.id).toSet(), {'e-a', 'e-b'});
    },
  );

  test(
    'every tenth poll re-fetches the season to catch remote deletes',
    () async {
      final fields = <String>[];
      final service = DesktopScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final where = ((body['structuredQuery'] as Map)['where'] as Map)
                .cast<String, dynamic>();
            final filter = (where['fieldFilter'] as Map)
                .cast<String, dynamic>();
            fields.add((filter['field'] as Map)['fieldPath'] as String);
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
      );

      for (var i = 0; i < 21; i++) {
        await service.syncNow();
      }

      expect(fields.length, 21);
      for (var i = 0; i < fields.length; i++) {
        final expected = (i == 0 || i == 10 || i == 20)
            ? 'updatedAt'
            : 'updatedAtTs';
        expect(fields[i], expected, reason: 'poll ${i + 1}');
      }
    },
  );

  test(
    'a delete during a poll fetch is not resurrected by that poll (#1511)',
    () async {
      final entry = ScoutEntry(
        id: 'e-raced',
        matchId: 'Q1',
        teamNumber: 3847,
        updatedAt: DateTime.utc(2026, 7, 8, 12),
      );

      final gate = Completer<void>();
      var queries = 0;
      final service = DesktopScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'DELETE') return http.Response('{}', 200);
            queries++;
            if (queries == 2) await gate.future;

            return http.Response(
              jsonEncode([
                {'document': jsonDecode(_entryDoc(entry))},
              ]),
              200,
            );
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );

      final snapshots = <List<ScoutEntry>>[];
      final sub = service.remoteEntriesStream.listen(snapshots.add);
      await service.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(snapshots.last.map((e) => e.id), ['e-raced']);

      final second = service.syncNow();
      await Future<void>.delayed(Duration.zero);

      await service.delete(entry);
      gate.complete();
      await second;
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots.last, isEmpty);
      await service.dispose();
    },
  );

  test(
    'a push during a full-sync fetch is not discarded by that poll (#1511)',
    () async {
      final entry = ScoutEntry(
        id: 'e-pushed',
        matchId: 'Q2',
        teamNumber: 3847,
        updatedAt: DateTime.utc(2026, 7, 8, 12),
      );
      final gate = Completer<void>();
      final service = DesktopScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.url.path.endsWith(':runQuery')) {
              await gate.future;

              return http.Response(jsonEncode(<dynamic>[]), 200);
            }
            return http.Response(_entryDoc(entry), 200);
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );

      final snapshots = <List<ScoutEntry>>[];
      final sub = service.remoteEntriesStream.listen(snapshots.add);

      final first = service.syncNow();
      await Future<void>.delayed(Duration.zero);
      await service.push(entry);
      gate.complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots.last.map((e) => e.id), ['e-pushed']);
      await service.dispose();
    },
  );

  test(
    'a local delete evicts the cache so a stale delta cannot resurrect it',
    () async {
      final entry = ScoutEntry(
        id: 'e-deleted',
        matchId: 'Q1',
        teamNumber: 3847,
        updatedAt: DateTime.utc(2026, 7, 8, 12),
      );
      var calls = 0;
      final service = DesktopScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'DELETE') return http.Response('{}', 200);
            calls++;
            if (calls == 1) {
              return http.Response(
                jsonEncode([
                  {'document': jsonDecode(_entryDoc(entry))},
                ]),
                200,
              );
            }

            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
      );

      final snapshots = <List<ScoutEntry>>[];
      final sub = service.remoteEntriesStream.listen(snapshots.add);
      await service.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(snapshots.last.map((e) => e.id), ['e-deleted']);

      await service.delete(entry);
      await service.syncNow();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots.last, isEmpty);
    },
  );

  test('a document with no server timestamp cannot push the cursor into the '
      'future', () async {
    final fastClockEntry = ScoutEntry(
      id: 'e-fast',
      matchId: 'Q1',
      teamNumber: 3847,
      updatedAt: DateTime.utc(2030),
    );
    final docWithoutServerTs = jsonEncode({
      'name':
          'projects/demo/databases/(default)/documents/'
          'scoutEntries/e-fast',
      'fields': fc.FirestoreValueCodec.encodeFields(fastClockEntry.toJson()),
    });
    final fixedNow = DateTime.utc(2026, 7, 8, 12);
    final filters = <Map<String, dynamic>>[];
    final service = DesktopScoutingSyncService(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final where = ((body['structuredQuery'] as Map)['where'] as Map)
              .cast<String, dynamic>();
          filters.add((where['fieldFilter'] as Map).cast<String, dynamic>());
          return http.Response(
            jsonEncode([
              {'document': jsonDecode(docWithoutServerTs)},
            ]),
            200,
          );
        }),
      ),
      clock: () => fixedNow,
    );

    await service.syncNow();
    await service.syncNow();

    final secondFilterValue =
        (filters[1]['value'] as Map)['timestampValue'] as String;
    expect(DateTime.parse(secondFilterValue).year, lessThan(2030));
  });
}
