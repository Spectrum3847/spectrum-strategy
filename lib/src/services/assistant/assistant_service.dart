import 'dart:async';

import 'assistant_backend.dart';
import 'assistant_cache.dart';

class AssistantService {
  AssistantService({
    required List<AssistantBackend> backends,
    required this._cache,
    this.minimumGap = const Duration(seconds: 4),
  }) : _backends = List.unmodifiable(backends);

  final List<AssistantBackend> _backends;
  final AssistantCache _cache;

  final Duration minimumGap;

  Future<void> _gate = Future<void>.value();
  DateTime? _lastCall;

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
    }

    final summary = (await _serialize(() => _complete(request)))
        .withCoverage(request.coverage);
    try {
      await _cache.write(request.cacheKey, summary);
    } catch (_) {}
    return summary;
  }

  Future<AssistantSummary> _complete(AssistantRequest request) async {
    final failures = <String>[];
    for (final backend in _backends) {
      if (!await backend.isAvailable()) {
        continue;
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

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _gate.then((_) async {
      final last = _lastCall;
      if (last != null) {
        final since = DateTime.now().difference(last);
        if (since < minimumGap) {
          await Future<void>.delayed(minimumGap - since);
        }
      }
      _lastCall = DateTime.now();
      return action();
    });

    _gate = result.then((_) {}, onError: (_) {});
    return result;
  }
}
