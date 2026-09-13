import 'package:firestore_client/firestore_client.dart' as fc;

import '../spectrum_auth_service.dart';
import 'assistant_backend.dart';
import 'assistant_requests.dart';
import 'remote_assistant_cache.dart';

class DesktopAssistantRequests implements RemoteAssistantRequests {
  DesktopAssistantRequests({
    required this._authService,
    required this._firestore,
  });

  static const String collection = 'assistantRequests';

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;

  @override
  Future<bool> post(AssistantRequest request) async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return false;
    final pending = PendingAssistantRequest.fromRequest(
      request,
      requestedBy: uid,
      requestedAt: DateTime.now().toUtc(),
    );
    try {
      await _firestore.setDocument(
        '$collection/${pending.id}',
        pending.toJson(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<PendingAssistantRequest>> open() async {
    try {
      final docs = await _firestore.runQuery(collection, limit: 50);
      return [
        for (final doc in docs)
          if (!doc.fromCache &&
              (doc.fields['cacheKey'] as String? ?? '').isNotEmpty &&
              (doc.fields['prompt'] as String? ?? '').isNotEmpty)
            PendingAssistantRequest.fromJson(doc.fields),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> claim(PendingAssistantRequest request) async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return false;
    try {
      await _firestore.commitUpdate(
        '$collection/${request.id}',
        fields: {
          'claimedBy': uid,
          'claimedAt': DateTime.now().toUtc().toIso8601String(),
        },
        updateMask: const ['claimedBy', 'claimedAt'],
        mustExist: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> remove(String cacheKey) async {
    try {
      await _firestore.deleteDocument(
        '$collection/${assistantCacheDocId(cacheKey)}',
      );
    } catch (_) {}
  }
}
