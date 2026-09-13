import 'package:cloud_firestore/cloud_firestore.dart';

import '../spectrum_auth_service.dart';
import 'assistant_backend.dart';
import 'remote_assistant_cache.dart';

class FirestoreRemoteAssistantCache implements RemoteAssistantCache {
  FirestoreRemoteAssistantCache({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collection = 'assistantSummaries';

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  @override
  Future<AssistantSummary?> read(String cacheKey) async {
    try {
      final doc = await _firestore
          .collection(collection)
          .doc(assistantCacheDocId(cacheKey))
          .get();
      final data = doc.data();
      if (data == null) return null;
      return AssistantSummary.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String cacheKey, AssistantSummary summary) async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _firestore
          .collection(collection)
          .doc(assistantCacheDocId(cacheKey))
          .set({
            'cacheKey': cacheKey,
            ...summary.toJson(),
            'authorUid': uid,
            'updatedAt': now,
            'updatedAtTs': FieldValue.serverTimestamp(),
          });
    } catch (_) {}
  }
}
