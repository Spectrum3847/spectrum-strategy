import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/services/llama_runtime_service.dart';
import 'package:spectrumstrategy/src/state/assistant_chat_controller.dart';
import 'package:spectrumstrategy/src/ui/ai_tab.dart';

void main() {
  late Directory root;
  setUpAll(() async => root = await Directory.systemTemp.createTemp('ai-tab'));
  tearDownAll(() async => root.delete(recursive: true));

  LlamaRuntimeService makeRuntime() => LlamaRuntimeService(
    root: root,
    os: 'linux',
    arch: 'x64',
    client: MockClient((_) async => http.Response('[]', 200)),
    ramProbe: () async => 16,
    vramProbe: () async => null,

    autoVariantDetector: () async => LlamaBuildVariant.cpu,
  );

  AssistantChatController makeChatController() => AssistantChatController(
    assistant: AssistantService(
      backends: [_FakeBackend(available: false)],
      cache: AssistantCache(),
    ),
  );

  Future<void> pump(
    WidgetTester tester, {
    AssistantChatController? chatController,
    bool applies = true,
    bool hasLlamaRuntime = true,
    bool hasMcp = true,
    LlamaRuntimeService? runtime,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(2000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiTab(
            chatController: chatController,
            applies: applies,
            hasLlamaRuntime: hasLlamaRuntime,
            hasMcp: hasMcp,
            runtime: runtime ?? makeRuntime(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(Duration.zero);
  }

  testWidgets('Models needs llama.cpp, so an iPhone does not get it', (
    tester,
  ) async {
    await pump(
      tester,
      chatController: makeChatController(),
      hasLlamaRuntime: false,
    );
    expect(find.text('Models'), findsNothing);

    expect(find.text('Chat'), findsOneWidget);

    await pump(tester);
    expect(find.text('Models'), findsOneWidget);
  });

  testWidgets('where no model could answer, the tab says so and stops', (
    tester,
  ) async {
    await pump(tester, applies: false);
    expect(find.byType(SegmentedButton<AiSection>), findsNothing);
    expect(find.textContaining('a model on your own device'), findsOneWidget);
  });

  testWidgets('Tools follows the MCP sign-in, not the tab', (tester) async {
    await pump(tester);
    expect(find.text('Tools'), findsOneWidget);

    await pump(tester, chatController: makeChatController(), hasMcp: false);
    expect(find.text('Tools'), findsNothing);
  });

  testWidgets('the not-ready note offers a download only where one exists', (
    tester,
  ) async {
    await pump(tester, chatController: makeChatController());
    expect(find.text('Open Models'), findsOneWidget);

    await pump(
      tester,
      chatController: makeChatController(),
      hasLlamaRuntime: false,
    );
    expect(find.text('Open Models'), findsNothing);
    expect(find.textContaining('Apple Intelligence'), findsOneWidget);
  });

  testWidgets('a section with nothing behind it never becomes the body', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Chat'), findsNothing);
    expect(find.text('Models'), findsOneWidget);
  });

  testWidgets('Chat with no model yet stays visible and says what is '
      'missing', (tester) async {
    final assistant = AssistantService(
      backends: [_FakeBackend(available: false)],
      cache: AssistantCache(),
    );
    await pump(
      tester,
      chatController: AssistantChatController(assistant: assistant),
    );

    expect(find.text('Chat'), findsOneWidget);
    expect(find.textContaining('none is ready yet'), findsOneWidget);
    expect(find.text('Open Models'), findsOneWidget);
  });

  testWidgets('the notice sends you to Models, where the download is', (
    tester,
  ) async {
    final assistant = AssistantService(
      backends: [_FakeBackend(available: false)],
      cache: AssistantCache(),
    );
    await pump(
      tester,
      chatController: AssistantChatController(assistant: assistant),
    );

    await tester.tap(find.text('Open Models'));
    await tester.pump();
    expect(find.textContaining('runs entirely on this computer'), findsWidgets);
  });

  testWidgets('Chat drops the notice once a backend can answer', (
    tester,
  ) async {
    final assistant = availableAssistant();
    await pump(
      tester,
      chatController: AssistantChatController(assistant: assistant),
    );

    expect(find.text('Chat'), findsOneWidget);
    expect(find.textContaining('none is ready yet'), findsNothing);
  });

  testWidgets('a finished download clears the notice without a restart', (
    tester,
  ) async {
    final backend = _FakeBackend(available: false);
    final runtime = makeRuntime();
    await pump(
      tester,
      chatController: AssistantChatController(
        assistant: AssistantService(
          backends: [backend],
          cache: AssistantCache(),
        ),
      ),
      runtime: runtime,
    );
    expect(find.textContaining('none is ready yet'), findsOneWidget);

    backend.available = true;

    await tester.runAsync(
      () => runtime.deleteModel(
        AssistantModel(repoId: 'owner/repo', path: 'model.gguf', sizeBytes: 1),
      ),
    );
    await tester.pump();
    await tester.pump(Duration.zero);

    expect(find.textContaining('none is ready yet'), findsNothing);
  });

  testWidgets('a slow readiness check cannot overwrite a newer answer', (
    tester,
  ) async {
    final backend = _GatedBackend();
    await pump(
      tester,
      chatController: AssistantChatController(
        assistant: AssistantService(
          backends: [backend],
          cache: AssistantCache(),
        ),
      ),
    );
    expect(backend.pending, hasLength(1));

    await tester.tap(find.text('Open Models'));
    await tester.pump();
    await tester.tap(find.text('Chat'));
    await tester.pump();
    expect(backend.pending, hasLength(2));

    backend.pending[1].complete(true);
    await tester.pump();
    expect(find.textContaining('none is ready yet'), findsNothing);

    backend.pending[0].complete(false);
    await tester.pump();
    expect(find.textContaining('none is ready yet'), findsNothing);
  });

  group('tab visibility', () {
    test('the AI tab goes to the roles that may spend the model budget', () {
      for (final role in [
        UserRole.strategy,
        UserRole.admin,
        UserRole.developer,
      ]) {
        expect(
          {role}.visibleTabIndices,
          contains(9),
          reason: '$role should see the AI tab',
        );
        expect({role}.canPublishSummaries, isTrue);
      }
    });

    test('scouters and viewers do not get it', () {
      expect({UserRole.scouter}.visibleTabIndices, isNot(contains(9)));
      expect({UserRole.viewer}.visibleTabIndices, isNot(contains(9)));
    });

    test('it is a secondary tab, so it never crowds the bottom bar', () {
      expect({UserRole.strategy}.primaryTabIndices, isNot(contains(9)));
      expect({UserRole.strategy}.secondaryTabIndices, contains(9));
    });
  });
}

class _GatedBackend implements AssistantBackend {
  final List<Completer<bool>> pending = <Completer<bool>>[];

  @override
  Future<bool> isAvailable() {
    final completer = Completer<bool>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async =>
      AssistantSummary(
        text: 'ok',
        generatedAt: DateTime.now().toUtc(),
        model: 'test-model',
        source: AssistantSource.local,
      );
}

class _FakeBackend implements AssistantBackend {
  _FakeBackend({required this.available});

  bool available;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async =>
      AssistantSummary(
        text: 'ok',
        generatedAt: DateTime.now().toUtc(),
        model: 'test-model',
        source: AssistantSource.local,
      );
}

AssistantService availableAssistant() => AssistantService(
  backends: [_FakeBackend(available: true)],
  cache: AssistantCache(),
);
