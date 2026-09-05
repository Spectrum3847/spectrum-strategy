import 'dart:async';
import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_pit_scouting_sync_service.dart';
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

String _doc(PitScoutEntry entry, {DateTime? serverTs}) => jsonEncode({
  'name':
      'projects/demo/databases/(default)/documents/pitScoutEntries/'
      '${entry.id}',
  'fields': fc.FirestoreValueCodec.encodeFields(<String, dynamic>{
    ...entry.toJson(),
    'updatedAtTs': ?serverTs,
  }),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'the second poll queries updatedAtTs, not the whole collection',
    () async {
      final entry = PitScoutEntry(
        id: 'p1',
        teamNumber: 3847,
        updatedAt: DateTime.utc(2026, 7, 8),
      );
      final fields = <String>[];
      final service = DesktopPitScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.url.path.endsWith(':runQuery')) {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              final filter =
                  ((body['structuredQuery'] as Map)['where']
                          as Map)['fieldFilter']
                      as Map;
              fields.add((filter['field'] as Map)['fieldPath'] as String);
              return http.Response(jsonEncode(<dynamic>[]), 200);
            }
            fields.add('(listDocuments)');
            return http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc(entry, serverTs: entry.updatedAt)),
                ],
              }),
              200,
            );
          }),
        ),
      );

      await service.syncNow();
      await service.syncNow();

      expect(fields, ['(listDocuments)', 'updatedAtTs']);
    },
  );

  test(
    'a delta poll merges into the cache instead of replacing the snapshot',
    () async {
      final first = PitScoutEntry(
        id: 'p-a',
        teamNumber: 1,
        updatedAt: DateTime.utc(2026, 7, 1),
      );
      final second = PitScoutEntry(
        id: 'p-b',
        teamNumber: 2,
        updatedAt: DateTime.utc(2026, 7, 2),
      );
      var calls = 0;
      final service = DesktopPitScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((_) async {
            calls++;
            if (calls == 1) {
              return http.Response(
                jsonEncode({
                  'documents': [
                    jsonDecode(_doc(first, serverTs: first.updatedAt)),
                  ],
                }),
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
      );

      final snapshots = <List<PitScoutEntry>>[];
      final sub = service.remoteEntriesStream.listen(snapshots.add);
      await service.syncNow();
      await service.syncNow();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots[0].map((e) => e.id), ['p-a']);

      expect(snapshots[1].map((e) => e.id).toSet(), {'p-a', 'p-b'});
    },
  );

  test(
    'every tenth poll re-fetches the collection to catch remote deletes',
    () async {
      final fields = <String>[];
      final service = DesktopPitScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.url.path.endsWith(':runQuery')) {
              fields.add('delta');
              return http.Response(jsonEncode(<dynamic>[]), 200);
            }
            fields.add('full');
            return http.Response(jsonEncode({'documents': <dynamic>[]}), 200);
          }),
        ),
      );

      for (var i = 0; i < 21; i++) {
        await service.syncNow();
      }

      expect(fields.length, 21);
      for (var i = 0; i < fields.length; i++) {
        final expected = (i == 0 || i == 10 || i == 20) ? 'full' : 'delta';
        expect(fields[i], expected, reason: 'poll ${i + 1}');
      }
    },
  );

  test(
    'a local delete evicts the cache so a stale delta cannot resurrect it',
    () async {
      final entry = PitScoutEntry(
        id: 'p-deleted',
        teamNumber: 3847,
        updatedAt: DateTime.utc(2026, 7, 8),
      );
      var calls = 0;
      final service = DesktopPitScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'DELETE') return http.Response('{}', 200);
            calls++;
            if (calls == 1) {
              return http.Response(
                jsonEncode({
                  'documents': [
                    jsonDecode(_doc(entry, serverTs: entry.updatedAt)),
                  ],
                }),
                200,
              );
            }

            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );

      await service.syncNow();
      await service.delete(entry);

      final snapshots = <List<PitScoutEntry>>[];
      final sub = service.remoteEntriesStream.listen(snapshots.add);
      await service.syncNow();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots.single, isEmpty);
    },
  );

  test(
    'a delete during a poll fetch is not resurrected by that poll (#1511)',
    () async {
      final entry = PitScoutEntry(
        id: 'p-raced',
        teamNumber: 3847,
        updatedAt: DateTime.utc(2026, 7, 8),
      );

      final gate = Completer<void>();
      var queries = 0;
      final service = DesktopPitScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'DELETE') return http.Response('{}', 200);
            if (request.url.path.endsWith(':runQuery')) {
              queries++;
              if (queries == 1) await gate.future;

              return http.Response(
                jsonEncode([
                  {
                    'document': jsonDecode(
                      _doc(entry, serverTs: entry.updatedAt),
                    ),
                  },
                ]),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc(entry, serverTs: entry.updatedAt)),
                ],
              }),
              200,
            );
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );

      final snapshots = <List<PitScoutEntry>>[];
      final sub = service.remoteEntriesStream.listen(snapshots.add);
      await service.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(snapshots.last.map((e) => e.id), ['p-raced']);

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
      final entry = PitScoutEntry(
        id: 'p-pushed',
        teamNumber: 3847,
        updatedAt: DateTime.utc(2026, 7, 8),
      );
      final gate = Completer<void>();
      final service = DesktopPitScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'GET') {
              await gate.future;

              return http.Response(jsonEncode({'documents': <dynamic>[]}), 200);
            }
            return http.Response(_doc(entry, serverTs: entry.updatedAt), 200);
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );

      final snapshots = <List<PitScoutEntry>>[];
      final sub = service.remoteEntriesStream.listen(snapshots.add);

      final first = service.syncNow();
      await Future<void>.delayed(Duration.zero);
      await service.push(entry);
      gate.complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots.last.map((e) => e.id), ['p-pushed']);
      await service.dispose();
    },
  );

  test(
    'a document with no server timestamp cannot advance the cursor',
    () async {
      final docA = PitScoutEntry(
        id: 'a',
        teamNumber: 1,
        updatedAt: DateTime.utc(2026, 7, 1),
      );
      final docB = PitScoutEntry(
        id: 'b',
        teamNumber: 2,
        updatedAt: DateTime.utc(2099, 1, 1),
      );
      DateTime? capturedFilterValue;
      var calls = 0;
      final service = DesktopPitScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            calls++;
            if (calls == 1) {
              return http.Response(
                jsonEncode({
                  'documents': [
                    jsonDecode(_doc(docA, serverTs: docA.updatedAt)),

                    jsonDecode(_doc(docB)),
                  ],
                }),
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
