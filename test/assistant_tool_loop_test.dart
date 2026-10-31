import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_tool.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_tool_loop.dart';

class _OneToolProvider implements AssistantToolProvider {
  int calls = 0;

  @override
  Future<List<AssistantToolSpec>> tools() async => [
    const AssistantToolSpec(
      name: 'get_team',
      description: 'test tool',
      parameters: {'type': 'object', 'properties': {}},
    ),
  ];

  @override
  Future<String> call(String name, Map<String, dynamic> arguments) async {
    calls++;
    return 'team 3847 stats';
  }
}

Map<String, dynamic> _toolCallMessage({String id = 'call-1'}) => {
  'role': 'assistant',
  'content': null,
  'tool_calls': [
    {
      'id': id,
      'type': 'function',
      'function': {'name': 'get_team', 'arguments': '{"team_number": 3847}'},
    },
  ],
};

Map<String, dynamic> _finalMessage(String text) => {
  'role': 'assistant',
  'content': text,
};

void main() {
  group('runAssistantToolLoop', () {
    test(
      'sends the identical single request when there is no registry',
      () async {
        final requests = <List<Map<String, dynamic>>>[];
        final toolArgs = <List<Map<String, dynamic>>?>[];
        final message = await runAssistantToolLoop(
          messages: [
            {'role': 'user', 'content': 'hi'},
          ],
          registry: null,
          complete: (messages, tools) async {
            requests.add(messages);
            toolArgs.add(tools);
            return _finalMessage('ok');
          },
        );

        expect(requests, hasLength(1));
        expect(toolArgs.single, isNull);
        expect(message['content'], 'ok');
      },
    );

    test(
      'runs a tool call and feeds the result back as a tool message',
      () async {
        final provider = _OneToolProvider();
        final registry = AssistantToolRegistry([provider]);
        var round = 0;
        final requestBodies = <List<Map<String, dynamic>>>[];

        final message = await runAssistantToolLoop(
          messages: [
            {'role': 'user', 'content': 'what about 3847?'},
          ],
          registry: registry,
          complete: (messages, tools) async {
            requestBodies.add(messages);
            round++;
            if (round == 1) {
              expect(tools, isNotNull);
              return _toolCallMessage();
            }
            return _finalMessage('3847 looks strong');
          },
        );

        expect(provider.calls, 1);
        expect(message['content'], '3847 looks strong');

        final secondRequest = requestBodies[1];
        expect(secondRequest.last, {
          'role': 'tool',
          'tool_call_id': 'call-1',
          'content': 'team 3847 stats',
        });
        expect(
          secondRequest[secondRequest.length - 2]['tool_calls'],
          isNotNull,
        );
      },
    );

    test(
      'caps round trips for a model that calls the same tool forever',
      () async {
        final provider = _OneToolProvider();
        final registry = AssistantToolRegistry([provider]);
        var calls = 0;

        final message = await runAssistantToolLoop(
          messages: [
            {'role': 'user', 'content': 'loop please'},
          ],
          registry: registry,
          complete: (messages, tools) async {
            calls++;
            if (tools == null) {
              return _finalMessage('giving up, here is what I know');
            }
            return _toolCallMessage(id: 'call-$calls');
          },
          maxRounds: 4,
        );

        expect(calls, 5);
        expect(message['content'], 'giving up, here is what I know');
      },
    );

    test('stops early once the model answers without a tool call', () async {
      final registry = AssistantToolRegistry([_OneToolProvider()]);
      var calls = 0;

      final message = await runAssistantToolLoop(
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
        registry: registry,
        complete: (messages, tools) async {
          calls++;
          return _finalMessage('no tool needed');
        },
      );

      expect(calls, 1);
      expect(message['content'], 'no tool needed');
    });
  });

  test('every declared tool_call gets a matching tool message', () async {
    final provider = _OneToolProvider();
    final registry = AssistantToolRegistry([provider]);
    final sent = <List<Map<String, dynamic>>>[];

    await runAssistantToolLoop(
      messages: [
        {'role': 'user', 'content': 'how did 3847 do'},
      ],
      registry: registry,
      maxToolCalls: 1,
      complete: (messages, tools) async {
        sent.add(messages);
        if (tools == null) return _finalMessage('done');
        return {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'call-a',
              'type': 'function',
              'function': {'name': 'get_team', 'arguments': '{}'},
            },

            {
              'id': 'call-b',
              'type': 'function',
              'function': {'name': 'get_team', 'arguments': '{}'},
            },

            'not-a-map',
          ],
        };
      },
    );

    final last = sent.last;
    final declared = <String>{};
    for (final message in last) {
      final calls = message['tool_calls'];
      if (calls is List) {
        for (final call in calls) {
          if (call is Map && call['id'] != null) declared.add('${call['id']}');
        }
      }
    }
    final answered = last
        .where((m) => m['role'] == 'tool')
        .map((m) => '${m['tool_call_id']}')
        .toSet();

    expect(declared, {'call-a', 'call-b'});
    expect(answered.containsAll(declared), isTrue);
    expect(provider.calls, 1, reason: 'the cap still bounds real tool runs');
  });
}
