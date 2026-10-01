import 'dart:async';

import '../desktop_poll_backoff.dart';
import '../spectrum_auth_service.dart';
import 'assistant_requests.dart';
import 'assistant_service.dart';

class AssistantRequestWorker {
  AssistantRequestWorker({
    required this._requests,
    required this._assistant,
    required this._authService,
    Duration pollEvery = const Duration(seconds: 15),
    this.claimTimeout = const Duration(minutes: 3),
    this.requestTimeout = const Duration(minutes: 10),
  }) : _scheduler = DesktopPollScheduler(pollEvery);

  final RemoteAssistantRequests _requests;
  final AssistantService _assistant;
  final SpectrumAuthService _authService;
  final DesktopPollScheduler _scheduler;

  final Duration claimTimeout;

  final Duration requestTimeout;

  bool _running = false;
  bool _ticking = false;

  void start() {
    if (_running) return;
    _running = true;
    _scheduler.start(tick);
  }

  void stop() {
    _running = false;
    _scheduler.cancel();
  }

  Future<void> tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      await _fill();
      _scheduler.onSuccess();
    } catch (_) {
      _scheduler.onFailure();
    } finally {
      _ticking = false;
    }
  }

  Future<void> _fill() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null || !await _assistant.isAvailable()) return;
    final now = DateTime.now().toUtc();
    for (final pending in await _requests.open()) {
      if (!_wanted(pending, uid, now)) continue;
      if (!await _requests.claim(pending)) continue;
      try {
        await _assistant.generate(pending.toRequest());
      } catch (_) {
        continue;
      }
      await _requests.remove(pending.cacheKey);
    }
  }

  bool _wanted(PendingAssistantRequest pending, String uid, DateTime now) {
    if (pending.requestedBy == uid) return false;
    if (now.difference(pending.requestedAt) > requestTimeout) return false;
    final claimedAt = pending.claimedAt;
    if (pending.claimedBy != null && claimedAt != null) {
      if (now.difference(claimedAt) < claimTimeout) return false;
    }
    return true;
  }
}
