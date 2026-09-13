import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/assistant_chat_session.dart';
import '../services/assistant/assistant_backend.dart';
import '../services/assistant/assistant_chat.dart';
import '../services/assistant/assistant_service.dart';
import '../services/assistant_chat_store.dart';
import '../services/remote_chat_store.dart';

enum AssistantChatMessageKind { user, assistant, error }

class AssistantChatMessage {
  const AssistantChatMessage.user(this.text)
    : kind = AssistantChatMessageKind.user,
      source = null,
      model = null;

  const AssistantChatMessage.assistant(
    this.text, {
    required this.source,
    required this.model,
  }) : kind = AssistantChatMessageKind.assistant;

  const AssistantChatMessage.error(this.text)
    : kind = AssistantChatMessageKind.error,
      source = null,
      model = null;

  final AssistantChatMessageKind kind;
  final String text;

  final AssistantSource? source;

  final String? model;
}

class AssistantChatController extends ChangeNotifier {
  AssistantChatController({
    required this._assistant,
    this._storage,
    this._remote,
    String Function()? idFactory,
    DateTime Function()? clock,
  }) : _idFactory = idFactory ?? _defaultId,
       _now = clock ?? DateTime.now;

  final AssistantService _assistant;
  final AssistantChatStorage? _storage;

  final RemoteChatStore? _remote;

  final String Function() _idFactory;
  final DateTime Function() _now;

  static String _defaultId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Future<void> _saveQueue = Future<void>.value();

  List<AssistantChatSession> _sessions = <AssistantChatSession>[];
  String? _activeId;
  bool _loaded = false;

  List<AssistantChatSession> get sessions => List.unmodifiable(_sessions);

  bool get isLoaded => _loaded;

  AssistantChatSession? get activeSession {
    for (final session in _sessions) {
      if (session.id == _activeId) return session;
    }
    return null;
  }

  String? get activeId => _activeId;

  Future<void> bootstrap() async {
    if (_loaded) return;
    final storage = _storage;
    if (storage != null) {
      try {
        final load = _saveQueue.then((_) => storage.loadAll());
        _saveQueue = load.then((_) {}).catchError((_) {});
        _sessions = await load;
      } catch (_) {
        _sessions = <AssistantChatSession>[];
      }
    }
    if (_sessions.isEmpty) {
      _sessions = [_blankSession()];
    }
    _activeId = _sessions.first.id;
    _loaded = true;
    notifyListeners();
    _pull = _pullRemote();
  }

  Future<void>? _pull;

  Future<void> _pullRemote() async {
    final remote = _remote;
    if (remote == null) return;
    final RemoteChatSnapshot? snapshot;
    try {
      snapshot = await remote.loadAll();
    } catch (_) {
      return;
    }

    if (snapshot == null) return;

    final byId = <String, AssistantChatSession>{
      for (final session in _sessions) session.id: session,
    };
    var changed = false;
    for (final session in snapshot.sessions) {
      session.syncedUid = snapshot.uid;
      final local = byId[session.id];
      if (local == null || session.updatedAt.isAfter(local.updatedAt)) {
        byId[session.id] = session;
        _persistLocalOnly(session);
        changed = true;
      } else if (local.syncedUid != snapshot.uid) {
        local.syncedUid = snapshot.uid;
        _persistLocalOnly(local);
      }
    }

    final present = <String>{for (final s in snapshot.sessions) s.id};
    for (final local in byId.values.toList()) {
      if (!_deletedElsewhere(local, snapshot, present)) continue;
      byId.remove(local.id);
      _deleteLocalOnly(local.id);
      changed = true;
    }
    if (!changed) return;

    _sessions = byId.values.toList()
      ..removeWhere((s) => s.isEmpty && s.id != _activeId)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (_sessions.isEmpty) {
      _sessions = [_blankSession()];
    }
    if (!_sessions.any((s) => s.id == _activeId)) {
      _activeId = _sessions.first.id;
    }
    notifyListeners();
  }

  bool _deletedElsewhere(
    AssistantChatSession local,
    RemoteChatSnapshot snapshot,
    Set<String> present,
  ) {
    if (present.contains(local.id)) return false;

    if (local.syncedUid != snapshot.uid) return false;

    final oldest = snapshot.oldest;
    if (!snapshot.complete &&
        oldest != null &&
        !local.updatedAt.isAfter(oldest)) {
      return false;
    }
    return true;
  }

  void _deleteLocalOnly(String id) {
    final storage = _storage;
    if (storage == null) return;
    _saveQueue = _saveQueue.then((_) => storage.delete(id)).catchError((_) {});
  }

  Future<void> refresh() async {
    if (!_loaded) return bootstrap();
    final pull = _pullRemote();
    _pull = pull;
    await pull;
  }

  void _persistLocalOnly(AssistantChatSession session) {
    final storage = _storage;
    if (storage == null) return;
    final snapshot = AssistantChatSession.fromJson(session.toLocalJson());
    _saveQueue = _saveQueue
        .then((_) => storage.save(snapshot))
        .catchError((_) {});
  }

