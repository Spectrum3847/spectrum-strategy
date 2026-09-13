import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_tool.dart';
import 'package:spectrumstrategy/src/services/assistant/firestore_assistant_config.dart';
import 'package:spectrumstrategy/src/services/assistant/openrouter_assistant_backend.dart';

class _TeamLookupProvider implements AssistantToolProvider {
  int calls = 0;

  @override
  Future<List<AssistantToolSpec>> tools() async => [
    const AssistantToolSpec(
      name: 'lookup_team',
      description: 'test tool',
      parameters: {'type': 'object', 'properties': {}},
    ),
  ];

  @override
  Future<String> call(String name, Map<String, dynamic> arguments) async {
    calls++;
    return 'team 3847: strong auto';
  }
}

String _toolCallBody() => jsonEncode({
  'model': 'openrouter/free',
  'choices': [
    {
      'message': {
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          {
            'id': 'call-1',
            'type': 'function',
            'function': {'name': 'lookup_team', 'arguments': '{}'},
          },
        ],
      },
    },
  ],
});

String _finalBody(String text) => jsonEncode({
  'model': 'openrouter/free',
  'choices': [
    {
      'message': {'role': 'assistant', 'content': text},
    },
  ],
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('a request with useTools false never sends a tools key', () async {
    final registry = AssistantToolRegistry([_TeamLookupProvider()]);
    Map<String, dynamic>? sent;
    final backend = OpenRouterAssistantBackend(
      config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
      tools: registry,
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(_finalBody('a plain summary'), 200);
      }),
    );

    await backend.complete(
      const AssistantRequest(cacheKey: 'k', prompt: 'summarize'),
    );

    expect(sent!.containsKey('tools'), isFalse);
  });

  test('runs a tool call and answers with the final content', () async {
    final provider = _TeamLookupProvider();
    final registry = AssistantToolRegistry([provider]);
    var requestCount = 0;
    final bodies = <Map<String, dynamic>>[];
    final backend = OpenRouterAssistantBackend(
      config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
      tools: registry,
      client: MockClient((request) async {
        requestCount++;
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (requestCount == 1) {
          return http.Response(_toolCallBody(), 200);
        }
        return http.Response(
          _finalBody('3847 is strong in auto, per our scouts.'),
          200,
        );
      }),
    );

    final summary = await backend.complete(
      const AssistantRequest(
        cacheKey: 'k',
        prompt: 'how does 3847 look?',
        useTools: true,
      ),
    );

    expect(provider.calls, 1);
    expect(summary.text, '3847 is strong in auto, per our scouts.');
    expect(bodies.first['tools'], isNotNull);

    final secondMessages = (bodies[1]['messages'] as List)
        .cast<Map<String, dynamic>>();
    expect(secondMessages.last['role'], 'tool');
    expect(secondMessages.last['tool_call_id'], 'call-1');
    expect(secondMessages.last['content'], 'team 3847: strong auto');
  });

  test('caps rounds for a model that keeps calling the same tool', () async {
    final registry = AssistantToolRegistry([_TeamLookupProvider()]);
    var requestCount = 0;
    final backend = OpenRouterAssistantBackend(
      config: FirestoreAssistantConfig(remoteFetcher: () async => 'k'),
      tools: registry,
      client: MockClient((request) async {
        requestCount++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body.containsKey('tools')) {
          return http.Response(_toolCallBody(), 200);
        }
        return http.Response(_finalBody('giving up'), 200);
      }),
    );

    final summary = await backend.complete(
      const AssistantRequest(
        cacheKey: 'k',
        prompt: 'loop forever',
        useTools: true,
      ),
    );

    expect(summary.text, 'giving up');

    expect(requestCount, 5);
  });
}
