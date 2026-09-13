import 'dart:convert';

import 'package:spectrumstrategy/src/models/assistant_chat_session.dart';
import 'package:spectrumstrategy/src/services/assistant_chat_store.dart';
import 'package:spectrumstrategy/src/services/remote_chat_store.dart';

class FakeAssistantChatStore implements AssistantChatStorage {
  FakeAssistantChatStore({List<AssistantChatSession>? initial}) {
    for (final session in initial ?? const <AssistantChatSession>[]) {
      _rows[session.id] = jsonEncode(session.toLocalJson());
    }
  }

  final Map<String, String> _rows = <String, String>{};

  final List<String> savedIds = <String>[];
  final List<String> deletedIds = <String>[];

  bool failLoad = false;

  @override
  Future<List<AssistantChatSession>> loadAll() async {
    if (failLoad) throw StateError('cannot read');
    final sessions = [
      for (final raw in _rows.values)
        AssistantChatSession.fromJson(jsonDecode(raw) as Map<String, dynamic>),
    ];
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  @override
  Future<void> save(AssistantChatSession session) async {
    _rows[session.id] = jsonEncode(session.toLocalJson());
    savedIds.add(session.id);
  }

  @override
  Future<void> delete(String id) async {
    _rows.remove(id);
    deletedIds.add(id);
  }

  bool has(String id) => _rows.containsKey(id);
}

class FakeRemoteChatStore implements RemoteChatStore {
  FakeRemoteChatStore({
    List<AssistantChatSession>? incoming,
    this.uid = 'uid-1',
  }) : _incoming = incoming ?? <AssistantChatSession>[];

  final List<AssistantChatSession> _incoming;

  String uid;

  final List<String> written = <String>[];
  final List<String> deleted = <String>[];

  bool failLoad = false;

  bool signedOut = false;

  bool complete = true;

  @override
  Future<RemoteChatSnapshot?> loadAll() async {
    if (failLoad) throw StateError('offline');
    if (signedOut) return null;
    return RemoteChatSnapshot(
      uid: uid,
      sessions: List<AssistantChatSession>.from(_incoming),
      complete: complete,
    );
  }

  @override
  Future<void> write(AssistantChatSession session) async {
    written.add(session.id);
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    _incoming.removeWhere((s) => s.id == id);
  }

  void removeRemotely(String id) => _incoming.removeWhere((s) => s.id == id);

  void addRemotely(AssistantChatSession session) => _incoming.add(session);
}
