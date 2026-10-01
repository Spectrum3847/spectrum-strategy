import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_request_worker.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_requests.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/services/assistant/remote_assistant_cache.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

import 'support/fake_assistant_requests.dart';
import 'support/fake_spectrum_auth_service.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  PendingAssistantRequest pending(
    String key, {
    String requestedBy = 'poster-uid',
    Duration age = Duration.zero,
    String? claimedBy,
    Duration claimAge = Duration.zero,
  }) => PendingAssistantRequest(
    cacheKey: key,
    prompt: 'Write a brief.',
    minimumChars: 5,
    requestedBy: requestedBy,
    requestedAt: DateTime.now().toUtc().subtract(age),
    claimedBy: claimedBy,
    claimedAt: claimedBy == null
        ? null
        : DateTime.now().toUtc().subtract(claimAge),
  );

  late FakeAssistantRequests requests;
  late _FakeRemote remote;
  late _LocalBackend backend;
  late AssistantRequestWorker worker;

  setUp(() {
    requests = FakeAssistantRequests();
    remote = _FakeRemote();
    backend = _LocalBackend();
    worker = AssistantRequestWorker(
      requests: requests,
      assistant: AssistantService(
        backends: [backend],
        cache: AssistantCache(remote: remote),
      ),
      authService: FakeSpectrumAuthService(
        initialUser: const SpectrumUser(
          uid: 'worker-uid',
          displayName: 'Worker',
          email: 'w@example.com',
        ),
      ),
    );
  });

  test('claims, publishes, and removes an open request', () async {
    requests.queue['k1'] = pending('k1');

    await worker.tick();

    expect(requests.claimed, ['k1']);
    expect(remote.written, ['k1']);
    expect(requests.removed, ['k1']);
    expect(backend.calls, 1);
  });

  test('leaves alone its own, freshly claimed, and expired requests', () async {
    requests.queue['mine'] = pending('mine', requestedBy: 'worker-uid');
    requests.queue['taken'] = pending('taken', claimedBy: 'other-uid');
    requests.queue['old'] = pending('old', age: const Duration(minutes: 11));

    await worker.tick();

    expect(requests.claimed, isEmpty);
    expect(backend.calls, 0);
  });

  test('takes over a claim that went stale', () async {
    requests.queue['k'] = pending(
      'k',
      claimedBy: 'other-uid',
      claimAge: const Duration(minutes: 4),
    );

    await worker.tick();

    expect(requests.removed, ['k']);
  });

  test('does nothing while the model is not ready', () async {
    backend.available = false;
    requests.queue['k'] = pending('k');

    await worker.tick();

    expect(requests.claimed, isEmpty);
  });

  test('a failed generation leaves the request for someone else', () async {
    backend.fail = true;
    requests.queue['k'] = pending('k');

    await worker.tick();

    expect(requests.claimed, ['k']);
    expect(requests.removed, isEmpty);
    expect(requests.queue['k']!.claimedBy, 'worker-uid');
  });

  test('a lost claim is not generated', () async {
    requests.claimAnswer = false;
    requests.queue['k'] = pending('k');

    await worker.tick();

    expect(backend.calls, 0);
  });
}

class _LocalBackend implements AssistantBackend {
  bool available = true;
  bool fail = false;
  int calls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    calls++;
    if (fail) throw const AssistantUnavailable('model crashed');
    return AssistantSummary(
      text: 'A brief written on this device.',
      generatedAt: DateTime.now().toUtc(),
      model: 'qwen',
      source: AssistantSource.local,
    );
  }
}

class _FakeRemote implements RemoteAssistantCache {
  final List<String> written = [];

  @override
  Future<AssistantSummary?> read(String cacheKey) async => null;

  @override
  Future<void> write(String cacheKey, AssistantSummary summary) async {
    written.add(cacheKey);
  }
}
