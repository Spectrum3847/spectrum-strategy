import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/firestore_remote_assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/remote_assistant_cache.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

import 'support/fake_spectrum_auth_service.dart';

class _FakeRemoteAssistantCache implements RemoteAssistantCache {
  AssistantSummary? readAnswer;
  Object? readError;
  Object? writeError;

  int readCalls = 0;
  final List<String> writtenKeys = [];
  final List<AssistantSummary> writtenSummaries = [];

  @override
  Future<AssistantSummary?> read(String cacheKey) async {
    readCalls++;
    if (readError != null) throw readError!;
    return readAnswer;
  }

  @override
  Future<void> write(String cacheKey, AssistantSummary summary) async {
    if (writeError != null) throw writeError!;
    writtenKeys.add(cacheKey);
    writtenSummaries.add(summary);
  }
}

AssistantSummary _summary(String text) => AssistantSummary(
  text: text,
  generatedAt: DateTime.utc(2026, 1, 1),
  model: 'test-model',
  source: AssistantSource.openRouter,
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('a local hit never touches the remote', () async {
    final remote = _FakeRemoteAssistantCache();
    final cache = AssistantCache(remote: remote);
    await cache.write('key', _summary('local'));

    final result = await cache.read('key');

    expect(result?.text, 'local');
    expect(remote.readCalls, 0);
  });

  test('a local miss served from the remote is mirrored locally', () async {
    final remote = _FakeRemoteAssistantCache()
      ..readAnswer = _summary('from-remote');
    final cache = AssistantCache(remote: remote);

    final first = await cache.read('key');
    expect(first?.text, 'from-remote');
    expect(remote.readCalls, 1);

    final second = await cache.read('key');
    expect(second?.text, 'from-remote');
    expect(remote.readCalls, 1);
  });

  test('a remote failure degrades to a local miss without throwing', () async {
    final remote = _FakeRemoteAssistantCache()
      ..readError = StateError('offline');
    final cache = AssistantCache(remote: remote);

    final result = await cache.read('key');

    expect(result, isNull);
  });

  test('no remote configured is a plain local cache', () async {
    final cache = AssistantCache();

    expect(await cache.read('key'), isNull);
    await cache.write('key', _summary('local-only'));
    expect((await cache.read('key'))?.text, 'local-only');
  });

  test('a write reaches both local and remote', () async {
    final remote = _FakeRemoteAssistantCache();
    final cache = AssistantCache(remote: remote);

    await cache.write('key', _summary('shared'));

    expect((await cache.read('key'))?.text, 'shared');
    expect(remote.writtenKeys, ['key']);
    expect(remote.writtenSummaries.single.text, 'shared');
  });

  test('a write survives a remote failure', () async {
    final remote = _FakeRemoteAssistantCache()
      ..writeError = StateError('offline');
    final cache = AssistantCache(remote: remote);

    await cache.write('key', _summary('still-local'));

    expect((await cache.read('key'))?.text, 'still-local');
  });

  group('FirestoreRemoteAssistantCache', () {
    test('a write with no signed-in user stays local-only', () async {
      final firestore = FakeFirebaseFirestore();
      final remote = FirestoreRemoteAssistantCache(
        authService: FakeSpectrumAuthService(),
        firestore: firestore,
      );

      await remote.write('key', _summary('unsigned'));

      final docs = await firestore
          .collection(FirestoreRemoteAssistantCache.collection)
          .get();
      expect(docs.docs, isEmpty);
    });

    test('a signed-in write lands under the sha256 doc id', () async {
      final firestore = FakeFirebaseFirestore();
      final remote = FirestoreRemoteAssistantCache(
        authService: FakeSpectrumAuthService(
          initialUser: const SpectrumUser(
            uid: 'uid-1',
            displayName: 'Test User',
          ),
        ),
        firestore: firestore,
      );

      await remote.write('team-brief:3847', _summary('shared'));

      final doc = await firestore
          .collection(FirestoreRemoteAssistantCache.collection)
          .doc(assistantCacheDocId('team-brief:3847'))
          .get();
      expect(doc.data()?['authorUid'], 'uid-1');
      expect(doc.data()?['cacheKey'], 'team-brief:3847');

      final read = await remote.read('team-brief:3847');
      expect(read?.text, 'shared');
    });
  });

  test('assistantCacheDocId is a stable sha256 hex hash', () {
    final id = assistantCacheDocId('team-brief:3847:2026txhou');

    expect(id, assistantCacheDocId('team-brief:3847:2026txhou'));
    expect(id.length, 64);
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(id), isTrue);
  });
}
