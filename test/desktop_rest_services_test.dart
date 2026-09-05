import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/models/pick_list.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_assignment.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_accuracy_alert_service.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_scout_assignment_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_pit_scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/services/desktop_scout_config_sync_service.dart';
import 'package:spectrumstrategy/src/models/trait_table.dart';
import 'package:spectrumstrategy/src/services/desktop_pick_list_sync_service.dart';
import 'package:spectrumstrategy/src/services/desktop_trait_table_sync_service.dart';
import 'package:spectrumstrategy/src/services/pick_list_sync_service.dart';
import 'package:spectrumstrategy/src/services/pending_push_queue.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

import 'support/fake_pending_push_queue.dart';
import 'support/fake_pick_list_storage.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_spectrum_auth_service.dart';

fc.Firestore _firestore(MockClient client) => fc.Firestore(
  projectId: 'demo',
  idTokenProvider: () async => 'tok',
  httpClient: client,
);

FakeSpectrumAuthService _signedInAuth() => FakeSpectrumAuthService(
  initialUser: const SpectrumUser(uid: 'uid-1', displayName: 'Dana'),
);

String _doc(String path, Map<String, dynamic> fields) => jsonEncode({
  'name': 'projects/demo/databases/(default)/documents/$path',
  'fields': fc.FirestoreValueCodec.encodeFields(fields),
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
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('DesktopPickListSyncService', () {
    final list = PickList(
      id: 'l1',
      name: 'First pick',
      teamNumbers: const [3847],
      updatedAt: DateTime.utc(2026, 7, 8, 12),
    );

    test(
      'pushTeamAdd is an atomic array transform, not a full write',
      () async {
        late Map<String, dynamic> body;
        final service = DesktopPickListSyncService(
          authService: _signedInAuth(),
          firestore: _firestore(
            MockClient((request) async {
              expect(request.url.path, endsWith('documents:commit'));
              body = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response('{}', 200);
            }),
          ),
          pendingPushQueue: FakePendingPushQueue(),
        );
        await service.pushTeamAdd(list, 118);

        final write = ((body['writes'] as List).single as Map)
            .cast<String, dynamic>();
        expect(
          (write['updateMask'] as Map)['fieldPaths'],
          unorderedEquals(['updatedAt', 'updatedAtTs']),
        );
        expect((write['currentDocument'] as Map)['exists'], isTrue);
        final transform = ((write['updateTransforms'] as List).single as Map)
            .cast<String, dynamic>();
        expect(transform['fieldPath'], 'teamNumbers');
        expect(transform.containsKey('appendMissingElements'), isTrue);
        expect(service.status.state, PickListSyncState.synced);
      },
    );

    test('pushTeamRemove uses removeAllFromArray', () async {
      late Map<String, dynamic> body;
      final service = DesktopPickListSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('{}', 200);
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );
      await service.pushTeamRemove(list, 118);
      final write = ((body['writes'] as List).single as Map)
          .cast<String, dynamic>();
      final transform = ((write['updateTransforms'] as List).single as Map)
          .cast<String, dynamic>();
      expect(transform.containsKey('removeAllFromArray'), isTrue);
    });

    test('a team op on a missing document falls back to a full push', () async {
      var commits = 0;
      var fullWrites = 0;
      final service = DesktopPickListSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.url.path.endsWith('documents:commit')) {
              commits++;
              return http.Response(
                jsonEncode([
                  {
                    'error': {
                      'code': 404,
                      'message': 'No document to update',
                      'status': 'NOT_FOUND',
                    },
                  },
                ]),
                400,
              );
            }
            expect(request.method, 'PATCH');
            fullWrites++;
            return http.Response(_doc('pickLists/l1', list.toJson()), 200);
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );
      await service.pushTeamAdd(list, 118);
      expect(commits, 1);
      expect(fullWrites, 1);
      expect(service.status.state, PickListSyncState.synced);
    });

    test('push writes updatedAtTs as a timestamp', () async {
      late Map<String, dynamic> written;
      final service = DesktopPickListSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            written = ((jsonDecode(request.body) as Map)['fields'] as Map)
                .cast<String, dynamic>();
            return http.Response(_doc('pickLists/l1', list.toJson()), 200);
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );
      await service.push(list);

      expect(written['updatedAtTs'], containsPair('timestampValue', anything));
      final decoded = fc.FirestoreValueCodec.decodeFields(written);
      expect(decoded['updatedAtTs'], DateTime.utc(2026, 7, 8, 12));
    });

    test('decode orders by updatedAtTs, not a poisoned string', () async {
      final service = DesktopPickListSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(
                    _doc('pickLists/l1', {
                      ...list.toJson(),
                      'updatedAt': '2099-01-01T00:00:00.000Z',
                      'updatedAtTs': DateTime.utc(2026, 7, 8, 12),
                    }),
                  ),
                ],
              }),
              200,
            ),
          ),
        ),
      );
      final remote = service.remoteListsStream.first;
      await service.syncNow();
      expect((await remote).single.updatedAt, DateTime.utc(2026, 7, 8, 12));
    });

    test('syncNow lists the collection; 403 reads as noAccess', () async {
      final okService = DesktopPickListSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'documents': [jsonDecode(_doc('pickLists/l1', list.toJson()))],
              }),
              200,
            ),
          ),
        ),
      );
      final remote = okService.remoteListsStream.first;
      await okService.syncNow();
      expect((await remote).single.name, 'First pick');

      final deniedService = DesktopPickListSyncService(
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
      await deniedService.syncNow();
      expect(deniedService.status.state, PickListSyncState.noAccess);
    });

    test('delete removes the document; a failure reads as a status', () async {
      late Uri url;
      late String method;
      final service = DesktopPickListSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            url = request.url;
            method = request.method;
            return http.Response('{}', 200);
          }),
        ),
      );
      await service.delete(list);
      expect(method, 'DELETE');
      expect(url.path, endsWith('pickLists/l1'));
      expect(service.status.state, PickListSyncState.synced);

      final denied = DesktopPickListSyncService(
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
      await denied.delete(list);
      expect(denied.status.state, PickListSyncState.noAccess);
    });

    test(
      'a failed team-add retries as the same atomic transform, not a full push',
      () async {
        final storage = FakePickListStorage();
        await storage.save(list);
        final queue = FakePendingPushQueue();
        var commitAttempts = 0;
        var fullWrites = 0;
        late Map<String, dynamic> retriedBody;
        final service = DesktopPickListSyncService(
          authService: _signedInAuth(),
          firestore: _firestore(
            MockClient((request) async {
              if (request.url.path.endsWith('documents:commit')) {
                commitAttempts++;
                if (commitAttempts == 1) {
                  throw http.ClientException('offline');
                }
                retriedBody = jsonDecode(request.body) as Map<String, dynamic>;
                return http.Response('{}', 200);
              }
              if (request.method == 'PATCH') {
                fullWrites++;
                return http.Response(_doc('pickLists/l1', list.toJson()), 200);
              }

              return http.Response(jsonEncode({'documents': <dynamic>[]}), 200);
            }),
          ),
          storage: storage,
          pendingPushQueue: queue,
        );

        await service.pushTeamAdd(list, 118);
        expect(commitAttempts, 1);
        expect(await queue.pending('pickLists'), {'l1'});

        await service.syncNow();

        expect(commitAttempts, 2);
        expect(fullWrites, 0);
        expect(await queue.pending('pickLists'), isEmpty);
        final write = ((retriedBody['writes'] as List).single as Map)
            .cast<String, dynamic>();
        final transform = ((write['updateTransforms'] as List).single as Map)
            .cast<String, dynamic>();
        expect(transform['fieldPath'], 'teamNumbers');
        expect(transform.containsKey('appendMissingElements'), isTrue);
      },
    );

    test('multiple queued team ops replay in order on the next sync', () async {
      final storage = FakePickListStorage();
      await storage.save(list);
      final queue = FakePendingPushQueue();
      var offline = true;
      final appliedTeams = <int>[];
      final appliedIsAdd = <bool>[];
      final service = DesktopPickListSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.url.path.endsWith('documents:commit')) {
              if (offline) {
                throw http.ClientException('offline');
              }
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              final write = ((body['writes'] as List).single as Map)
                  .cast<String, dynamic>();
              final transform =
                  ((write['updateTransforms'] as List).single as Map)
                      .cast<String, dynamic>();
              final isAdd = transform.containsKey('appendMissingElements');
              final values =
                  ((isAdd
                              ? transform['appendMissingElements']
                              : transform['removeAllFromArray'])
                          as Map)['values']
                      as List;
              final encoded = (values.single as Map).cast<String, dynamic>();
              appliedTeams.add(int.parse(encoded['integerValue'] as String));
              appliedIsAdd.add(isAdd);
              return http.Response('{}', 200);
            }
            if (request.method == 'PATCH') {
              return http.Response(_doc('pickLists/l1', list.toJson()), 200);
            }
            return http.Response(jsonEncode({'documents': <dynamic>[]}), 200);
          }),
        ),
        storage: storage,
        pendingPushQueue: queue,
      );

      await service.pushTeamAdd(list, 100);
      await service.pushTeamRemove(list, 200);
      expect(await queue.pending('pickLists'), {'l1'});
      expect(appliedTeams, isEmpty);

      offline = false;
      await service.syncNow();

      expect(appliedTeams, [100, 200]);
      expect(appliedIsAdd, [true, false]);
      expect(await queue.pending('pickLists'), isEmpty);
    });
  });

  group('DesktopPitScoutingSyncService', () {
    test('push stamps the author; syncNow decodes entries', () async {
      final entry = PitScoutEntry(
        id: 'p1',
        teamNumber: 3847,
        updatedAt: DateTime.utc(2026, 7, 8),
      );
      late Map<String, dynamic> written;
      final service = DesktopPitScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'PATCH') {
              written = ((jsonDecode(request.body) as Map)['fields'] as Map)
                  .cast<String, dynamic>();
              return http.Response(_doc('pitScoutEntries/p1', {}), 200);
            }
            if (request.url.path.endsWith(':runQuery')) {
              return http.Response(
                jsonEncode([
                  {
                    'document': jsonDecode(
                      _doc('pitScoutEntries/p1', entry.toJson()),
                    ),
                  },
                ]),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'documents': [
                  jsonDecode(_doc('pitScoutEntries/p1', entry.toJson())),
                ],
              }),
              200,
            );
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );
      await service.push(entry);
      final decoded = fc.FirestoreValueCodec.decodeFields(written);
      expect(decoded['authorUid'], 'uid-1');

      expect(written['updatedAtTs'], containsPair('timestampValue', anything));
      expect(decoded['updatedAtTs'], DateTime.utc(2026, 7, 8));

      final remote = service.remoteEntriesStream.first;
      await service.syncNow();
      expect((await remote).single.teamNumber, 3847);
    });

    test('delete removes the document; a failure reads as a status', () async {
      final entry = PitScoutEntry(
        id: 'p9',
        teamNumber: 118,
        updatedAt: DateTime.utc(2026, 7, 9),
      );
      late Uri url;
      late String method;
      final service = DesktopPitScoutingSyncService(
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
      expect(url.path, endsWith('pitScoutEntries/p9'));
      expect(service.status.state, PitScoutingSyncState.synced);

      final denied = DesktopPitScoutingSyncService(
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
      expect(denied.status.state, PitScoutingSyncState.noAccess);
    });

    test('failed push retries on next sync and clears on success', () async {
      final storage = FakePitScoutingStorage();
      final entry = PitScoutEntry(
        id: 'p-retry-1',
        teamNumber: 3847,
        updatedAt: DateTime.utc(2026, 7, 8),
      );
      await storage.saveEntry(entry);
      final queue = FakePendingPushQueue();
      var pushAttempts = 0;
      final service = DesktopPitScoutingSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'PATCH') {
              pushAttempts++;
              if (pushAttempts == 1) {
                throw http.ClientException('offline');
              }
              return http.Response(_doc('pitScoutEntries/p-retry-1', {}), 200);
            }
            if (request.url.path.endsWith(':runQuery')) {
              return http.Response(jsonEncode(<dynamic>[]), 200);
            }
            return http.Response(jsonEncode({'documents': <dynamic>[]}), 200);
          }),
        ),
        storage: storage,
        pendingPushQueue: queue,
      );

      await service.push(entry);
      expect(pushAttempts, 1);
      expect(await queue.pending('pitScoutEntries'), {'p-retry-1'});
      expect(service.status.state, PitScoutingSyncState.offline);

      await service.syncNow();

      expect(pushAttempts, 2);
      expect(await queue.pending('pitScoutEntries'), isEmpty);
      expect(service.status.state, PitScoutingSyncState.synced);
    });
  });

  group('DesktopScoutConfigSyncService', () {
    test('polls the config doc and re-emits only on change', () async {
      const configJson =
          '{"title":"Test form","sections":[],"delimiter":"\\t"}';
      var gets = 0;
      final auth = _signedInAuth();
      final service = DesktopScoutConfigSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((_) async {
            gets++;
            return http.Response(
              _doc('appConfig/scoutConfig', {'configJson': configJson}),
              200,
            );
          }),
        ),
        pollInterval: const Duration(milliseconds: 10),
      );
      final emissions = <ScoutConfig?>[];
      final sub = service.configStream.listen(emissions.add);
      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await service.dispose();
      await sub.cancel();

      expect(gets, greaterThanOrEqualTo(2));

      expect(emissions, hasLength(1));
      expect(emissions.single?.title, 'Test form');
    });

    test('push writes configJson to appConfig/scoutConfig', () async {
      late Uri url;
      late Map<String, dynamic> written;
      final service = DesktopScoutConfigSyncService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            url = request.url;
            written = ((jsonDecode(request.body) as Map)['fields'] as Map)
                .cast<String, dynamic>();
            return http.Response(_doc('appConfig/scoutConfig', {}), 200);
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );
      await service.push(const ScoutConfig(title: 'Pushed', sections: []));
      expect(url.path, endsWith('appConfig/scoutConfig'));
      final decoded = fc.FirestoreValueCodec.decodeFields(written);
      expect(decoded['configJson'], contains('Pushed'));
    });

    test('the .pit() constructor writes to appConfig/pitScoutConfig', () async {
      late Uri url;
      final service = DesktopScoutConfigSyncService.pit(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            url = request.url;
            return http.Response(_doc('appConfig/pitScoutConfig', {}), 200);
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );
      await service.push(const ScoutConfig(title: 'Pit Pushed', sections: []));
      expect(url.path, endsWith('appConfig/pitScoutConfig'));
    });

    test(
      'a failed push retries on the next poll tick and clears on success',
      () async {
        var attempts = 0;
        final queue = FakePendingPushQueue();
        final service = DesktopScoutConfigSyncService(
          authService: _signedInAuth(),
          firestore: _firestore(
            MockClient((request) async {
              if (request.method == 'GET') {
                return http.Response('', 404);
              }
              attempts++;
              if (attempts == 1) {
                throw http.ClientException('offline');
              }
              return http.Response(_doc('appConfig/scoutConfig', {}), 200);
            }),
          ),
          pollInterval: const Duration(milliseconds: 10),
          pendingPushQueue: queue,
        );
        addTearDown(service.dispose);

        await expectLater(
          () => service.push(const ScoutConfig(title: 'Pushed', sections: [])),
          throwsA(isA<http.ClientException>()),
        );
        expect(attempts, 1);
        expect(await queue.pending('appConfig'), {'scoutConfig'});

        await service.initialize();
        await _waitUntil(() => attempts >= 2);

        expect(attempts, greaterThanOrEqualTo(2));
        expect(await queue.pending('appConfig'), isEmpty);
      },
    );
  });

  group('DesktopAccuracyAlertService', () {
    Map<String, dynamic> alertJson(String entryId) => {
      'entryId': entryId,
      'teamNumber': 3847,
      'tbaMatchKey': '2026txhou_qm1',
      'authorUid': 'uid-1',
      'flaggedFields': <dynamic>[],
      'createdAt': '2026-07-08T12:00:00.000Z',
      'acknowledged': false,
    };

    test('polls the signed-in user\'s unacknowledged alerts', () async {
      final service = DesktopAccuracyAlertService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            expect(request.url.path, endsWith(':runQuery'));
            final query =
                ((jsonDecode(request.body) as Map)['structuredQuery'] as Map)
                    .cast<String, dynamic>();
            final filters =
                ((query['where'] as Map)['compositeFilter'] as Map)['filters']
                    as List;
            expect(filters, hasLength(2));
            return http.Response(
              jsonEncode([
                {
                  'document': jsonDecode(
                    _doc('accuracyAlerts/e1', alertJson('e1')),
                  ),
                },
              ]),
              200,
            );
          }),
        ),
      );
      final first = service.alertsStream.firstWhere(
        (alerts) => alerts.isNotEmpty,
      );
      await service.initialize();
      expect((await first).single.entryId, 'e1');
      await service.dispose();
    });

    test('acknowledge patches only the acknowledged field', () async {
      late Uri url;
      final service = DesktopAccuracyAlertService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'PATCH') {
              url = request.url;
              return http.Response(_doc('accuracyAlerts/e1', {}), 200);
            }
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
      );
      await service.acknowledge('e1');
      expect(url.path, endsWith('accuracyAlerts/e1'));
      expect(url.query, contains('updateMask.fieldPaths=acknowledged'));
    });

    test('acknowledging an already-deleted alert is not an error', () async {
      final service = DesktopAccuracyAlertService(
        authService: _signedInAuth(),
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'PATCH') {
              return http.Response('missing', 404);
            }
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
      );
      await service.acknowledge('gone');
    });
  });

  group('DesktopScoutAssignmentSyncService', () {
    test('polls assignments and clears them on sign-out', () async {
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      final service = DesktopScoutAssignmentSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((request) async {
            return http.Response(
              jsonEncode([
                {
                  'document': jsonDecode(
                    _doc('scoutAssignments/qm1__red1', {
                      'id': 'qm1__red1',
                      'matchKey': 'qm1',
                      'matchNumber': 1,
                      'station': 'red1',
                      'scouterUid': 'u1',
                      'scouterName': 'One',
                      'authorUid': 'uid-1',
                      'authorDisplayName': 'Dana',
                      'updatedAt': '2026-07-08T12:00:00.000Z',
                    }),
                  ),
                },
              ]),
              200,
            );
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );
      addTearDown(service.dispose);

      final seen = <List<ScoutAssignment>>[];
      service.watchAll().listen(seen.add);
      await pumpEventQueue();
      expect(seen.single.single.station, 'red1');

      await auth.signOut();
      await pumpEventQueue();
      expect(seen.last, isEmpty);
    });

    test(
      'a failed upsert retries on the next poll tick and clears on success',
      () async {
        final auth = _signedInAuth();
        addTearDown(auth.dispose);
        var writeAttempts = 0;
        final queue = FakePendingPushQueue();
        final service = DesktopScoutAssignmentSyncService(
          authService: auth,
          firestore: _firestore(
            MockClient((request) async {
              if (request.method == 'PATCH') {
                writeAttempts++;
                if (writeAttempts == 1) {
                  throw http.ClientException('offline');
                }
                return http.Response(
                  _doc('scoutAssignments/qm1__red1', {}),
                  200,
                );
              }
              return http.Response(jsonEncode(<dynamic>[]), 200);
            }),
          ),
          pollInterval: const Duration(milliseconds: 10),
          pendingPushQueue: queue,
        );
        addTearDown(service.dispose);
        service.watchAll().listen((_) {});

        final assignment = ScoutAssignment(
          id: 'qm1__red1',
          matchKey: 'qm1',
          matchNumber: 1,
          station: 'red1',
          scouterUid: 'u1',
          scouterName: 'One',
        );

        await expectLater(
          () => service.upsert(assignment),
          throwsA(isA<http.ClientException>()),
        );
        expect(writeAttempts, 1);
        expect(await queue.pending('scoutAssignments'), {'qm1__red1'});

        await _waitUntil(() => writeAttempts >= 2);

        expect(writeAttempts, greaterThanOrEqualTo(2));
        expect(await queue.pending('scoutAssignments'), isEmpty);
      },
    );

    test(
      'a failed delete retries on the next poll tick, not as an upsert',
      () async {
        final auth = _signedInAuth();
        addTearDown(auth.dispose);
        var deleteAttempts = 0;
        final queue = FakePendingPushQueue();
        final service = DesktopScoutAssignmentSyncService(
          authService: auth,
          firestore: _firestore(
            MockClient((request) async {
              if (request.method == 'DELETE') {
                deleteAttempts++;
                if (deleteAttempts == 1) {
                  throw http.ClientException('offline');
                }
                return http.Response('{}', 200);
              }
              return http.Response(jsonEncode(<dynamic>[]), 200);
            }),
          ),
          pollInterval: const Duration(milliseconds: 10),
          pendingPushQueue: queue,
        );
        addTearDown(service.dispose);
        service.watchAll().listen((_) {});

        await expectLater(
          () => service.delete('qm1__red1'),
          throwsA(isA<http.ClientException>()),
        );
        expect(deleteAttempts, 1);
        expect(await queue.pending('scoutAssignments_deleted'), {'qm1__red1'});
        expect(
          await queue.pending('scoutAssignments'),
          isEmpty,
          reason: 'a delete in the upsert queue cannot be replayed as a delete',
        );

        await _waitUntil(() => deleteAttempts >= 2);

        expect(deleteAttempts, greaterThanOrEqualTo(2));
        expect(await queue.pending('scoutAssignments_deleted'), isEmpty);
      },
    );

    test('a failed delete survives a restart and still replays', () async {
      final queue = PendingPushQueue();
      final firstAuth = _signedInAuth();
      addTearDown(firstAuth.dispose);
      final first = DesktopScoutAssignmentSyncService(
        authService: firstAuth,
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'DELETE') {
              throw http.ClientException('offline');
            }
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
        pendingPushQueue: queue,
      );
      await expectLater(
        () => first.delete('qm2__blue3'),
        throwsA(isA<http.ClientException>()),
      );
      await first.dispose();

      var deleteAttempts = 0;
      final secondAuth = _signedInAuth();
      addTearDown(secondAuth.dispose);
      final second = DesktopScoutAssignmentSyncService(
        authService: secondAuth,
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'DELETE') {
              deleteAttempts++;
              return http.Response('{}', 200);
            }
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
        pollInterval: const Duration(milliseconds: 10),

        pendingPushQueue: PendingPushQueue(),
      );
      addTearDown(second.dispose);
      second.watchAll().listen((_) {});

      await _waitUntil(() => deleteAttempts >= 1);

      expect(deleteAttempts, greaterThanOrEqualTo(1));
      expect(await queue.pending('scoutAssignments_deleted'), isEmpty);
    });

    test('an upsert after a failed delete cancels the delete', () async {
      final queue = FakePendingPushQueue();
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      var deleteAttempts = 0;
      final service = DesktopScoutAssignmentSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'DELETE') {
              deleteAttempts++;
              throw http.ClientException('offline');
            }
            if (request.method == 'PATCH') {
              return http.Response(
                _doc('scoutAssignments/qm3__red2', <String, dynamic>{}),
                200,
              );
            }
            return http.Response(jsonEncode(<dynamic>[]), 200);
          }),
        ),
        pendingPushQueue: queue,
      );
      addTearDown(service.dispose);

      await expectLater(
        () => service.delete('qm3__red2'),
        throwsA(isA<http.ClientException>()),
      );
      expect(await queue.pending('scoutAssignments_deleted'), {'qm3__red2'});

      await service.upsert(
        ScoutAssignment(
          id: 'qm3__red2',
          matchKey: 'qm3',
          matchNumber: 3,
          station: 'red2',
          scouterUid: 'u2',
          scouterName: 'Two',
        ),
      );

      expect(await queue.pending('scoutAssignments_deleted'), isEmpty);
      expect(deleteAttempts, 1, reason: 'the stale delete is never replayed');
    });
  });

  group('DesktopTraitTableSyncService', () {
    TraitTable table() => TraitTable(
      id: '2026txhou_qm1',
      eventKey: '2026txhou',
      matchId: 'qm1',
      updatedAt: DateTime.utc(2026, 8, 1),
      cells: const {
        254: {'defense': 'strong'},
      },
    );

    test('watch decodes the document, preferring updatedAtTs', () async {
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      final service = DesktopTraitTableSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((request) async {
            if (request.url.path.endsWith('appConfig/traitConfig')) {
              return http.Response(_doc('appConfig/traitConfig', {}), 200);
            }
            return http.Response(
              _doc('traitTables/2026txhou_qm1', {
                ...table().toJson(),
                'updatedAtTs': DateTime.utc(2026, 8, 2),
              }),
              200,
            );
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );
      addTearDown(service.dispose);

      final first = service.tableStream.firstWhere((t) => t != null);
      await service.watch(eventKey: '2026txhou', matchId: 'qm1');
      final got = await first;
      expect(got!.valueFor(254, 'defense'), 'strong');

      expect(got.updatedAt, DateTime.utc(2026, 8, 2));
    });

    test('push carries toJson plus the updatedAtTs timestamp', () async {
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      late Map<String, dynamic> written;
      final service = DesktopTraitTableSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'PATCH') {
              written = ((jsonDecode(request.body) as Map)['fields'] as Map)
                  .cast<String, dynamic>();
              return http.Response(_doc('traitTables/2026txhou_qm1', {}), 200);
            }
            return http.Response(_doc('appConfig/traitConfig', {}), 200);
          }),
        ),
        pendingPushQueue: FakePendingPushQueue(),
      );
      addTearDown(service.dispose);

      await service.push(table());
      final decoded = fc.FirestoreValueCodec.decodeFields(written);
      expect(decoded['matchId'], 'qm1');
      expect(written['updatedAtTs'], containsPair('timestampValue', anything));

      expect(decoded['updatedAtTs'], DateTime.utc(2026, 8, 1));
    });

    test('a failed push replays on a later tick', () async {
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      final queue = FakePendingPushQueue();
      var patches = 0;
      var failPatches = true;
      final service = DesktopTraitTableSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'PATCH') {
              patches++;
              if (failPatches) throw http.ClientException('offline');
              return http.Response(_doc('traitTables/2026txhou_qm1', {}), 200);
            }
            return http.Response(_doc('appConfig/traitConfig', {}), 200);
          }),
        ),
        pollInterval: const Duration(milliseconds: 10),
        pendingPushQueue: queue,
      );
      addTearDown(service.dispose);

      await expectLater(service.push(table()), throwsA(anything));
      expect(await queue.pending('traitTables'), {'2026txhou_qm1'});

      failPatches = false;
      await service.watch(eventKey: '2026txhou', matchId: 'qm1');
      await _waitUntil(() => patches >= 2);

      expect(patches, greaterThanOrEqualTo(2));
      expect(await queue.pending('traitTables'), isEmpty);
    });

    test('a newer failed push replaces the queued snapshot, so the retry '
        'does not clobber it with stale data', () async {
      final auth = _signedInAuth();
      addTearDown(auth.dispose);
      final queue = FakePendingPushQueue();
      var patches = 0;
      var failPatches = true;
      Map<String, dynamic>? lastWritten;
      final service = DesktopTraitTableSyncService(
        authService: auth,
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'PATCH') {
              patches++;
              if (failPatches) throw http.ClientException('offline');
              lastWritten = ((jsonDecode(request.body) as Map)['fields'] as Map)
                  .cast<String, dynamic>();
              return http.Response(_doc('traitTables/2026txhou_qm1', {}), 200);
            }
            return http.Response(_doc('appConfig/traitConfig', {}), 200);
          }),
        ),
        pollInterval: const Duration(milliseconds: 10),
        pendingPushQueue: queue,
      );
      addTearDown(service.dispose);

      final stale = table();
      final latest = stale.withCell(
        teamNumber: 254,
        traitKey: 'defense',
        value: 'weak',
        updatedAt: DateTime.utc(2026, 8, 3),
        authorUid: 'uid-1',
        authorDisplayName: 'Dana',
      );

      await expectLater(service.push(stale), throwsA(anything));
      await expectLater(service.push(latest), throwsA(anything));
      expect(patches, 2);
      expect(await queue.pending('traitTables'), {'2026txhou_qm1'});

      failPatches = false;
      await service.watch(eventKey: '2026txhou', matchId: 'qm1');
      await _waitUntil(() => patches >= 3);

      expect(await queue.pending('traitTables'), isEmpty);
      final decoded = fc.FirestoreValueCodec.decodeFields(lastWritten!);
      final cells = decoded['cells'] as Map;
      expect((cells['254'] as Map)['defense'], 'weak');
    });
  });
}
