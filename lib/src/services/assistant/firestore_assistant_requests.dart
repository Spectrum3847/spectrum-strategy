import 'package:cloud_firestore/cloud_firestore.dart';

import '../spectrum_auth_service.dart';
import 'assistant_backend.dart';
import 'assistant_requests.dart';
import 'remote_assistant_cache.dart';

class FirestoreAssistantRequests implements RemoteAssistantRequests {
  FirestoreAssistantRequests({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collection = 'assistantRequests';

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

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
      await _firestore
          .collection(collection)
          .doc(pending.id)
          .set(pending.toJson());
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<PendingAssistantRequest>> open() async {
    try {
      final docs = await _firestore.collection(collection).limit(50).get();
      return [
        for (final doc in docs.docs)
          if ((doc.data()['cacheKey'] as String? ?? '').isNotEmpty &&
              (doc.data()['prompt'] as String? ?? '').isNotEmpty)
            PendingAssistantRequest.fromJson(doc.data()),
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
      await _firestore.collection(collection).doc(request.id).update({
        'claimedBy': uid,
        'claimedAt': DateTime.now().toUtc().toIso8601String(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> remove(String cacheKey) async {
    try {
      await _firestore
          .collection(collection)
          .doc(assistantCacheDocId(cacheKey))
          .delete();
    } catch (_) {}
  }
}
