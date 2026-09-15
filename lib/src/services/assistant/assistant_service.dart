import 'dart:async';

import 'assistant_backend.dart';
import 'assistant_cache.dart';
import 'assistant_requests.dart';

class AssistantService {
  AssistantService({
    required List<AssistantBackend> backends,
    required this._cache,
    this._shared,
    this.minimumGap = const Duration(seconds: 4),
    this.sharedWait = const Duration(minutes: 2),
    this.sharedPollEvery = const Duration(seconds: 10),
  }) : _backends = List.unmodifiable(backends);

  final List<AssistantBackend> _backends;
  final AssistantCache _cache;
  final RemoteAssistantRequests? _shared;

  final Duration sharedWait;

  final Duration sharedPollEvery;

  final Duration minimumGap;

  Future<void> _gate = Future<void>.value();
  DateTime? _lastRationedCall;

  Future<bool> isAvailable() async {
    for (final backend in _backends) {
      if (await backend.isAvailable()) {
        return true;
      }
    }
    return false;
  }

  Future<AssistantSummary?> peek(AssistantRequest request) async =>
      _plausible(await _cache.read(request.cacheKey), request);

  AssistantSummary? _plausible(
    AssistantSummary? summary,
    AssistantRequest request,
  ) {
    if (summary == null) {
      return null;
    }
    return looksLikeAnAnswer(summary.text, minimumChars: request.minimumChars)
        ? summary
        : null;
  }

  Future<AssistantSummary> generate(
    AssistantRequest request, {
    bool force = false,
  }) async {
    if (!force) {
      final cached = _plausible(await _cache.read(request.cacheKey), request);
      if (cached != null) {
        return cached;
      }
      final shared = await _askTheTeam(request);
      if (shared != null) {
        return shared;
      }
    }

    final summary = (await _serialize(() => _complete(request)))
        .withCoverage(request.coverage);
    try {
      await _cache.write(request.cacheKey, summary);
    } catch (_) {}
    return summary;
  }

  Future<AssistantSummary> converse(AssistantRequest request) async =>
      (await _serialize(() => _complete(request)))
          .withCoverage(request.coverage);

  Future<void> closeSession(String sessionId) async {
    for (final backend in _backends) {
      if (backend is! AssistantSessionBackend) continue;
      try {
        await (backend as AssistantSessionBackend).closeSession(sessionId);
      } catch (_) {}
    }
  }

  Future<AssistantSummary?> _askTheTeam(AssistantRequest request) async {
    final shared = _shared;
    if (shared == null || await _hasLocalAnswerer()) {
      return null;
    }
    if (!await shared.post(request)) {
      return null;
    }
    final deadline = DateTime.now().add(sharedWait);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(sharedPollEvery);
      final published = _plausible(
        await _cache.read(request.cacheKey),
        request,
      );
      if (published != null) {
        return published;
      }
    }

    await shared.remove(request.cacheKey);
    return null;
  }

  Future<bool> _hasLocalAnswerer() async {
    for (final backend in _backends) {
      if (backend is RationedAssistantBackend) continue;
      if (await backend.isAvailable()) return true;
    }
    return false;
  }

  Future<AssistantSummary> _complete(AssistantRequest request) async {
    final failures = <String>[];
    for (final backend in _backends) {
      if (!await backend.isAvailable()) {
        continue;
      }
      if (backend is RationedAssistantBackend) {
        await _spaceRationedCall();
      }
      try {
        return await backend.complete(request);
      } on AssistantUnavailable catch (error) {
        failures.add(error.reason);
      } catch (error) {
        failures.add('$error');
      }
    }
    throw AssistantUnavailable(
      failures.isEmpty
          ? 'No assistant backend is set up.'
          : failures.join(' | '),
    );
  }

  Future<void> _spaceRationedCall() async {
    final last = _lastRationedCall;
    if (last != null) {
      final since = DateTime.now().difference(last);
      if (since < minimumGap) {
        await Future<void>.delayed(minimumGap - since);
      }
    }
    _lastRationedCall = DateTime.now();
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _gate.then((_) async => action());

    _gate = result.then((_) {}, onError: (_) {});
    return result;
  }
}
