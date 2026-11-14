import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/services/assistant/remote_assistant_cache.dart';

import 'support/fake_assistant_requests.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const request = AssistantRequest(
    cacheKey: 'team-brief:3847',
    prompt: 'Write a brief.',
    minimumChars: 10,
  );

  AssistantService build({
    required FakeAssistantRequests shared,
    required _FakeRemote remote,
    required _Router router,
    List<AssistantBackend> local = const [],
  }) => AssistantService(
    backends: [...local, router],
    cache: AssistantCache(remote: remote),
    shared: shared,
    minimumGap: Duration.zero,
    sharedWait: const Duration(milliseconds: 300),
    sharedPollEvery: const Duration(milliseconds: 20),
  );

  test('a device with its own model never posts to the queue', () async {
    final shared = FakeAssistantRequests();
    final router = _Router();
    final service = build(
      shared: shared,
      remote: _FakeRemote(),
      router: router,
      local: [_Backend()],
    );

    final summary = await service.generate(request);

    expect(summary.source, AssistantSource.local);
    expect(shared.posted, isEmpty);
    expect(router.calls, 0);
  });

  test(
    'a summary another device publishes is used and the router is not',
    () async {
      final shared = FakeAssistantRequests();
      final remote = _FakeRemote()..answerAfterReads = 2;
      final router = _Router();
      final service = build(shared: shared, remote: remote, router: router);

      final summary = await service.generate(request);

      expect(summary.text, remote.published.text);
      expect(shared.posted, [request.cacheKey]);
      expect(router.calls, 0);
    },
  );

  test('when nobody answers in time the request is withdrawn and the router called', () async {
    final shared = FakeAssistantRequests();
    final router = _Router();
    final service = build(
      shared: shared,
      remote: _FakeRemote(),
      router: router,
    );

    final summary = await service.generate(request);

    expect(summary.source, AssistantSource.openRouter);
    expect(shared.removed, [request.cacheKey]);
    expect(router.calls, 1);
  });

  test('a post that fails skips the wait', () async {
    final shared = FakeAssistantRequests()..postAnswer = false;
    final router = _Router();
    final service = build(
      shared: shared,
      remote: _FakeRemote(),
      router: router,
    );

    final started = DateTime.now();
    await service.generate(request);

    expect(router.calls, 1);
    expect(shared.removed, isEmpty);
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(milliseconds: 250)),
    );
  });

  test('regenerate goes straight to a backend', () async {
    final shared = FakeAssistantRequests();
    final router = _Router();
    final service = build(
      shared: shared,
      remote: _FakeRemote(),
      router: router,
    );

    await service.generate(request, force: true);

    expect(shared.posted, isEmpty);
    expect(router.calls, 1);
  });

  test('a published non-answer keeps the device waiting', () async {
    final shared = FakeAssistantRequests();
    final remote = _FakeRemote()
      ..answerAfterReads = 1
      ..published = _summary('short');
    final router = _Router();
    final service = build(shared: shared, remote: remote, router: router);

    final summary = await service.generate(request);

    expect(summary.source, AssistantSource.openRouter);
    expect(router.calls, 1);
  });
}

AssistantSummary _summary(String text) => AssistantSummary(
  text: text,
  generatedAt: DateTime.utc(2026, 1, 1),
  model: 'qwen',
  source: AssistantSource.local,
);

class _FakeRemote implements RemoteAssistantCache {
  int answerAfterReads = -1;
  int reads = 0;
  AssistantSummary published = _summary('A brief long enough to count.');
  final List<String> written = [];

  @override
  Future<AssistantSummary?> read(String cacheKey) async {
    reads++;
    if (answerAfterReads >= 0 && reads > answerAfterReads) return published;
    return null;
  }

  @override
  Future<void> write(String cacheKey, AssistantSummary summary) async {
    written.add(cacheKey);
  }
}

class _Backend implements AssistantBackend {
  int calls = 0;

  AssistantSource get source => AssistantSource.local;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    calls++;
    return AssistantSummary(
      text: 'An answer long enough to count.',
      generatedAt: DateTime.now().toUtc(),
      model: 'm',
      source: source,
    );
  }
}

class _Router extends _Backend implements RationedAssistantBackend {
  @override
  AssistantSource get source => AssistantSource.openRouter;
}
