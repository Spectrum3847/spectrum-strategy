import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_requests.dart';
import 'package:spectrumstrategy/src/services/assistant/remote_assistant_cache.dart';

void main() {
  test('toJson/fromJson round trip omits null optional fields', () {
    final request = PendingAssistantRequest.fromRequest(
      const AssistantRequest(cacheKey: 'k1', prompt: 'hello'),
      requestedBy: 'uid-1',
      requestedAt: DateTime.utc(2026, 1, 1),
    );

    final json = request.toJson();
    expect(json.containsKey('system'), isFalse);
    expect(json.containsKey('minimumChars'), isFalse);
    expect(json.containsKey('coverage'), isFalse);
    expect(json.containsKey('claimedBy'), isFalse);
    expect(json.containsKey('claimedAt'), isFalse);

    final restored = PendingAssistantRequest.fromJson(json);
    expect(restored.cacheKey, 'k1');
    expect(restored.prompt, 'hello');
    expect(restored.requestedBy, 'uid-1');
    expect(restored.requestedAt, DateTime.utc(2026, 1, 1));
    expect(restored.claimedBy, isNull);
    expect(restored.claimedAt, isNull);
  });

  test('toJson/fromJson round trip keeps claimedAt as a parsed stamp', () {
    final request = PendingAssistantRequest(
      cacheKey: 'k2',
      prompt: 'hi',
      system: 'sys',
      minimumChars: 40,
      coverage: 2,
      requestedBy: 'uid-1',
      requestedAt: DateTime.utc(2026, 2, 1),
      claimedBy: 'uid-2',
      claimedAt: DateTime.utc(2026, 2, 1, 12),
    );

    final restored = PendingAssistantRequest.fromJson(request.toJson());

    expect(restored.system, 'sys');
    expect(restored.minimumChars, 40);
    expect(restored.coverage, 2);
    expect(restored.claimedBy, 'uid-2');
    expect(restored.claimedAt, DateTime.utc(2026, 2, 1, 12));
  });

  test('id is the sha256 hash of the cache key', () {
    final request = PendingAssistantRequest.fromRequest(
      const AssistantRequest(cacheKey: 'team-brief:3847', prompt: 'p'),
      requestedBy: 'uid-1',
      requestedAt: DateTime.utc(2026, 1, 1),
    );

    expect(request.id, assistantCacheDocId('team-brief:3847'));
  });
}
