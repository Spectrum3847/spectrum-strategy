import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/state/assistant_chat_controller.dart';

void main() {
  group('AssistantChatController', () {
    test('a turn round trips: question in, answer out, source shown', () async {
      final backend = _FakeBackend(reply: '3847 climbs reliably.');
      final controller = AssistantChatController(
        assistant: AssistantService(
          backends: [backend],
          cache: AssistantCache(),
          minimumGap: Duration.zero,
        ),
      );

      await controller.send('How does 3847 climb?');

      expect(controller.messages, hasLength(2));
      expect(controller.messages[0].kind, AssistantChatMessageKind.user);
      expect(controller.messages[0].text, 'How does 3847 climb?');
      expect(controller.messages[1].kind, AssistantChatMessageKind.assistant);
      expect(controller.messages[1].text, '3847 climbs reliably.');
      expect(controller.messages[1].source, AssistantSource.local);
      expect(controller.messages[1].model, 'test-model');
    });

    test('history accumulates oldest first and alternates roles', () async {
      final backend = _FakeBackend(reply: 'first answer');
      final controller = AssistantChatController(
        assistant: AssistantService(
          backends: [backend],
          cache: AssistantCache(),
          minimumGap: Duration.zero,
        ),
      );

      await controller.send('question one');
      backend.reply = 'second answer';
      await controller.send('question two');

      final secondRequest = backend.requests[1];
      expect(secondRequest.history, hasLength(2));
      expect(secondRequest.history![0].role, AssistantTurnRole.user);
      expect(secondRequest.history![0].content, 'question one');
      expect(secondRequest.history![1].role, AssistantTurnRole.assistant);
      expect(secondRequest.history![1].content, 'first answer');
      expect(secondRequest.prompt, 'question two');
    });

    test('every request goes through converse with tools on and the '
        'system prompt attached', () async {
      final backend = _FakeBackend();
      final controller = AssistantChatController(
        assistant: AssistantService(
          backends: [backend],
          cache: AssistantCache(),
          minimumGap: Duration.zero,
        ),
      );

      await controller.send('anything');

      expect(backend.requests.single.useTools, isTrue);
      expect(backend.requests.single.system, isNotNull);
    });

    test('an AssistantUnavailable renders as a recoverable error and keeps '
        'the typed reason', () async {
      final backend = _FakeBackend(available: false);
      final controller = AssistantChatController(
        assistant: AssistantService(
          backends: [backend],
          cache: AssistantCache(),
          minimumGap: Duration.zero,
        ),
      );

      await controller.send('is anyone there?');

      expect(controller.messages, hasLength(2));
      expect(controller.messages[1].kind, AssistantChatMessageKind.error);
      expect(controller.messages[1].text, contains('No assistant backend'));

      expect(controller.isSending, isFalse);
    });

    test(
      'a second concurrent send is blocked while one is in flight',
      () async {
        final gate = Completer<void>();
        final backend = _FakeBackend(reply: 'answer', gate: gate);
        final controller = AssistantChatController(
          assistant: AssistantService(
            backends: [backend],
            cache: AssistantCache(),
            minimumGap: Duration.zero,
          ),
        );

        final first = controller.send('first question');
        expect(controller.isSending, isTrue);

        final second = controller.send('second question');

        gate.complete();
        await Future.wait([first, second]);

        expect(backend.requests, hasLength(1));
        expect(controller.messages, hasLength(2));
        expect(controller.messages[0].text, 'first question');
      },
    );

    test('an unexpected failure shows an error, not silence', () async {
      final controller = AssistantChatController(
        assistant: AssistantService(
          backends: [_ThrowingProbeBackend()],
          cache: AssistantCache(),
          minimumGap: Duration.zero,
        ),
      );

      await controller.send('a question');

      expect(controller.isSending, isFalse);
      expect(controller.messages.last.kind, AssistantChatMessageKind.error);
      expect(controller.messages.last.text, contains('models directory'));
    });

    test('clear starts over', () async {
      final backend = _FakeBackend(reply: 'answer');
      final controller = AssistantChatController(
        assistant: AssistantService(
          backends: [backend],
          cache: AssistantCache(),
          minimumGap: Duration.zero,
        ),
      );

      await controller.send('a question');
      controller.clear();

      expect(controller.messages, isEmpty);

      await controller.send('a fresh question');

      expect(backend.requests.last.history, isEmpty);
    });
  });
}

class _ThrowingProbeBackend implements AssistantBackend {
  @override
  Future<bool> isAvailable() async =>
      throw const FileSystemException('models directory unreadable');

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async =>
      throw StateError('never reached');
}

class _FakeBackend implements AssistantBackend {
  _FakeBackend({this.reply = 'ok', this.available = true, this.gate});

  String reply;
  final String model = 'test-model';
  final bool available;
  final Completer<void>? gate;
  final List<AssistantRequest> requests = [];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    requests.add(request);
    final wait = gate;
    if (wait != null) {
      await wait.future;
    }
    return AssistantSummary(
      text: reply,
      generatedAt: DateTime.now().toUtc(),
      model: model,
      source: AssistantSource.local,
    );
  }
}
