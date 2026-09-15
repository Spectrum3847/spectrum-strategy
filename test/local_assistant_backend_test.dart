import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_tool.dart';
import 'package:spectrumstrategy/src/services/assistant/local_assistant_backend.dart';
import 'package:spectrumstrategy/src/services/llama_runtime_service.dart';

class _CountingToolProvider implements AssistantToolProvider {
  int calls = 0;

  @override
  Future<List<AssistantToolSpec>> tools() async => [
    const AssistantToolSpec(
      name: 'get_pick_list',
      description: 'test tool',
      parameters: {'type': 'object', 'properties': {}},
    ),
  ];

  @override
  Future<String> call(String name, Map<String, dynamic> arguments) async {
    calls++;
    return 'pick list: 3847, 254, 118';
  }
}

void main() {
  late Directory root;
  late LlamaRuntimeService runtime;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    root = await Directory.systemTemp.createTemp('local-assistant-backend');
    runtime = LlamaRuntimeService(root: root);
  });

  tearDown(() => root.delete(recursive: true));

  Future<void> installBinary() async {
    final runtimeDir = Directory('${root.path}/runtime');
    await runtimeDir.create(recursive: true);
    final name = Platform.isWindows ? 'llama-server.exe' : 'llama-server';
    await File('${runtimeDir.path}/$name').writeAsString('stub');
  }

  AssistantModel testModel() => AssistantModel(
    repoId: 'unsloth/Qwen3-4B-GGUF',
    path: 'Qwen3-4B-Q4_K_M.gguf',
    sizeBytes: 2740937888,
  );

  Future<void> installModel(AssistantModel model) async {
    final modelsDir = Directory('${root.path}/models');
    await modelsDir.create(recursive: true);
    await File('${modelsDir.path}/${model.fileName}').writeAsString('stub');
    final manifest = File('${modelsDir.path}/installed_v1.json');
    await manifest.writeAsString(jsonEncode({model.id: model.toJson()}));
  }

  group('isAvailable', () {
    test('is false with nothing installed', () async {
      final backend = LocalAssistantBackend(runtime: runtime);
      expect(await backend.isAvailable(), isFalse);
    });

    test('is false with a model but no runtime binary', () async {
      await installModel(testModel());
      final backend = LocalAssistantBackend(runtime: runtime);
      expect(await backend.isAvailable(), isFalse);
    });

    test('is false with a runtime binary but no model', () async {
      await installBinary();
      final backend = LocalAssistantBackend(runtime: runtime);
      expect(await backend.isAvailable(), isFalse);
    });

    test('is true once both a binary and a model are installed', () async {
      await installBinary();
      await installModel(testModel());
      final backend = LocalAssistantBackend(runtime: runtime);
      expect(await backend.isAvailable(), isTrue);
    });
  });

  group('complete', () {
    test('throws AssistantUnavailable when no model is installed', () async {
      await installBinary();
      final backend = LocalAssistantBackend(runtime: runtime);
      await expectLater(
        backend.complete(const AssistantRequest(cacheKey: 'k', prompt: 'hi')),
        throwsA(isA<AssistantUnavailable>()),
      );
    });

    test('wraps a server-start failure as AssistantUnavailable', () async {
      await installModel(testModel());
      final backend = LocalAssistantBackend(
        runtime: runtime,
        startServer: (_) => Future.error(StateError('boom')),
      );
      await expectLater(
        backend.complete(const AssistantRequest(cacheKey: 'k', prompt: 'hi')),
        throwsA(isA<AssistantUnavailable>()),
      );
    });

    test('posts an OpenAI-style chat request with thinking disabled', () async {
      final model = testModel();
      await installModel(model);
      late Uri requested;
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        requested = request.url;
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': ' 254 is a strong pick. '},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final backend = LocalAssistantBackend(
        runtime: runtime,
        client: client,
        startServer: (_) async => 'http://127.0.0.1:8178',
      );

      final summary = await backend.complete(
        const AssistantRequest(
          cacheKey: 'k',
          prompt: 'Who should we pick?',
          system: 'You are a strategy assistant.',
        ),
      );

      expect(requested.toString(), 'http://127.0.0.1:8178/v1/chat/completions');
      expect(sent['model'], model.name);
      expect(sent['max_tokens'], 1024);
      expect(sent['chat_template_kwargs'], {'enable_thinking': false});
      final messages = (sent['messages'] as List).cast<Map<String, dynamic>>();
      expect(messages.first, {
        'role': 'system',
        'content': 'You are a strategy assistant.',
      });
      expect(messages.last, {'role': 'user', 'content': 'Who should we pick?'});

      expect(summary.text, '254 is a strong pick.');
      expect(summary.model, model.name);
      expect(summary.source, AssistantSource.local);
    });

    test('prepends history turns before the final prompt', () async {
      await installModel(testModel());
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final backend = LocalAssistantBackend(
        runtime: runtime,
        client: client,
        startServer: (_) async => 'http://127.0.0.1:8178',
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

      final messages = (sent['messages'] as List).cast<Map<String, dynamic>>();
      expect(messages, [
        {'role': 'user', 'content': 'pick 254'},
        {'role': 'assistant', 'content': '254 it is.'},
        {'role': 'user', 'content': 'and the counter?'},
      ]);
    });

    test('omits the system message when there is none', () async {
      await installModel(testModel());
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final backend = LocalAssistantBackend(
        runtime: runtime,
        client: client,
        startServer: (_) async => 'http://127.0.0.1:8178',
      );

      await backend.complete(
        const AssistantRequest(cacheKey: 'k', prompt: 'hi'),
      );

      final messages = (sent['messages'] as List).cast<Map<String, dynamic>>();
      expect(messages, hasLength(1));
      expect(messages.first['role'], 'user');
    });

    test('falls back to reasoning_content when content is empty', () async {
      await installModel(testModel());
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '', 'reasoning_content': '  254 wins  '},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final backend = LocalAssistantBackend(
        runtime: runtime,
        client: client,
        startServer: (_) async => 'http://127.0.0.1:8178',
      );

      final summary = await backend.complete(
        const AssistantRequest(cacheKey: 'k', prompt: 'hi'),
      );
      expect(summary.text, '254 wins');
    });

    test('a non-200 answer is AssistantUnavailable, not a crash', () async {
      await installModel(testModel());
      final client = MockClient(
        (request) async => http.Response('loading model', 503),
      );
      final backend = LocalAssistantBackend(
        runtime: runtime,
        client: client,
        startServer: (_) async => 'http://127.0.0.1:8178',
      );

      await expectLater(
        backend.complete(const AssistantRequest(cacheKey: 'k', prompt: 'hi')),
        throwsA(
          isA<AssistantUnavailable>().having(
            (e) => e.reason,
            'reason',
            contains('503'),
          ),
        ),
      );
    });

    test('an empty answer is AssistantUnavailable, not a crash', () async {
      await installModel(testModel());
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': ''},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final backend = LocalAssistantBackend(
        runtime: runtime,
        client: client,
        startServer: (_) async => 'http://127.0.0.1:8178',
      );

      await expectLater(
        backend.complete(const AssistantRequest(cacheKey: 'k', prompt: 'hi')),
        throwsA(isA<AssistantUnavailable>()),
      );
    });
  });

  group('tool calling', () {
    test('a registry is ignored when useTools is false', () async {
      await installModel(testModel());
      Map<String, dynamic>? sent;
      final client = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final backend = LocalAssistantBackend(
        runtime: runtime,
        client: client,
        startServer: (_) async => 'http://127.0.0.1:8178',
        tools: AssistantToolRegistry([_CountingToolProvider()]),
      );

      await backend.complete(
        const AssistantRequest(cacheKey: 'k', prompt: 'hi'),
      );

      expect(sent!.containsKey('tools'), isFalse);
    });

    test('runs a tool call and feeds the result back', () async {
      await installModel(testModel());
      final provider = _CountingToolProvider();
      var requestCount = 0;
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        requestCount++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        if (requestCount == 1) {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': null,
                    'tool_calls': [
                      {
                        'id': 'call-1',
                        'type': 'function',
                        'function': {
                          'name': 'get_pick_list',
                          'arguments': '{}',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'take 254 first, then 3847'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final backend = LocalAssistantBackend(
        runtime: runtime,
        client: client,
        startServer: (_) async => 'http://127.0.0.1:8178',
        tools: AssistantToolRegistry([provider]),
      );

      final summary = await backend.complete(
        const AssistantRequest(
          cacheKey: 'k',
          prompt: 'who should we pick?',
          useTools: true,
        ),
      );

      expect(provider.calls, 1);
      expect(summary.text, 'take 254 first, then 3847');
      expect(bodies.first['tools'], isNotNull);
      final secondMessages = (bodies[1]['messages'] as List)
          .cast<Map<String, dynamic>>();
      expect(secondMessages.last, {
        'role': 'tool',
        'tool_call_id': 'call-1',
        'content': 'pick list: 3847, 254, 118',
      });
    });
  });
}
