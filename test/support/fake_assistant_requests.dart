import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_requests.dart';

class FakeAssistantRequests implements RemoteAssistantRequests {
  final Map<String, PendingAssistantRequest> queue = {};
  bool postAnswer = true;
  bool claimAnswer = true;
  String uid = 'worker-uid';

  final List<String> posted = [];
  final List<String> claimed = [];
  final List<String> removed = [];

  @override
  Future<bool> post(AssistantRequest request) async {
    posted.add(request.cacheKey);
    if (!postAnswer) return false;
    queue[request.cacheKey] = PendingAssistantRequest.fromRequest(
      request,
      requestedBy: 'poster-uid',
      requestedAt: DateTime.now().toUtc(),
    );
    return true;
  }

  @override
  Future<List<PendingAssistantRequest>> open() async =>
      queue.values.toList(growable: false);

  @override
  Future<bool> claim(PendingAssistantRequest request) async {
    claimed.add(request.cacheKey);
    if (!claimAnswer) return false;
    queue[request.cacheKey] = PendingAssistantRequest.fromJson({
      ...request.toJson(),
      'claimedBy': uid,
      'claimedAt': DateTime.now().toUtc().toIso8601String(),
    });
    return true;
  }

  @override
  Future<void> remove(String cacheKey) async {
    removed.add(cacheKey);
    queue.remove(cacheKey);
  }
}
