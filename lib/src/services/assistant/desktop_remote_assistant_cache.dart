import 'package:firestore_client/firestore_client.dart' as fc;

import '../spectrum_auth_service.dart';
import 'assistant_backend.dart';
import 'remote_assistant_cache.dart';

class DesktopRemoteAssistantCache implements RemoteAssistantCache {
  DesktopRemoteAssistantCache({
    required this._authService,
    required this._firestore,
  });

  static const String collection = 'assistantSummaries';

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;

  @override
  Future<AssistantSummary?> read(String cacheKey) async {
    try {
      final doc = await _firestore.getDocument(
        '$collection/${assistantCacheDocId(cacheKey)}',
      );
      if (doc == null) return null;
      return AssistantSummary.fromJson(doc.fields);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String cacheKey, AssistantSummary summary) async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    try {
      final now = DateTime.now().toUtc();
      await _firestore.setDocument(
        '$collection/${assistantCacheDocId(cacheKey)}',
        {
          'cacheKey': cacheKey,
          ...summary.toJson(),
          'authorUid': uid,
          'updatedAt': now.toIso8601String(),

          'updatedAtTs': now,
        },
      );
    } catch (_) {}
  }
}