  AssistantChatSession _blankSession() {
    final now = _now();
    return AssistantChatSession(
      id: _idFactory(),
      createdAt: now,
      updatedAt: now,
    );
  }

  void newChat() {
    final active = activeSession;
    if (active != null && active.isEmpty) return;
    final session = _blankSession();
    _sessions.insert(0, session);
    _activeId = session.id;
    notifyListeners();
  }

  void selectChat(String id) {
    if (_activeId == id) return;
    if (!_sessions.any((s) => s.id == id)) return;
    _activeId = id;
    notifyListeners();
  }

  Future<void> deleteChat(String id) async {
    _sessions.removeWhere((s) => s.id == id);

    unawaited(_assistant.closeSession(id));
    if (_sessions.isEmpty) {
      _sessions = [_blankSession()];
    }
    if (_activeId == id) {
      _activeId = _sessions.first.id;
    }
    notifyListeners();
    final storage = _storage;
    if (storage != null) {
      _saveQueue = _saveQueue
          .then((_) => storage.delete(id))
          .catchError((_) {});
      await _saveQueue;
    }

    await _remote?.delete(id);
  }

  Future<void> retryLast() async {
    if (_sending) return;
    final session = activeSession;
    if (session == null) return;
    final question = _takeBackLastExchange(session);
    if (question == null) return;
    notifyListeners();
    await send(question);
  }

  String? _takeBackLastExchange(AssistantChatSession session) {
    final messages = session.messages;
    final asked = messages.lastIndexWhere(
      (m) => m.kind == AssistantChatMessageKind.user,
    );
    if (asked < 0) return null;
    final question = messages[asked].text;
    final answered = messages
        .skip(asked + 1)
        .any((m) => m.kind == AssistantChatMessageKind.assistant);
    messages.removeRange(asked, messages.length);

    if (answered) {
      for (var i = 0; i < 2 && session.turns.isNotEmpty; i++) {
        session.turns.removeLast();
      }
    }
    return question;
  }

  void selectModel(String? modelId) {
    final active = activeSession;
    if (active == null || active.modelId == modelId) return;
    active.modelId = modelId;
    notifyListeners();
    _persist(active);
  }

  void _persist(AssistantChatSession session) {
    final storage = _storage;
    final remote = _remote;
    if (storage == null && remote == null) return;

    final snapshot = AssistantChatSession.fromJson(session.toLocalJson());
    if (storage != null) {
      _saveQueue = _saveQueue
          .then((_) => storage.save(snapshot))
          .catchError((_) {});
    }

    if (remote != null) unawaited(remote.write(snapshot));
  }

  Future<bool> isAvailable() => _assistant.isAvailable();

  static const String _cacheKey = 'assistant-chat';

  bool _sending = false;

  List<AssistantChatMessage> get messages =>
      List.unmodifiable(activeSession?.messages ?? const []);

  bool get isSending => _sending;

  Future<void> send(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _sending) {
      return;
    }

    _sending = true;
    notifyListeners();

    AssistantChatSession? session;
    try {
      if (!_loaded) await bootstrap();
      session = activeSession;
      if (session == null) return;

      session.titleFrom(trimmed);
      session.messages.add(AssistantChatMessage.user(trimmed));
      session.updatedAt = _now();
      _touch(session);
      notifyListeners();

      final summary = await _assistant.converse(
        AssistantRequest(
          cacheKey: _cacheKey,
          prompt: trimmed,
          system: assistantChatSystemPrompt,
          compactSystem: assistantChatSystemPromptCompact,
          history: boundAssistantChatHistory(session.turns),
          useTools: true,
          modelId: session.modelId,

          sessionId: session.id,
        ),
      );
      session.turns.add(
        AssistantTurn(role: AssistantTurnRole.user, content: trimmed),
      );
      session.turns.add(
        AssistantTurn(role: AssistantTurnRole.assistant, content: summary.text),
      );
      session.messages.add(
        AssistantChatMessage.assistant(
          summary.text,
          source: summary.source,
          model: summary.model,
        ),
      );
    } on AssistantUnavailable catch (error) {
      session?.messages.add(AssistantChatMessage.error(error.reason));
    } catch (error) {
      session?.messages.add(AssistantChatMessage.error('$error'));
    } finally {
      _sending = false;
      final sent = session;
      sent?.trim();

      if (sent != null && _sessions.any((s) => s.id == sent.id)) {
        sent.updatedAt = _now();
        _persist(sent);
      }
      notifyListeners();
    }
  }

  void _touch(AssistantChatSession session) {
    _sessions
      ..removeWhere((s) => s.id == session.id)
      ..insert(0, session);
  }

  void clear() {
    final session = activeSession;
    if (session == null) return;
    session.messages.clear();
    session.turns.clear();
    session.title = null;
    session.updatedAt = _now();
    notifyListeners();
    _persist(session);
  }

  @visibleForTesting
  Future<void> settle() async {
    await _pull;
    await _saveQueue;
  }
}
