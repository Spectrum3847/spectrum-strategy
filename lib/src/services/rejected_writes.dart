import 'package:firestore_client/firestore_client.dart' as fc;

import 'pending_push_queue.dart';

class RejectedWrites {
  final Map<String, _Refusal> _refusals = <String, _Refusal>{};

  bool get isNotEmpty => _refusals.isNotEmpty;

  String? get reason => _refusals.isEmpty ? null : _refusals.values.last.reason;

  bool contains(String id) => _refusals.containsKey(id);

  static String? refusalReason(Object error) {
    if (error is fc.FirestoreApiException &&
        (error.statusCode == 403 || error.status == 'PERMISSION_DENIED')) {
      return error.message;
    }
    return null;
  }

  Future<void> recordFailure(
    PendingPushQueue queue,
    String collection,
    String id,
    Object error, {
    required DateTime at,
  }) async {
    _refusals.remove(id);
    final reason = refusalReason(error);
    if (reason == null) {
      await queue.mark(collection, id);
      return;
    }
    _refusals[id] = _Refusal(at.toUtc(), reason);
    await queue.clear(collection, id);
  }

  void remove(String id) => _refusals.remove(id);

  void supersede(String id, DateTime remoteUpdatedAt) {
    final refusal = _refusals[id];
    if (refusal != null && !remoteUpdatedAt.toUtc().isBefore(refusal.at)) {
      _refusals.remove(id);
    }
  }

  void clear() => _refusals.clear();
}

class _Refusal {
  const _Refusal(this.at, this.reason);

  final DateTime at;
  final String reason;
}
