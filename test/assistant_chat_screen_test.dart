import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/state/assistant_chat_controller.dart';
import 'package:spectrumstrategy/src/ui/assistant_chat_screen.dart';
import 'package:spectrumstrategy/src/ui/glass_chrome.dart';
import 'package:spectrumstrategy/src/widgets/glass_panel.dart';

void main() {
  Future<AssistantChatController> pump(
    WidgetTester tester, {
    required _FakeBackend backend,
    bool glassEnabled = false,
    double glassBottomPadding = 0,
  }) async {
    final controller = AssistantChatController(
      assistant: AssistantService(
        backends: [backend],
        cache: AssistantCache(),
        minimumGap: Duration.zero,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(bottom: glassBottomPadding),
                ),
                child: GlassChrome(
                  enabled: glassEnabled,
                  child: AssistantChatScreen(
                    controller: controller,
                    embedded: true,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('a turn round trips: question and markdown answer render', (
    tester,
  ) async {
    final backend = _FakeBackend(reply: 'Team **3847** climbs reliably.');
    await pump(tester, backend: backend);

    await tester.enterText(find.byType(TextField), 'How does 3847 climb?');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('How does 3847 climb?'),
      ),
      findsOneWidget,
    );
    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown.data, 'Team **3847** climbs reliably.');
  });

  testWidgets('shows which backend answered', (tester) async {
    final backend = _FakeBackend(
      reply: 'ok',
      source: AssistantSource.openRouter,
      model: 'some-vendor/some-model:free',
    );
    await pump(tester, backend: backend);

    await tester.enterText(find.byType(TextField), 'question');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('OpenRouter'), findsOneWidget);
    expect(find.textContaining('some-vendor/some-model:free'), findsOneWidget);
  });

  testWidgets('the in-flight state shows before the answer arrives', (
    tester,
  ) async {
    final backend = _FakeBackend(reply: 'ok', gate: Completer<void>());
    await pump(tester, backend: backend);

    await tester.enterText(find.byType(TextField), 'question');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(find.textContaining('Thinking'), findsOneWidget);

    final sendButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.send_rounded),
    );
    expect(sendButton.onPressed, isNull);

    backend.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('an AssistantUnavailable renders as a recoverable error with the '
      'typed reason', (tester) async {
    final backend = _FakeBackend(available: false);
    await pump(tester, backend: backend);

    await tester.enterText(find.byType(TextField), 'is anyone there?');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('No assistant backend'), findsOneWidget);

    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('is anyone there?'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Retry sits on the newest answer only', (tester) async {
    final backend = _FakeBackend(reply: 'first answer');
    final controller = await pump(tester, backend: backend);

    await tester.enterText(find.byType(TextField), 'first question');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'second question');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(controller.messages, hasLength(4));
  });

  testWidgets('Retry asks the question again and replaces the answer', (
    tester,
  ) async {
    final backend = _FakeBackend(reply: 'a wrong answer');
    await pump(tester, backend: backend);

    await tester.enterText(find.byType(TextField), 'how is 3847 doing');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    backend.reply = 'a better answer';
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    final list = find.byType(ListView);
    expect(
      find.descendant(of: list, matching: find.textContaining('a better')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: list, matching: find.textContaining('a wrong')),
      findsNothing,
    );
  });

  testWidgets('a long model name beside Retry does not overflow a narrow '
      'bubble', (tester) async {
    tester.view.physicalSize = const Size(420, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final backend = _FakeBackend(
      reply: 'an answer',
      model: 'LFM2.5-8B-A1B-Q4_K_M-Instruct',
    );
    await pump(tester, backend: backend);

    await tester.enterText(find.byType(TextField), 'how is 3847 doing');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed turn offers Retry', (tester) async {
    final backend = _FakeBackend(reply: 'ok', fail: true);
    await pump(tester, backend: backend);

    await tester.enterText(find.byType(TextField), 'how is 3847 doing');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the composer clears the system bottom inset', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final backend = _FakeBackend();
    await pump(
      tester,
      backend: backend,
      glassEnabled: true,
      glassBottomPadding: 40,
    );

    final sendButtonBottom = tester
        .getBottomLeft(find.byIcon(Icons.send_rounded))
        .dy;

    expect(800 - sendButtonBottom, greaterThanOrEqualTo(40));
  });

  testWidgets('delete-chat draws on GlassPanel when glass is on', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pump(tester, backend: _FakeBackend(), glassEnabled: true);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(GlassPanel), findsOneWidget);
    expect(find.text('Delete this chat?'), findsOneWidget);
  });

  testWidgets('delete-chat is a plain AlertDialog when glass is off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pump(tester, backend: _FakeBackend());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(GlassPanel), findsNothing);
  });

  testWidgets('the saved-chats sheet draws on GlassPanel when glass is on', (
    tester,
  ) async {
    await pump(tester, backend: _FakeBackend(), glassEnabled: true);
    await tester.pump();

    await tester.tap(find.byTooltip('Saved chats'));
    await tester.pumpAndSettle();

    expect(find.byType(GlassPanel), findsOneWidget);
  });

  testWidgets('the saved-chats sheet is plain Material when glass is off', (
    tester,
  ) async {
    await pump(tester, backend: _FakeBackend());
    await tester.pump();

    await tester.tap(find.byTooltip('Saved chats'));
    await tester.pumpAndSettle();

    expect(find.byType(GlassPanel), findsNothing);
  });
}

class _FakeBackend implements AssistantBackend {
  _FakeBackend({
    this.reply = 'ok',
    this.model = 'test-model',
    this.source = AssistantSource.local,
    this.available = true,
    this.gate,
    this.fail = false,
  });

  String reply;

  bool fail;
  final String model;
  final AssistantSource source;
  final bool available;

  final Completer<void>? gate;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    final wait = gate;
    if (wait != null) {
      await wait.future;
    }
    if (fail) throw const AssistantUnavailable('the model fell over');
    return AssistantSummary(
      text: reply,
      generatedAt: DateTime.now().toUtc(),
      model: model,
      source: source,
    );
  }
}
