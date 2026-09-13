import 'package:apple_ai/apple_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/assistant/apple_assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_tool.dart';

void main() {
  late Map<String, Object?> asked;

  AppleAssistantBackend backendThat({
    AppleAiAvailability availability = const AppleAiAvailability.available(),
    String answer = 'Three teams on this alliance can climb reliably.',
    AppleAiException? failure,
  }) {
    asked = <String, Object?>{};
    return AppleAssistantBackend(
      availability: () async => availability,
      respond:
          ({
            required prompt,
            instructions,
            temperature,
            sessionId,
            tools,
          }) async {
            asked = <String, Object?>{
              'prompt': prompt,
              'instructions': instructions,
              'temperature': temperature,
              'sessionId': sessionId,
              'tools': tools,
            };
            if (failure != null) throw failure;
            return answer;
          },
    );
  }

  AssistantRequest request({
    String prompt = 'Who climbs?',
    String? system,
    List<AssistantTurn>? history,
    int? minimumChars,
  }) => AssistantRequest(
    cacheKey: 'test:2026txhou:3847',
    prompt: prompt,
    system: system,
    history: history,
    minimumChars: minimumChars,
  );

  group('isAvailable', () {
    test('follows the on-device model', () async {
      expect(await backendThat().isAvailable(), isTrue);
      expect(
        await backendThat(
          availability: const AppleAiAvailability.unavailable(
            AppleAiUnavailableReason.deviceNotEligible,
          ),
        ).isAvailable(),
        isFalse,
      );
    });
  });

  group('complete', () {
    test('answers, stamped as the on-device Apple model', () async {
      final backend = backendThat();

      final summary = await backend.complete(
        request(system: 'Answer in two sentences.'),
      );

      expect(summary.text, 'Three teams on this alliance can climb reliably.');
      expect(summary.source, AssistantSource.apple);
      expect(summary.model, contains('Apple'));
      expect(asked['prompt'], 'Who climbs?');
      expect(asked['instructions'], 'Answer in two sentences.');
      expect(asked['temperature'], 0.2);
    });

    test('folds history into the prompt, labelled by speaker', () async {
      final backend = backendThat();

      await backend.complete(
        request(
          prompt: 'And in auton?',
          history: const <AssistantTurn>[
            AssistantTurn(role: AssistantTurnRole.user, content: 'Who climbs?'),
            AssistantTurn(
              role: AssistantTurnRole.assistant,
              content: '3847 and 118.',
            ),
          ],
        ),
      );

      final prompt = asked['prompt']! as String;
      expect(prompt, contains('Question: Who climbs?'));
      expect(prompt, contains('You: 3847 and 118.'));

      expect(prompt.trimRight(), endsWith('And in auton?'));
    });

    test('an unavailable model is a reason a person can act on', () async {
      final backend = backendThat(
        availability: const AppleAiAvailability.unavailable(
          AppleAiUnavailableReason.appleIntelligenceNotEnabled,
        ),
      );

      expect(
        () => backend.complete(request()),
        throwsA(
          isA<AssistantUnavailable>().having(
            (e) => e.reason,
            'reason',
            contains('Settings'),
          ),
        ),
      );
    });

    test('a refusal from the model is unavailable, not a summary', () async {
      final backend = backendThat(
        failure: const AppleAiException('the model declined'),
      );

      expect(
        () => backend.complete(request()),
        throwsA(
          isA<AssistantUnavailable>().having(
            (e) => e.reason,
            'reason',
            'the model declined',
          ),
        ),
      );
    });

    test('a chat turn carries the session id and the tools', () async {
      final registry = AssistantToolRegistry([_FakeToolProvider()]);
      AppleAiToolHandler? installed;
      final backend = AppleAssistantBackend(
        tools: registry,
        availability: () async => const AppleAiAvailability.available(),
        setToolHandler: (handler) => installed = handler,
        respond:
            ({
              required prompt,
              instructions,
              temperature,
              sessionId,
              tools,
            }) async {
              asked = <String, Object?>{
                'prompt': prompt,
                'sessionId': sessionId,
                'tools': tools,
              };
              return 'Team 3847 climbs in nine of eleven matches this event.';
            },
      );

      await backend.complete(
        AssistantRequest(
          cacheKey: 'chat',
          prompt: 'who climbs?',
          useTools: true,
          sessionId: 'chat-1',
        ),
      );

      expect(asked['sessionId'], 'chat-1');
      expect((asked['tools']! as List<AppleAiTool>).single.name, 'fake_tool');

      expect(await installed!('fake_tool', <String, dynamic>{}), 'fake result');
      expect(
        await installed!('no_such_tool', <String, dynamic>{}),
        startsWith('Error: no such tool'),
      );
    });

    test('sends a tool description without its guidance', () async {
      final registry = AssistantToolRegistry([_FakeToolProvider()]);
      final backend = AppleAssistantBackend(
        tools: registry,
        availability: () async => const AppleAiAvailability.available(),
        setToolHandler: (_) {},
        respond:
            ({
              required prompt,
              instructions,
              temperature,
              sessionId,
              tools,
            }) async {
              asked = <String, Object?>{'tools': tools};
              return 'Team 3847 climbs in nine of eleven matches this event.';
            },
      );

      await backend.complete(
        const AssistantRequest(
          cacheKey: 'chat',
          prompt: 'who climbs?',
          useTools: true,
        ),
      );

      final tool = (asked['tools']! as List<AppleAiTool>).single;
      expect(tool.description, 'Answers with a fixed string.');
      expect(tool.description, isNot(contains('Prefer the other tool')));
    });

    test('cuts a tool result to its own budget, not the registry\'s', () async {
      final registry = AssistantToolRegistry([
        _FakeToolProvider(result: 'x' * 3000),
      ]);
      AppleAiToolHandler? installed;
      final backend = AppleAssistantBackend(
        tools: registry,
        availability: () async => const AppleAiAvailability.available(),
        setToolHandler: (handler) => installed = handler,
        respond: ({
          required prompt,
          instructions,
          temperature,
          sessionId,
          tools,
        }) async => 'Team 3847 climbs in nine of eleven matches.',
      );

      await backend.complete(
        const AssistantRequest(
          cacheKey: 'chat',
          prompt: 'who climbs?',
          useTools: true,
        ),
      );

      final result = await installed!('fake_tool', <String, dynamic>{});
      expect(result, contains('[Truncated:'));
      expect(
        result,
        startsWith('x' * AppleAssistantBackend.appleToolResultCharBudget),
      );
    });

    test('prefers the compact system prompt when one is offered', () async {
      final backend = backendThat();
      await backend.complete(
        const AssistantRequest(
          cacheKey: 'chat',
          prompt: 'who climbs?',
          system: 'The long framing, written for a bigger window.',
          compactSystem: 'The short framing.',
        ),
      );
      expect(asked['instructions'], 'The short framing.');
    });

    test(
      'falls back to the full system prompt when there is no compact one',
      () async {
        final backend = backendThat();
        await backend.complete(
          const AssistantRequest(
            cacheKey: 'chat',
            prompt: 'who climbs?',
            system: 'The only framing there is.',
          ),
        );
        expect(asked['instructions'], 'The only framing there is.');
      },
    );

    test('drops the oldest exchanges from a seeded prompt', () async {
      final backend = backendThat();
      final history = <AssistantTurn>[
        for (var i = 0; i < 10; i++) ...<AssistantTurn>[
          AssistantTurn(
            role: AssistantTurnRole.user,
            content: 'q$i ${'a' * 400}',
          ),
          AssistantTurn(
            role: AssistantTurnRole.assistant,
            content: 'answer $i',
          ),
        ],
      ];

      await backend.complete(
        AssistantRequest(
          cacheKey: 'chat',
          prompt: 'and in auton?',
          history: history,
        ),
      );

      final prompt = asked['prompt']! as String;
      expect(prompt, contains('and in auton?'));
      expect(prompt, isNot(contains('q0')));
      expect(prompt, contains('q9'));
    });

    test('a live session is not made to re-read its own history', () async {
      final backend = backendThat();
      const request = AssistantRequest(
        cacheKey: 'chat',
        prompt: 'and in auton?',
        sessionId: 'chat-1',
        history: <AssistantTurn>[
          AssistantTurn(role: AssistantTurnRole.user, content: 'who climbs?'),
          AssistantTurn(
            role: AssistantTurnRole.assistant,
            content: '3847 and 118.',
          ),
        ],
      );

      await backend.complete(request);
      expect(asked['prompt'], contains('Question: who climbs?'));

      await backend.complete(request);
      expect(asked['prompt'], 'and in auton?');
    });

    test('a failed turn does not claim the session holds it', () async {
      var calls = 0;
      final backend = AppleAssistantBackend(
        availability: () async => const AppleAiAvailability.available(),
        setToolHandler: (_) {},
        respond:
            ({
              required prompt,
              instructions,
              temperature,
              sessionId,
              tools,
            }) async {
              asked = <String, Object?>{'prompt': prompt};
              if (++calls == 1) throw const AppleAiException('busy');
              return 'Team 3847 climbs in nine of eleven matches this event.';
            },
      );
      const request = AssistantRequest(
        cacheKey: 'chat',
        prompt: 'and in auton?',
        sessionId: 'chat-1',
        history: <AssistantTurn>[
          AssistantTurn(role: AssistantTurnRole.user, content: 'who climbs?'),
        ],
      );

      await expectLater(
        () => backend.complete(request),
        throwsA(isA<AssistantUnavailable>()),
      );
      await backend.complete(request);

      expect(asked['prompt'], contains('Question: who climbs?'));
    });

    test('closing a chat makes the next turn seed a fresh session', () async {
      final backend = backendThat();
      const request = AssistantRequest(
        cacheKey: 'chat',
        prompt: 'and in auton?',
        sessionId: 'chat-1',
        history: <AssistantTurn>[
          AssistantTurn(role: AssistantTurnRole.user, content: 'who climbs?'),
        ],
      );

      await backend.complete(request);
      await backend.complete(request);
      expect(asked['prompt'], 'and in auton?');

      await backend.closeSession('chat-1');
      await backend.complete(request);

      expect(asked['prompt'], contains('Question: who climbs?'));
    });

    test('an answer under the feature floor is not an answer', () async {
      final backend = backendThat(answer: 'Yes.');

      expect(
        () => backend.complete(request(minimumChars: 80)),
        throwsA(isA<AssistantUnavailable>()),
      );
    });
  });
}

class _FakeToolProvider implements AssistantToolProvider {
  _FakeToolProvider({this.result = 'fake result'});

  final String result;

  @override
  Future<List<AssistantToolSpec>> tools() async => const <AssistantToolSpec>[
    AssistantToolSpec(
      name: 'fake_tool',
      description: 'Answers with a fixed string.',
      guidance: 'Prefer the other tool when the question is about EPA.',
      parameters: <String, dynamic>{'type': 'object'},
    ),
  ];

  @override
  Future<String> call(String name, Map<String, dynamic> arguments) async =>
      result;
}
