import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/assistant_chat_session.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/state/assistant_chat_controller.dart';

import 'support/fake_assistant_chat_store.dart';

void main() {
  var counter = 0;
  String nextId() => 'chat-${++counter}';

  setUp(() => counter = 0);

  AssistantChatController controllerWith(
    FakeAssistantChatStore store, {
    bool available = true,
  }) => AssistantChatController(
    assistant: AssistantService(
      backends: [_FakeBackend(available: available)],
      cache: AssistantCache(),
    ),
    storage: store,
    idFactory: nextId,
    clock: () => DateTime.utc(2026, 1, 2, 12),
  );

  group('bootstrap', () {
    test('opens a blank chat when nothing is saved', () async {
      final controller = controllerWith(FakeAssistantChatStore());

      await controller.bootstrap();

      expect(controller.sessions, hasLength(1));
      expect(controller.activeSession!.isEmpty, isTrue);
      expect(controller.messages, isEmpty);
    });

    test('reopens the most recently used chat', () async {
      final store = FakeAssistantChatStore(
        initial: [
          AssistantChatSession(
            id: 'old',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026, 1, 1),
            title: 'older question',
          ),
          AssistantChatSession(
            id: 'recent',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026, 5, 1),
            title: 'newer question',
          ),
        ],
      );
      final controller = controllerWith(store);

      await controller.bootstrap();

      expect(controller.activeId, 'recent');
      expect(controller.sessions.map((s) => s.id), ['recent', 'old']);
    });

    test('a store that cannot be read still leaves a usable chat', () async {
      final store = FakeAssistantChatStore()..failLoad = true;
      final controller = controllerWith(store);

      await controller.bootstrap();

      expect(controller.sessions, hasLength(1));
      expect(controller.activeSession, isNotNull);
    });

    test('is idempotent', () async {
      final controller = controllerWith(FakeAssistantChatStore());

      await controller.bootstrap();
      final first = controller.activeId;
      await controller.bootstrap();

      expect(controller.activeId, first);
      expect(controller.sessions, hasLength(1));
    });
  });

  group('new chat', () {
    test('does not stack blank chats', () async {
      final controller = controllerWith(FakeAssistantChatStore());
      await controller.bootstrap();

      controller.newChat();
      controller.newChat();

      expect(controller.sessions, hasLength(1));
    });

    test('opens a second chat once the first has been used', () async {
      final store = FakeAssistantChatStore();
      final controller = controllerWith(store);
      await controller.bootstrap();
      await controller.send('how is 3847 doing');

      controller.newChat();

      expect(controller.sessions, hasLength(2));
      expect(controller.activeSession!.isEmpty, isTrue);
      expect(controller.messages, isEmpty);
    });
  });

  group('send', () {
    test('titles a chat from its first question, and does not rename it '
        'afterwards', () async {
      final controller = controllerWith(FakeAssistantChatStore());
      await controller.bootstrap();

      await controller.send('how is 3847 doing');
      expect(controller.activeSession!.displayTitle, 'how is 3847 doing');

      await controller.send('what about 118');
      expect(controller.activeSession!.displayTitle, 'how is 3847 doing');
    });

    test('a long first question is shortened for the sidebar', () async {
      final controller = controllerWith(FakeAssistantChatStore());
      await controller.bootstrap();

      await controller.send('x' * 200);

      expect(controller.activeSession!.displayTitle.length, 60);
      expect(controller.activeSession!.displayTitle, endsWith('...'));
    });

    test('persists the chat', () async {
      final store = FakeAssistantChatStore();
      final controller = controllerWith(store);
      await controller.bootstrap();

      await controller.send('how is 3847 doing');
      await controller.settle();

      expect(store.savedIds, contains(controller.activeId));
      final saved = (await store.loadAll()).single;
      expect(saved.messages, hasLength(2));
      expect(saved.turns, hasLength(2));
    });

    test('a failed turn is shown but never sent back as history', () async {
      final store = FakeAssistantChatStore();
      final controller = controllerWith(store, available: false);
      await controller.bootstrap();

      await controller.send('how is 3847 doing');
      await controller.settle();

      final saved = (await store.loadAll()).single;
      expect(
        saved.messages.map((m) => m.kind),
        contains(AssistantChatMessageKind.error),
      );

      expect(saved.turns, isEmpty);
    });

    test('answering moves a chat to the front of the list', () async {
      final controller = controllerWith(FakeAssistantChatStore());
      await controller.bootstrap();
      await controller.send('first');
      controller.newChat();
      await controller.send('second');
      final older = controller.sessions.last.id;

      controller.selectChat(older);
      await controller.send('back to the first');

      expect(controller.sessions.first.id, older);
    });
  });

  group('a chat that changes under an in-flight question', () {
    test(
      'an answer lands on the chat it was asked in, not the open one',
      () async {
        final gate = Completer<void>();
        final backend = _FakeBackend(available: true, gate: gate);
        final controller = AssistantChatController(
          assistant: AssistantService(
            backends: [backend],
            cache: AssistantCache(),
          ),
          storage: FakeAssistantChatStore(),
          idFactory: nextId,
        );
        await controller.bootstrap();
        final asked = controller.activeId!;

        final pending = controller.send('a slow question');

        controller.newChat();
        final opened = controller.activeId!;
        gate.complete();
        await pending;

        final askedIn = controller.sessions.firstWhere((s) => s.id == asked);
        final openedNow = controller.sessions.firstWhere((s) => s.id == opened);
        expect(askedIn.messages, hasLength(2));
        expect(openedNow.messages, isEmpty);
      },
    );

    test('a chat deleted mid-question is not resurrected by the write that '
        'follows the answer', () async {
      final gate = Completer<void>();
      final backend = _FakeBackend(available: true, gate: gate);
      final store = FakeAssistantChatStore();
      final controller = AssistantChatController(
        assistant: AssistantService(
          backends: [backend],
          cache: AssistantCache(),
        ),
        storage: store,
        idFactory: nextId,
      );
      await controller.bootstrap();
      final doomed = controller.activeId!;

      final pending = controller.send('a slow question');
      await controller.deleteChat(doomed);
      gate.complete();
      await pending;
      await controller.settle();

      expect(store.has(doomed), isFalse);
      expect(controller.sessions.map((s) => s.id), isNot(contains(doomed)));
    });
  });

  group('delete', () {
    test('removes the chat from the list and from the store', () async {
      final store = FakeAssistantChatStore();
      final controller = controllerWith(store);
      await controller.bootstrap();
      await controller.send('first');
      final doomed = controller.activeId!;
      controller.newChat();
      await controller.send('second');
      await controller.settle();

      await controller.deleteChat(doomed);

      expect(controller.sessions.map((s) => s.id), isNot(contains(doomed)));
      expect(store.has(doomed), isFalse);
    });

    test('deleting the open chat opens another one', () async {
      final controller = controllerWith(FakeAssistantChatStore());
      await controller.bootstrap();
      await controller.send('first');
      controller.newChat();
      await controller.send('second');
      final open = controller.activeId!;

      await controller.deleteChat(open);

      expect(controller.activeId, isNotNull);
      expect(controller.activeId, isNot(open));
    });

    test('deleting the last chat leaves a blank one, never none', () async {
      final controller = controllerWith(FakeAssistantChatStore());
      await controller.bootstrap();
      await controller.send('only chat');

      await controller.deleteChat(controller.activeId!);

      expect(controller.sessions, hasLength(1));
      expect(controller.activeSession!.isEmpty, isTrue);
    });
  });

  group('retry', () {
    test('drops the answer and asks the question again', () async {
      final store = FakeAssistantChatStore();
      final controller = controllerWith(store);
      await controller.bootstrap();
      await controller.send('how is 3847 doing');
      await controller.settle();
      expect(controller.messages, hasLength(2));

      await controller.retryLast();
      await controller.settle();

      expect(controller.messages, hasLength(2));
      expect(controller.messages.first.kind, AssistantChatMessageKind.user);
      expect(controller.messages.first.text, 'how is 3847 doing');
      expect(controller.messages.last.kind, AssistantChatMessageKind.assistant);
    });

    test('the discarded answer does not stay in the model history', () async {
      final controller = controllerWith(FakeAssistantChatStore());
      await controller.bootstrap();
      await controller.send('how is 3847 doing');
      await controller.settle();
      expect(controller.activeSession!.turns, hasLength(2));

      await controller.retryLast();
      await controller.settle();

      expect(controller.activeSession!.turns, hasLength(2));
      expect(
        controller.activeSession!.turns.first.content,
        'how is 3847 doing',
      );
    });

    test('an earlier exchange is left alone', () async {
      final controller = controllerWith(FakeAssistantChatStore());
      await controller.bootstrap();
      await controller.send('first question');
      await controller.settle();
      await controller.send('second question');
      await controller.settle();

      await controller.retryLast();
      await controller.settle();

      expect(controller.messages, hasLength(4));
      expect(controller.messages[0].text, 'first question');
      expect(controller.messages[2].text, 'second question');
      expect(controller.activeSession!.turns, hasLength(4));
      expect(controller.activeSession!.turns[0].content, 'first question');
    });

    test(
      'retrying a failed turn does not eat the exchange before it',
      () async {
        final assistant = _FlakyAssistant();
        final controller = AssistantChatController(
          assistant: AssistantService(
            backends: [assistant],
            cache: AssistantCache(),
          ),
          storage: FakeAssistantChatStore(),
          idFactory: nextId,
        );
        await controller.bootstrap();
        await controller.send('first question');
        await controller.settle();
        expect(controller.activeSession!.turns, hasLength(2));

        assistant.fail = true;
        await controller.send('second question');
        await controller.settle();
        expect(controller.messages.last.kind, AssistantChatMessageKind.error);
        expect(controller.activeSession!.turns, hasLength(2));

        assistant.fail = false;
        await controller.retryLast();
        await controller.settle();

        expect(controller.activeSession!.turns, hasLength(4));
        expect(controller.activeSession!.turns[0].content, 'first question');
        expect(controller.activeSession!.turns[2].content, 'second question');
      },
    );

    test('nothing to retry is a no-op, not a crash', () async {
      final controller = controllerWith(FakeAssistantChatStore());
      await controller.bootstrap();

      await controller.retryLast();
      await controller.settle();

      expect(controller.messages, isEmpty);
    });

    test('a retry while a question is in flight is refused', () async {
      final controller = controllerWith(FakeAssistantChatStore());
      await controller.bootstrap();
      await controller.send('how is 3847 doing');
      await controller.settle();

      final inFlight = controller.send('another question');
      await controller.retryLast();
      await inFlight;
      await controller.settle();

      expect(controller.messages, hasLength(4));
      expect(controller.messages[0].text, 'how is 3847 doing');
      expect(controller.messages[2].text, 'another question');
    });
  });

  group('model switching', () {
    test('the model is remembered per chat, not globally', () async {
      final controller = controllerWith(FakeAssistantChatStore());
      await controller.bootstrap();
      await controller.send('first');
      final first = controller.activeId!;
      controller.selectModel('unsloth/Qwen3-4B-GGUF/Qwen3-4B-Q4_K_M.gguf');

      controller.newChat();
      expect(controller.activeSession!.modelId, isNull);

      controller.selectChat(first);
      expect(
        controller.activeSession!.modelId,
        'unsloth/Qwen3-4B-GGUF/Qwen3-4B-Q4_K_M.gguf',
      );
    });

    test('the chosen model is sent with the request', () async {
      final backend = _FakeBackend(available: true);
      final controller = AssistantChatController(
        assistant: AssistantService(
          backends: [backend],
          cache: AssistantCache(),
        ),
        storage: FakeAssistantChatStore(),
        idFactory: nextId,
      );
      await controller.bootstrap();
      controller.selectModel('owner/repo/model.gguf');

      await controller.send('how is 3847 doing');

      expect(backend.lastRequest!.modelId, 'owner/repo/model.gguf');
    });

    test('survives a round trip through the store', () async {
      final store = FakeAssistantChatStore();
      final controller = controllerWith(store);
      await controller.bootstrap();
      await controller.send('first');
      controller.selectModel('owner/repo/model.gguf');
      await controller.settle();

      final reopened = controllerWith(store);
      await reopened.bootstrap();

      expect(reopened.activeSession!.modelId, 'owner/repo/model.gguf');
    });
  });

  group('sync across devices', () {
    AssistantChatSession remoteChat(
      String id,
      String title,
      DateTime updatedAt,
    ) => AssistantChatSession(
      id: id,
      createdAt: DateTime.utc(2026),
      updatedAt: updatedAt,
      title: title,
      messages: [AssistantChatMessage.user(title)],
    );

    AssistantChatController syncing(
      FakeAssistantChatStore store,
      FakeRemoteChatStore remote,
    ) => AssistantChatController(
      assistant: AssistantService(
        backends: [_FakeBackend(available: true)],
        cache: AssistantCache(),
      ),
      storage: store,
      remote: remote,
      idFactory: nextId,
    );

    test('a chat from another device appears, and is saved locally', () async {
      final store = FakeAssistantChatStore();
      final remote = FakeRemoteChatStore(
        incoming: [
          remoteChat('shop-laptop', 'held in the shop', DateTime.utc(2026, 5)),
        ],
      );
      final controller = syncing(store, remote);

      await controller.bootstrap();
      await controller.settle();

      expect(controller.sessions.map((s) => s.id), contains('shop-laptop'));
      expect(store.has('shop-laptop'), isTrue);
    });

    test(
      'the blank chat bootstrap opened is dropped once a real one arrives',
      () async {
        final remote = FakeRemoteChatStore(
          incoming: [
            remoteChat(
              'shop-laptop',
              'held in the shop',
              DateTime.utc(2026, 5),
            ),
          ],
        );
        final controller = syncing(FakeAssistantChatStore(), remote);

        await controller.bootstrap();
        await controller.settle();

        expect(
          controller.sessions.where(
            (s) => s.isEmpty && s.id != controller.activeId,
          ),
          isEmpty,
        );
      },
    );

    test('the newer copy wins, whichever device it came from', () async {
      final local = AssistantChatSession(
        id: 'same',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026, 6),
        title: 'the local edit',
        messages: [AssistantChatMessage.user('the local edit')],
      );
      final store = FakeAssistantChatStore(initial: [local]);
      final remote = FakeRemoteChatStore(
        incoming: [
          remoteChat('same', 'the older remote copy', DateTime.utc(2026, 1)),
        ],
      );
      final controller = syncing(store, remote);

      await controller.bootstrap();
      await controller.settle();

      expect(
        controller.sessions.firstWhere((s) => s.id == 'same').title,
        'the local edit',
      );
    });

    test('a remote copy newer than the local one replaces it', () async {
      final local = AssistantChatSession(
        id: 'same',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026, 1),
        title: 'the stale local copy',
        messages: [AssistantChatMessage.user('stale')],
      );
      final store = FakeAssistantChatStore(initial: [local]);
      final remote = FakeRemoteChatStore(
        incoming: [
          remoteChat('same', 'the newer remote copy', DateTime.utc(2026, 6)),
        ],
      );
      final controller = syncing(store, remote);

      await controller.bootstrap();
      await controller.settle();

      expect(
        controller.sessions.firstWhere((s) => s.id == 'same').title,
        'the newer remote copy',
      );
    });

    test(
      'an offline sync leaves the local chats exactly as they were',
      () async {
        final local = AssistantChatSession(
          id: 'mine',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026, 6),
          title: 'held here',
          messages: [AssistantChatMessage.user('held here')],
        );
        final store = FakeAssistantChatStore(initial: [local]);
        final remote = FakeRemoteChatStore()..failLoad = true;
        final controller = syncing(store, remote);

        await controller.bootstrap();
        await controller.settle();

        expect(controller.sessions.map((s) => s.id), ['mine']);
        expect(controller.activeId, 'mine');
      },
    );

    test('sending pushes the chat to the other devices', () async {
      final remote = FakeRemoteChatStore();
      final controller = syncing(FakeAssistantChatStore(), remote);
      await controller.bootstrap();

      await controller.send('how is 3847 doing');
      await controller.settle();

      expect(remote.written, contains(controller.activeId));
    });

    test('deleting removes it from the other devices too', () async {
      final remote = FakeRemoteChatStore(
        incoming: [remoteChat('doomed', 'delete me', DateTime.utc(2026, 5))],
      );
      final controller = syncing(FakeAssistantChatStore(), remote);
      await controller.bootstrap();
      await controller.settle();

      await controller.deleteChat('doomed');

      expect(remote.deleted, contains('doomed'));
    });

    test('a chat deleted on another device goes away here too', () async {
      final remote = FakeRemoteChatStore(
        incoming: [remoteChat('shared', 'held on both', DateTime.utc(2026, 5))],
      );
      final store = FakeAssistantChatStore();
      final controller = syncing(store, remote);
      await controller.bootstrap();
      await controller.settle();
      expect(controller.sessions.map((s) => s.id), contains('shared'));

      remote.removeRemotely('shared');
      await controller.refresh();
      await controller.settle();

      expect(controller.sessions.map((s) => s.id), isNot(contains('shared')));
      expect(store.has('shared'), isFalse);
    });

    test('a chat this device has never pushed survives a sync that does not '
        'mention it', () async {
      final mine = AssistantChatSession(
        id: 'mine',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026, 6),
        title: 'written on a plane',
        messages: [AssistantChatMessage.user('written on a plane')],
      );
      final store = FakeAssistantChatStore(initial: [mine]);
      final remote = FakeRemoteChatStore(
        incoming: [
          remoteChat('theirs', 'from the shop', DateTime.utc(2026, 5)),
        ],
      );
      final controller = syncing(store, remote);

      await controller.bootstrap();
      await controller.settle();

      expect(controller.sessions.map((s) => s.id), contains('mine'));
      expect(store.has('mine'), isTrue);
    });

    test('a read that could not run deletes nothing', () async {
      final remote = FakeRemoteChatStore(
        incoming: [remoteChat('shared', 'held on both', DateTime.utc(2026, 5))],
      );
      final store = FakeAssistantChatStore();
      final controller = syncing(store, remote);
      await controller.bootstrap();
      await controller.settle();

      remote.signedOut = true;
      await controller.refresh();
      await controller.settle();

      expect(controller.sessions.map((s) => s.id), contains('shared'));
      expect(store.has('shared'), isTrue);
    });

    test('a second lead signing in does not reconcile away the first '
        'lead\'s chats', () async {
      final remote = FakeRemoteChatStore(
        incoming: [remoteChat('hers', 'her chat', DateTime.utc(2026, 5))],
      );
      final store = FakeAssistantChatStore();
      final controller = syncing(store, remote);
      await controller.bootstrap();
      await controller.settle();
      expect(controller.sessions.map((s) => s.id), contains('hers'));

      remote.uid = 'uid-2';
      remote.removeRemotely('hers');
      await controller.refresh();
      await controller.settle();

      expect(controller.sessions.map((s) => s.id), contains('hers'));
      expect(store.has('hers'), isTrue);
    });

    test('a read that filled its window cannot conclude an older chat is '
        'gone', () async {
      final remote = FakeRemoteChatStore(
        incoming: [
          remoteChat('old', 'older chat', DateTime.utc(2026, 5)),
          remoteChat('new', 'newer chat', DateTime.utc(2026, 7)),
        ],
      );
      final store = FakeAssistantChatStore();
      final controller = syncing(store, remote);
      await controller.bootstrap();
      await controller.settle();

      remote.complete = false;
      remote.removeRemotely('old');
      await controller.refresh();
      await controller.settle();

      expect(controller.sessions.map((s) => s.id), contains('old'));
    });

    test(
      'deleting the only synced chat leaves a blank chat, not none',
      () async {
        final only = remoteChat('only', 'the only one', DateTime.utc(2026, 5));
        final remote = FakeRemoteChatStore(incoming: [only]);
        final controller = syncing(
          FakeAssistantChatStore(initial: [only]),
          remote,
        );
        await controller.bootstrap();
        await controller.settle();
        expect(controller.sessions.map((s) => s.id), ['only']);

        remote.removeRemotely('only');
        await controller.refresh();
        await controller.settle();

        expect(controller.sessions, hasLength(1));
        expect(controller.sessions.single.isEmpty, isTrue);
        expect(controller.activeId, controller.sessions.single.id);
      },
    );

    test('refresh brings in a chat written elsewhere mid-session', () async {
      final remote = FakeRemoteChatStore();
      final store = FakeAssistantChatStore();
      final controller = syncing(store, remote);
      await controller.bootstrap();
      await controller.settle();

      remote.addRemotely(
        remoteChat('later', 'written after launch', DateTime.utc(2026, 8)),
      );
      await controller.refresh();
      await controller.settle();

      expect(controller.sessions.map((s) => s.id), contains('later'));
    });

    test('with no remote wired the controller is purely local', () async {
      final store = FakeAssistantChatStore();
      final controller = controllerWith(store);

      await controller.bootstrap();
      await controller.send('local only');
      await controller.settle();

      expect(store.savedIds, isNotEmpty);
    });
  });

  test('a chat is trimmed to what the rules will accept, so it never '
      'silently stops syncing', () async {
    final store = FakeAssistantChatStore();
    final controller = controllerWith(store);
    await controller.bootstrap();

    final session = controller.activeSession!;
    for (var i = 0; i < AssistantChatSession.maxEntries + 20; i++) {
      session.messages.add(AssistantChatMessage.user('q$i'));
      session.turns.add(
        AssistantTurn(role: AssistantTurnRole.user, content: 'q$i'),
      );
    }
    await controller.send('one more');
    await controller.settle();

    expect(session.messages.length, AssistantChatSession.maxEntries);
    expect(session.turns.length, AssistantChatSession.maxEntries);

    expect(session.messages.last.text, 'answer');
    expect(session.messages.first.text, isNot('q0'));
  });

  group('serialization', () {
    test('a session round-trips with every message kind', () {
      final session = AssistantChatSession(
        id: 'a',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
        title: 'a question',
        modelId: 'owner/repo/model.gguf',
        messages: [
          AssistantChatMessage.user('q'),
          const AssistantChatMessage.assistant(
            'a',
            source: AssistantSource.local,
            model: 'test-model',
          ),
          AssistantChatMessage.error('boom'),
        ],
      );

      final restored = AssistantChatSession.fromJson(session.toJson());

      expect(restored.id, 'a');
      expect(restored.title, 'a question');
      expect(restored.modelId, 'owner/repo/model.gguf');
      expect(restored.messages.map((m) => m.kind), [
        AssistantChatMessageKind.user,
        AssistantChatMessageKind.assistant,
        AssistantChatMessageKind.error,
      ]);
      expect(restored.messages[1].source, AssistantSource.local);
      expect(restored.messages[1].model, 'test-model');
    });
  });
}

class _FakeBackend implements AssistantBackend {
  _FakeBackend({required this.available, this.gate});

  final bool available;

  final Completer<void>? gate;

  AssistantRequest? lastRequest;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    lastRequest = request;
    if (gate != null) await gate!.future;
    return AssistantSummary(
      text: 'answer',
      generatedAt: DateTime.utc(2026),
      model: 'test-model',
      source: AssistantSource.local,
    );
  }
}

class _FlakyAssistant implements AssistantBackend {
  bool fail = false;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    if (fail) throw const AssistantUnavailable('the model fell over');
    return AssistantSummary(
      text: 'answer',
      generatedAt: DateTime.now().toUtc(),
      model: 'test-model',
      source: AssistantSource.local,
    );
  }
}
