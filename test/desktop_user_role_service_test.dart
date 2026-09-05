import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/services/desktop_user_role_service.dart';

fc.Firestore _firestore(MockClient client, {String? token = 'tok'}) =>
    fc.Firestore(
      projectId: 'demo',
      idTokenProvider: () async => token,
      httpClient: client,
    );

String _profileDoc(String uid, List<String> roles) => jsonEncode({
  'name': 'projects/demo/databases/(default)/documents/userProfiles/$uid',
  'fields': fc.FirestoreValueCodec.encodeFields(<String, dynamic>{
    'uid': uid,
    'displayName': 'User $uid',
    'roles': roles,
  }),
});

void main() {
  group('fetchOrCreateProfile', () {
    test('reads an existing profile', () async {
      final service = DesktopUserRoleService(
        firestore: _firestore(
          MockClient(
            (_) async => http.Response(_profileDoc('u1', ['strategy']), 200),
          ),
        ),
      );
      expect((await service.fetchOrCreateProfile(uid: 'u1')).roles, {
        UserRole.strategy,
      });
    });

    test('creates a scouter profile on first sign-in (404)', () async {
      var createCalled = false;
      final service = DesktopUserRoleService(
        firestore: _firestore(
          MockClient((request) async {
            if (request.method == 'GET') {
              return http.Response('not found', 404);
            }
            createCalled = true;
            expect(request.url.queryParameters['documentId'], 'u1');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final fields = (body['fields'] as Map).cast<String, dynamic>();
            expect(
              fc.FirestoreValueCodec.decode(
                (fields['roles'] as Map).cast<String, dynamic>(),
              ),
              ['scouter'],
            );
            return http.Response(_profileDoc('u1', ['scouter']), 200);
          }),
        ),
      );
      final profile = await service.fetchOrCreateProfile(
        uid: 'u1',
        displayName: 'D',
      );
      expect(profile.roles, {UserRole.scouter});
      expect(createCalled, isTrue);
    });

    test('resolves viewer on any error (denied/offline)', () async {
      final service = DesktopUserRoleService(
        firestore: _firestore(
          MockClient((_) async => http.Response('denied', 403)),
        ),
      );
      expect((await service.fetchOrCreateProfile(uid: 'u1')).roles, {
        UserRole.viewer,
      });
    });
  });

  test('updateRoles patches only the roles field', () async {
    late Uri captured;
    final service = DesktopUserRoleService(
      firestore: _firestore(
        MockClient((request) async {
          captured = request.url;
          expect(request.method, 'PATCH');
          return http.Response(_profileDoc('u2', ['scouter']), 200);
        }),
      ),
    );
    await service.updateRoles('u2', {UserRole.scouter});
    expect(captured.path, endsWith('userProfiles/u2'));
    expect(captured.query, contains('updateMask.fieldPaths=roles'));
  });

  test('streamAllProfiles polls and emits the sorted roster', () async {
    final service = DesktopUserRoleService(
      pollInterval: const Duration(milliseconds: 5),
      firestore: _firestore(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'documents': [
                jsonDecode(_profileDoc('u2', ['scouter'])),
                jsonDecode(_profileDoc('u1', ['admin'])),
              ],
            }),
            200,
          ),
        ),
      ),
    );
    final roster = await service.streamAllProfiles().first;
    expect(roster.map((p) => p.uid), ['u1', 'u2']);
    expect(roster.first.roles, {UserRole.admin});
  });

  test('streamAllProfiles errors when the first poll fails', () async {
    final service = DesktopUserRoleService(
      pollInterval: const Duration(milliseconds: 5),
      firestore: _firestore(
        MockClient((_) async => http.Response('denied', 403)),
      ),
    );
    await expectLater(service.streamAllProfiles().first, throwsA(anything));
  });

  test(
    'a failed poll after a successful emit keeps the stream alive',
    () async {
      var calls = 0;
      final service = DesktopUserRoleService(
        pollInterval: const Duration(milliseconds: 5),
        firestore: _firestore(
          MockClient((_) async {
            calls++;
            if (calls == 2) {
              return http.Response('temporarily unavailable', 503);
            }
            final docs = calls == 1
                ? [
                    jsonDecode(_profileDoc('u1', ['admin'])),
                  ]
                : [
                    jsonDecode(_profileDoc('u1', ['admin'])),
                    jsonDecode(_profileDoc('u2', ['scouter'])),
                  ];
            return http.Response(jsonEncode({'documents': docs}), 200);
          }),
        ),
      );

      final rosters = await service.streamAllProfiles().take(2).toList();
      expect(rosters.first.map((p) => p.uid), ['u1']);
      expect(rosters.last.map((p) => p.uid), ['u1', 'u2']);
      expect(calls, greaterThanOrEqualTo(3));
    },
  );

  test('linkAccount points the secondary at the primary', () async {
    final requests = <Map<String, Object?>>[];
    final service = DesktopUserRoleService(
      firestore: _firestore(
        MockClient((request) async {
          requests.add({
            'method': request.method,
            'path': request.url.path,
            'query': request.url.query,
            'body': jsonDecode(request.body),
          });
          return http.Response(_profileDoc('second', ['strategy']), 200);
        }),
      ),
    );

    await service.linkAccount(
      secondaryUid: 'second',
      primaryUid: 'primary',
      secondaryEmail: 'dana@school.edu',
      roles: {UserRole.strategy},
    );

    expect(requests, hasLength(2));
    expect(requests.first['path'], endsWith('userProfiles/second'));
    expect(requests.first['query'], contains('canonicalUid'));

    expect(requests.last['path'], endsWith('documents:commit'));
    expect(
      jsonEncode(requests.last['body']),
      contains('appendMissingElements'),
    );
  });

  test('unlinkAccount clears canonicalUid and the primary entry', () async {
    final requests = <Map<String, Object?>>[];
    final service = DesktopUserRoleService(
      firestore: _firestore(
        MockClient((request) async {
          requests.add({
            'path': request.url.path,
            'query': request.url.query,
            'body': jsonDecode(request.body),
          });
          return http.Response(_profileDoc('second', ['viewer']), 200);
        }),
      ),
    );

    await service.unlinkAccount(
      secondaryUid: 'second',
      primaryUid: 'primary',
      secondaryEmail: 'dana@school.edu',
    );

    expect(requests.first['query'], contains('canonicalUid'));
    expect(
      jsonEncode((requests.first['body'] as Map)['fields']),
      isNot(contains('canonicalUid')),
    );
    expect(requests.last['path'], endsWith('documents:commit'));
    expect(jsonEncode(requests.last['body']), contains('removeAllFromArray'));
  });
}
