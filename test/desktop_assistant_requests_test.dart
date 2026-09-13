import 'dart:convert';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_requests.dart';
import 'package:spectrumstrategy/src/services/assistant/desktop_assistant_requests.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

import 'support/fake_spectrum_auth_service.dart';

const AssistantRequest _request = AssistantRequest(
  cacheKey: 'team-brief:3847',
  prompt: 'Summarize team 3847.',
);

fc.Firestore _firestore(MockClient client) => fc.Firestore(
  projectId: 'demo',
  idTokenProvider: () async => 'tok',
  httpClient: client,
);

FakeSpectrumAuthService _signedInAuth() => FakeSpectrumAuthService(
  initialUser: const SpectrumUser(uid: 'uid-1', displayName: 'Dana'),
);

String _docJson(PendingAssistantRequest request) => jsonEncode({
  'name':
      'projects/demo/databases/(default)/documents/'
      '${DesktopAssistantRequests.collection}/${request.id}',
  'fields': fc.FirestoreValueCodec.encodeFields(request.toJson()),
});

void main() {
  test('post sends the write and returns true', () async {
    http.Request? sent;
    final requests = DesktopAssistantRequests(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'name':
                  'projects/demo/databases/(default)/documents/'
                  '${DesktopAssistantRequests.collection}/x',
              'fields': <String, dynamic>{},
            }),
            200,
          );
        }),
      ),
    );

    final ok = await requests.post(_request);

    expect(ok, isTrue);
    expect(sent, isNotNull);
    expect(sent!.method, 'PATCH');
    final body = jsonDecode(sent!.body) as Map<String, dynamic>;
    final fields = (body['fields'] as Map).cast<String, dynamic>();
    expect(fields.keys, contains('cacheKey'));
    expect(fields.keys, contains('requestedBy'));
  });

  test('a 403 on post returns false', () async {
    final requests = DesktopAssistantRequests(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((_) async => http.Response('{"error":{}}', 403)),
      ),
    );

    final ok = await requests.post(_request);

    expect(ok, isFalse);
  });

  test('open decodes a runQuery response, skipping cached docs', () async {
    final pending = PendingAssistantRequest.fromRequest(
      _request,
      requestedBy: 'uid-1',
      requestedAt: DateTime.utc(2026, 1, 1),
    );
    final requests = DesktopAssistantRequests(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          expect(request.url.path, endsWith(':runQuery'));
          return http.Response(
            jsonEncode([
              {'document': jsonDecode(_docJson(pending))},
            ]),
            200,
          );
        }),
      ),
    );

    final open = await requests.open();

    expect(open.length, 1);
    expect(open.single.cacheKey, _request.cacheKey);
  });

  test('open returns empty on a 500', () async {
    final requests = DesktopAssistantRequests(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((_) async => http.Response('{"error":{}}', 500)),
      ),
    );

    final open = await requests.open();

    expect(open, isEmpty);
  });

  test('claim sends an update mask with only the two fields', () async {
    final pending = PendingAssistantRequest.fromRequest(
      _request,
      requestedBy: 'uid-1',
      requestedAt: DateTime.utc(2026, 1, 1),
    );
    http.Request? sent;
    final requests = DesktopAssistantRequests(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'writeResults': []}), 200);
        }),
      ),
    );

    final ok = await requests.claim(pending);

    expect(ok, isTrue);
    expect(sent, isNotNull);
    final body = jsonDecode(sent!.body) as Map<String, dynamic>;
    final write = (body['writes'] as List).single as Map<String, dynamic>;
    final mask = (write['updateMask']['fieldPaths'] as List).cast<String>();
    expect(mask.toSet(), {'claimedBy', 'claimedAt'});
    expect(write['currentDocument'], {'exists': true});
  });

  test('remove issues a delete and swallows a failure', () async {
    final pending = PendingAssistantRequest.fromRequest(
      _request,
      requestedBy: 'uid-1',
      requestedAt: DateTime.utc(2026, 1, 1),
    );
    var deleteCalls = 0;
    final requests = DesktopAssistantRequests(
      authService: _signedInAuth(),
      firestore: _firestore(
        MockClient((request) async {
          expect(request.method, 'DELETE');
          deleteCalls++;
          return http.Response('{"error":{}}', 500);
        }),
      ),
    );

    await requests.remove(pending.cacheKey);

    expect(deleteCalls, 1);
  });
}
