import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/services/assistant/firestore_assistant_config.dart';
import 'package:spectrumstrategy/src/services/assistant/local_assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/openrouter_assistant_backend.dart';
import 'package:spectrumstrategy/src/services/llama_runtime_service.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('key resolution', () {
    test('the team key wins over the compile-time key', () async {
      final config = FirestoreAssistantConfig(
        remoteFetcher: () async => 'team-key',
        fallbackKey: 'compile-time',
      );

      expect(await config.resolveApiKey(), 'team-key');
    });

    test('a fetched key is mirrored so it survives going offline', () async {
      final config = FirestoreAssistantConfig(
        remoteFetcher: () async => '  team-key  ',
      );

      expect(await config.teamKey(), 'team-key');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(FirestoreAssistantConfig.prefsKey), 'team-key');
    });

    test('a fetch failure falls back to the mirror', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        FirestoreAssistantConfig.prefsKey: 'mirrored',
      });
      final config = FirestoreAssistantConfig(
        remoteFetcher: () async => throw StateError('signed out'),
        fallbackKey: 'compile-time',
      );

      expect(await config.resolveApiKey(), 'mirrored');
    });

    test('an admin clearing the key clears the mirror too', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        FirestoreAssistantConfig.prefsKey: 'mirrored',
      });
      final config = FirestoreAssistantConfig(remoteFetcher: () async => '');

      expect(await config.teamKey(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(FirestoreAssistantConfig.prefsKey), isNull);
    });

    test('no key anywhere resolves to null', () async {
      final config = FirestoreAssistantConfig(remoteFetcher: () async => null);

      expect(await config.resolveApiKey(), isNull);
    });
  });

  group('OpenRouter backend', () {
    test('sends the router alias and the team key', () async {
      late http.Request sent;
      final backend = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
        client: MockClient((request) async {
          sent = request;
          return http.Response(_completion('a summary'), 200);
        }),
      );

      final summary = await backend.complete(
        const AssistantRequest(
          cacheKey: 'digest:3847',
          prompt: 'summarise',
          system: 'be terse',
        ),
      );

      expect(sent.headers['Authorization'], 'Bearer k');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['model'], 'openrouter/free');
      expect((body['messages'] as List).first['role'], 'system');
      expect(summary.text, 'a summary');
      expect(summary.source, AssistantSource.openRouter);
    });

    test('stamps the backing model the router actually landed on', () async {
      final backend = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
        client: MockClient(
          (_) async => http.Response(
            _completion('text', model: 'some-vendor/some-model:free'),
            200,
          ),
        ),
      );

      final summary = await backend.complete(_request);

      expect(summary.model, 'some-vendor/some-model:free');
    });

    test('omits the system message when there is none', () async {
      late http.Request sent;
      final backend = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
        client: MockClient((request) async {
          sent = request;
          return http.Response(_completion('text'), 200);
        }),
      );

      await backend.complete(_request);

      final messages = jsonDecode(sent.body)['messages'] as List;
      expect(messages, hasLength(1));
      expect(messages.single['role'], 'user');
    });

    test('prepends history turns before the final prompt', () async {
      late http.Request sent;
      final backend = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
        client: MockClient((request) async {
          sent = request;
          return http.Response(_completion('follow up'), 200);
        }),
      );

      await backend.complete(
        const AssistantRequest(
          cacheKey: 'k',
          prompt: 'and the counter?',
          history: [
            AssistantTurn(role: AssistantTurnRole.user, content: 'pick 254'),
            AssistantTurn(
              role: AssistantTurnRole.assistant,
              content: '254 it is.',
            ),
          ],
        ),
      );

      final messages = jsonDecode(sent.body)['messages'] as List;
      expect(messages, [
        {'role': 'user', 'content': 'pick 254'},
        {'role': 'assistant', 'content': '254 it is.'},
        {'role': 'user', 'content': 'and the counter?'},
      ]);
    });

    test('retries a rate limit once, then succeeds', () async {
      var calls = 0;
      final backend = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('rate limited', 429)
              : http.Response(_completion('second try'), 200);
        }),
      );

      expect((await backend.complete(_request)).text, 'second try');
      expect(calls, 2);
    });

    test('retries an answer too short to be an answer', () async {
      var calls = 0;
      final backend = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response(
                  _completion(
                    'User Safety: safe',
                    model: 'nvidia/nemotron-3.5-content-safety:free',
                  ),
                  200,
                )
              : http.Response(_completion('a' * 120), 200);
        }),
      );

      final summary = await backend.complete(
        const AssistantRequest(
          cacheKey: 'brief:3847',
          prompt: 'write a brief',
          minimumChars: 80,
        ),
      );

      expect(summary.text, 'a' * 120);
      expect(calls, 2);
    });

    test('gives up on a short answer after maxAttempts', () async {
      var calls = 0;
      final backend = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          calls++;
          return http.Response(_completion('User Safety: safe'), 200);
        }),
      );

      await expectLater(
        backend.complete(
          const AssistantRequest(
            cacheKey: 'brief:3847',
            prompt: 'write a brief',
            minimumChars: 80,
          ),
        ),
        throwsA(
          isA<AssistantUnavailable>().having(
            (e) => e.reason,
            'reason',
            allOf(
              contains('too short'),
              contains('17 characters'),
              contains('expected at least 80'),
            ),
          ),
        ),
      );

      expect(calls, backend.maxAttempts);
    });

    test('a short answer is accepted when the feature sets no floor', () async {
      var calls = 0;
      final backend = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          calls++;
          return http.Response(_completion('short'), 200);
        }),
      );

      expect((await backend.complete(_request)).text, 'short');
      expect(calls, 1);
    });

    test('an answer exactly at the floor is accepted', () async {
      var calls = 0;
      final backend = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          calls++;
          return http.Response(_completion('a' * 80), 200);
        }),
      );

      final summary = await backend.complete(
        const AssistantRequest(cacheKey: 'k', prompt: 'p', minimumChars: 80),
      );

      expect(summary.text.length, 80);
      expect(calls, 1);
    });

    test(
      'does not retry a bad key, which would spend another request',
      () async {
        var calls = 0;
        final backend = OpenRouterAssistantBackend(
          config: FirestoreAssistantConfig(remoteFetcher: () async => 'bad'),
          retryDelay: Duration.zero,
          client: MockClient((_) async {
            calls++;
            return http.Response('no', 401);
          }),
        );

        await expectLater(
          backend.complete(_request),
          throwsA(isA<AssistantUnavailable>()),
        );
        expect(calls, 1);
      },
    );

    test('an upstream failure inside a 200 is still a failure', () async {
      final backend = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
        retryDelay: Duration.zero,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'message': 'upstream model is down'},
            }),
            200,
          ),
        ),
      );

      await expectLater(
        backend.complete(_request),
        throwsA(
          isA<AssistantUnavailable>().having(
            (e) => e.reason,
            'reason',
            contains('upstream model is down'),
          ),
        ),
      );
    });

    test('a transport failure reads as unavailable, not as a crash', () async {
      var calls = 0;
      final backend = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          calls++;
          throw const SocketException('Connection refused');
        }),
      );

      await expectLater(
        backend.complete(_request),
        throwsA(
          isA<AssistantUnavailable>().having(
            (e) => e.reason,
            'reason',
            contains('Could not reach OpenRouter'),
          ),
        ),
      );
      expect(
        calls,
        backend.maxAttempts,
        reason: 'every retryable failure gets maxAttempts tries',
      );
    });

    test(
      'a transport failure that clears on the retry still answers',
      () async {
        var calls = 0;
        final backend = OpenRouterAssistantBackend(
          config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
          retryDelay: Duration.zero,
          client: MockClient((_) async {
            calls++;
            if (calls == 1) {
              throw const SocketException('Network is unreachable');
            }
            return http.Response(_completion('came back'), 200);
          }),
        );

        expect((await backend.complete(_request)).text, 'came back');
      },
    );

    test('is unavailable with no key, and does not call out', () async {
      var called = false;
      final backend = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => null),
        client: MockClient((_) async {
          called = true;
          return http.Response('', 200);
        }),
      );

      expect(await backend.isAvailable(), isFalse);
      await expectLater(
        backend.complete(_request),
        throwsA(isA<AssistantUnavailable>()),
      );
      expect(called, isFalse);
    });
  });

  group('looksLikeAnAnswer', () {
    test('accepts normal prose', () {
      expect(
        looksLikeAnAnswer('This team scores well from the far side.'),
        isTrue,
      );
    });

    test('rejects empty and whitespace-only text', () {
      expect(looksLikeAnAnswer(''), isFalse);
      expect(looksLikeAnAnswer('   \n  '), isFalse);
    });

    test('rejects text shorter than the floor', () {
      expect(looksLikeAnAnswer('too short', minimumChars: 80), isFalse);
    });

    test('accepts text exactly at the floor', () {
      expect(looksLikeAnAnswer('a' * 80, minimumChars: 80), isTrue);
    });

    test('accepts anything non-empty when there is no floor', () {
      expect(looksLikeAnAnswer('ok'), isTrue);
    });

    test('rejects each non-answer opening', () {
      expect(looksLikeAnAnswer('User Safety: safe'), isFalse);
      expect(looksLikeAnAnswer("I can't help with that request."), isFalse);
      expect(looksLikeAnAnswer('As an AI, I do not have opinions.'), isFalse);
    });

    test('is case-insensitive', () {
      expect(looksLikeAnAnswer('USER SAFETY: safe'), isFalse);
      expect(looksLikeAnAnswer('i AM sorry, I cannot do that'), isFalse);
    });

    test(
      'accepts text that merely contains a non-answer phrase mid-sentence',
      () {
        expect(
          looksLikeAnAnswer(
            'This team plays it safe. As an AI referee would score it, this '
            'is a legal defense.',
          ),
          isTrue,
        );
      },
    );
  });

  group('cache', () {
    test('a summary survives a round trip', () async {
      final cache = AssistantCache();
      final summary = AssistantSummary(
        text: 'kept',
        generatedAt: DateTime.utc(2026, 8, 14, 12),
        model: 'm',
        source: AssistantSource.openRouter,
      );

      await cache.write('k', summary);

      final read = await cache.read('k');
      expect(read?.text, 'kept');
      expect(read?.generatedAt, DateTime.utc(2026, 8, 14, 12));
      expect(read?.source, AssistantSource.openRouter);
    });

    test('evicts the oldest entries past the bound', () async {
      final cache = AssistantCache();
      for (var i = 0; i <= AssistantCache.maxEntries; i++) {
        await cache.write(
          'k$i',
          AssistantSummary(
            text: '$i',
            generatedAt: DateTime.utc(2026).add(Duration(minutes: i)),
            model: 'm',
            source: AssistantSource.openRouter,
          ),
        );
      }

      expect(await cache.read('k0'), isNull);
      expect(
        (await cache.read('k${AssistantCache.maxEntries}'))?.text,
        '${AssistantCache.maxEntries}',
      );
    });

    test('a corrupt cache starts over instead of failing every read', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AssistantCache.prefsKey: 'not json',
      });

      expect(await AssistantCache().read('k'), isNull);
    });
  });

  group('service', () {
    test('peek never calls a backend', () async {
      final backend = _RecordingBackend();
      final service = AssistantService(
        backends: [backend],
        cache: AssistantCache(),
      );

      expect(await service.peek(_request), isNull);
      expect(backend.calls, 0);
    });

    test('a second generate is served from the cache', () async {
      final backend = _RecordingBackend();
      final service = AssistantService(
        backends: [backend],
        cache: AssistantCache(),
        minimumGap: Duration.zero,
      );

      expect((await service.generate(_request)).text, 'answer 1');
      expect((await service.generate(_request)).text, 'answer 1');
      expect(backend.calls, 1);
    });

    test('force regenerates and overwrites the cache', () async {
      final backend = _RecordingBackend();
      final service = AssistantService(
        backends: [backend],
        cache: AssistantCache(),
        minimumGap: Duration.zero,
      );

      await service.generate(_request);
      expect((await service.generate(_request, force: true)).text, 'answer 2');
      expect((await service.peek(_request))?.text, 'answer 2');
      expect(backend.calls, 2);
    });

    test(
      'peek returns null for a cached summary that fails the check',
      () async {
        final cache = AssistantCache();
        await cache.write(
          _request.cacheKey,
          AssistantSummary(
            text: 'User Safety: safe',
            generatedAt: DateTime.now().toUtc(),
            model: 'm',
            source: AssistantSource.openRouter,
          ),
        );
        final service = AssistantService(
          backends: [_RecordingBackend()],
          cache: cache,
        );

        expect(await service.peek(_request), isNull);
      },
    );

    test('peek returns a cached summary that passes the check', () async {
      final cache = AssistantCache();
      await cache.write(
        _request.cacheKey,
        AssistantSummary(
          text: 'a real summary',
          generatedAt: DateTime.now().toUtc(),
          model: 'm',
          source: AssistantSource.openRouter,
        ),
      );
      final service = AssistantService(
        backends: [_RecordingBackend()],
        cache: cache,
      );

      expect((await service.peek(_request))?.text, 'a real summary');
    });

    test(
      'generate regenerates over a cached summary that fails the check',
      () async {
        final backend = _RecordingBackend();
        final cache = AssistantCache();
        await cache.write(
          _request.cacheKey,
          AssistantSummary(
            text: 'User Safety: safe',
            generatedAt: DateTime.now().toUtc(),
            model: 'old-model',
            source: AssistantSource.openRouter,
          ),
        );
        final service = AssistantService(
          backends: [backend],
          cache: cache,
          minimumGap: Duration.zero,
        );

        final summary = await service.generate(_request);

        expect(backend.calls, 1);
        expect(summary.text, 'answer 1');
      },
    );

    test('generate does not regenerate over a cached good summary', () async {
      final backend = _RecordingBackend();
      final cache = AssistantCache();
      await cache.write(
        _request.cacheKey,
        AssistantSummary(
          text: 'a real summary',
          generatedAt: DateTime.now().toUtc(),
          model: 'old-model',
          source: AssistantSource.openRouter,
        ),
      );
      final service = AssistantService(
        backends: [backend],
        cache: cache,
        minimumGap: Duration.zero,
      );

      final summary = await service.generate(_request);

      expect(backend.calls, 0);
      expect(summary.text, 'a real summary');
    });

    test(
      'falls through to the next backend when the first is unavailable',
      () async {
        final offline = _RecordingBackend(available: false);
        final local = _RecordingBackend(source: AssistantSource.local);
        final service = AssistantService(
          backends: [offline, local],
          cache: AssistantCache(),
          minimumGap: Duration.zero,
        );

        final summary = await service.generate(_request);

        expect(summary.source, AssistantSource.local);
        expect(offline.calls, 0);
        expect(local.calls, 1);
      },
    );

    test('falls through when the first backend throws', () async {
      final failing = _RecordingBackend(failWith: 'router is down');
      final local = _RecordingBackend(source: AssistantSource.local);
      final service = AssistantService(
        backends: [failing, local],
        cache: AssistantCache(),
        minimumGap: Duration.zero,
      );

      expect((await service.generate(_request)).source, AssistantSource.local);
      expect(failing.calls, 1);
    });

    test(
      'a backend throwing something unexpected does not crash the chain',
      () async {
        final rogue = _ThrowingBackend();
        final local = _RecordingBackend(source: AssistantSource.local);
        final service = AssistantService(
          backends: [rogue, local],
          cache: AssistantCache(),
          minimumGap: Duration.zero,
        );

        expect(
          (await service.generate(_request)).source,
          AssistantSource.local,
        );
      },
    );

    test('reports every failure when no backend answers', () async {
      final service = AssistantService(
        backends: [_RecordingBackend(failWith: 'router is down')],
        cache: AssistantCache(),
        minimumGap: Duration.zero,
      );

      await expectLater(
        service.generate(_request),
        throwsA(
          isA<AssistantUnavailable>().having(
            (e) => e.reason,
            'reason',
            contains('router is down'),
          ),
        ),
      );
    });

    test('a failed call does not stall every later one', () async {
      final backend = _RecordingBackend(failWith: 'once');
      final service = AssistantService(
        backends: [backend],
        cache: AssistantCache(),
        minimumGap: Duration.zero,
      );

      await expectLater(
        service.generate(_request),
        throwsA(isA<AssistantUnavailable>()),
      );

      backend.failWith = null;
      expect((await service.generate(_request)).text, 'answer 2');
    });

    test('paces concurrent calls instead of firing them together', () async {
      final backend = _RecordingBackend();
      final service = AssistantService(
        backends: [backend],
        cache: AssistantCache(),
        minimumGap: const Duration(milliseconds: 120),
      );

      final started = DateTime.now();
      await Future.wait([
        service.generate(const AssistantRequest(cacheKey: 'a', prompt: 'p')),
        service.generate(const AssistantRequest(cacheKey: 'b', prompt: 'p')),
      ]);

      expect(backend.calls, 2);
      expect(
        DateTime.now().difference(started),
        greaterThanOrEqualTo(const Duration(milliseconds: 100)),
      );
    });

    test('a summary survives a cache that cannot be written', () async {
      final service = AssistantService(
        backends: [_RecordingBackend()],
        cache: _BrokenCache(),
        minimumGap: Duration.zero,
      );

      expect((await service.generate(_request)).text, 'answer 1');
    });

    test('is unavailable when no backend is', () async {
      final service = AssistantService(
        backends: [_RecordingBackend(available: false)],
        cache: AssistantCache(),
      );

      expect(await service.isAvailable(), isFalse);
    });
  });

  group('backend wiring order', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('assistant-wiring');
    });

    tearDown(() => root.delete(recursive: true));

    test('OpenRouter first, the local llama.cpp runtime second, matching '
        "main.dart's desktop backend list", () async {
      final runtimeDir = Directory('${root.path}/runtime')
        ..createSync(recursive: true);
      final binaryName = Platform.isWindows
          ? 'llama-server.exe'
          : 'llama-server';
      File('${runtimeDir.path}/$binaryName').writeAsStringSync('stub');
      final model = LlamaRuntimeService.catalog.first;
      final modelsDir = Directory('${root.path}/models')
        ..createSync(recursive: true);
      File('${modelsDir.path}/${model.fileName}').writeAsStringSync('stub');

      final local = LocalAssistantBackend(
        runtime: LlamaRuntimeService(root: root),
        client: MockClient(
          (_) async => http.Response(_completion('local answer'), 200),
        ),
        startServer: (_) async => 'http://127.0.0.1:8178',
      );
      final unavailableRouter = OpenRouterAssistantBackend(
        config: FirestoreAssistantConfig(remoteFetcher: () async => null),
      );
      final service = AssistantService(
        backends: [unavailableRouter, local],
        cache: AssistantCache(),
        minimumGap: Duration.zero,
      );

      final summary = await service.generate(_request);

      expect(summary.source, AssistantSource.local);
    });
  });
}

const AssistantRequest _request = AssistantRequest(
  cacheKey: 'digest:3847',
  prompt: 'summarise the comments',
);

String _completion(String text, {String model = 'openrouter/free'}) =>
    jsonEncode({
      'model': model,
      'choices': [
        {
          'message': {'content': text},
        },
      ],
    });

class _RecordingBackend implements AssistantBackend {
  _RecordingBackend({
    this.available = true,
    this.source = AssistantSource.openRouter,
    this.failWith,
  });

  final bool available;
  final AssistantSource source;
  String? failWith;
  int calls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    calls++;
    final reason = failWith;
    if (reason != null) {
      throw AssistantUnavailable(reason);
    }
    return AssistantSummary(
      text: 'answer $calls',
      generatedAt: DateTime.now().toUtc(),
      model: 'm',
      source: source,
    );
  }
}

class _ThrowingBackend implements AssistantBackend {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async =>
      throw StateError('something nobody planned for');
}

class _BrokenCache extends AssistantCache {
  @override
  Future<void> write(String cacheKey, AssistantSummary summary) async =>
      throw StateError('no space left on device');
}
