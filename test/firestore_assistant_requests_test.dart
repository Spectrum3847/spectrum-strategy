import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_requests.dart';
import 'package:spectrumstrategy/src/services/assistant/remote_assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/firestore_assistant_requests.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

import 'support/fake_spectrum_auth_service.dart';

const AssistantRequest _request = AssistantRequest(
  cacheKey: 'team-brief:3847',
  prompt: 'Summarize team 3847.',
);

FirestoreAssistantRequests _signedIn(FakeFirebaseFirestore firestore) =>
    FirestoreAssistantRequests(
      authService: FakeSpectrumAuthService(
        initialUser: const SpectrumUser(uid: 'uid-1', displayName: 'Dana'),
      ),
      firestore: firestore,
    );

void main() {
  test(
    'post writes exactly toJson under the hashed id and returns true',
    () async {
      final firestore = FakeFirebaseFirestore();
      final requests = _signedIn(firestore);

      final ok = await requests.post(_request);

      expect(ok, isTrue);
      final doc = await firestore
          .collection(FirestoreAssistantRequests.collection)
          .doc(assistantCacheDocId(_request.cacheKey))
          .get();
      expect(doc.exists, isTrue);
      final expected = PendingAssistantRequest.fromRequest(
        _request,
        requestedBy: 'uid-1',
        requestedAt: DateTime.now().toUtc(),
      ).toJson();
      final data = doc.data()!;
      expect(data['cacheKey'], expected['cacheKey']);
      expect(data['prompt'], expected['prompt']);
      expect(data['requestedBy'], expected['requestedBy']);
      expect(data.keys.toSet(), {
        'cacheKey',
        'prompt',
        'requestedBy',
        'requestedAt',
      });
    },
  );

  test(
    'post with no signed-in user returns false and writes nothing',
    () async {
      final firestore = FakeFirebaseFirestore();
      final requests = FirestoreAssistantRequests(
        authService: FakeSpectrumAuthService(),
        firestore: firestore,
      );

      final ok = await requests.post(_request);

      expect(ok, isFalse);
      final docs = await firestore
          .collection(FirestoreAssistantRequests.collection)
          .get();
      expect(docs.docs, isEmpty);
    },
  );

  test('open lists and maps requests, skipping a malformed doc', () async {
    final firestore = FakeFirebaseFirestore();
    final requests = _signedIn(firestore);
    await requests.post(_request);
    await firestore
        .collection(FirestoreAssistantRequests.collection)
        .doc('malformed')
        .set({'cacheKey': '', 'prompt': ''});

    final open = await requests.open();

    expect(open.length, 1);
    expect(open.single.cacheKey, _request.cacheKey);
  });

  test('claim sets only claimedBy/claimedAt', () async {
    final firestore = FakeFirebaseFirestore();
    final requests = _signedIn(firestore);
    await requests.post(_request);
    final pending = (await requests.open()).single;

    final ok = await requests.claim(pending);

    expect(ok, isTrue);
    final doc = await firestore
        .collection(FirestoreAssistantRequests.collection)
        .doc(pending.id)
        .get();
    final data = doc.data()!;
    expect(data['claimedBy'], 'uid-1');
    expect(data['claimedAt'], isA<String>());
    expect(data['cacheKey'], _request.cacheKey);
    expect(data['prompt'], _request.prompt);
  });

  test('remove deletes the document', () async {
    final firestore = FakeFirebaseFirestore();
    final requests = _signedIn(firestore);
    await requests.post(_request);
    final pending = (await requests.open()).single;

    await requests.remove(pending.cacheKey);

    final doc = await firestore
        .collection(FirestoreAssistantRequests.collection)
        .doc(pending.id)
        .get();
    expect(doc.exists, isFalse);
  });
}
