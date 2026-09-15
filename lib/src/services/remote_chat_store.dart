library;

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/assistant_chat_session.dart';
import 'spectrum_auth_service.dart';

class RemoteChatSnapshot {
  RemoteChatSnapshot({
    required this.uid,
    required this.sessions,
    required this.complete,
  });

  final String uid;

  final List<AssistantChatSession> sessions;

  final bool complete;

  DateTime? get oldest {
    DateTime? oldest;
    for (final session in sessions) {
      if (oldest == null || session.updatedAt.isBefore(oldest)) {
        oldest = session.updatedAt;
      }
    }
    return oldest;
  }
}

abstract class RemoteChatStore {
  Future<RemoteChatSnapshot?> loadAll();

  Future<void> write(AssistantChatSession session);

  Future<void> delete(String id);
}

class DesktopRemoteChatStore implements RemoteChatStore {
  DesktopRemoteChatStore({
    required this._authService,
    required this._firestore,
  });

  static const String collection = 'assistantChats';

  static const int maxChats = 200;

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;

  @override
  Future<RemoteChatSnapshot?> loadAll() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return null;
    try {
      final docs = await _firestore.runQuery(
        collection,

        filters: [fc.FieldFilter('authorUid', 'EQUAL', uid)],
        orderBy: 'updatedAt',
        descending: true,
        limit: maxChats,
      );
      final sessions = <AssistantChatSession>[];
      for (final doc in docs) {
        try {
          sessions.add(AssistantChatSession.fromJson(doc.fields));
        } catch (_) {
          continue;
        }
      }
      return RemoteChatSnapshot(
        uid: uid,
        sessions: sessions,

        complete: docs.length < maxChats,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(AssistantChatSession session) async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    try {
      final now = DateTime.now().toUtc();
      await _firestore.setDocument('$collection/${session.id}', {
        ...session.toJson(),
        'authorUid': uid,

        'updatedAtTs': now,
      });
    } catch (_) {}
  }

  @override
  Future<void> delete(String id) async {
    if (_authService.currentUser?.uid == null) return;
    try {
      await _firestore.deleteDocument('$collection/$id');
    } catch (_) {}
  }
}
