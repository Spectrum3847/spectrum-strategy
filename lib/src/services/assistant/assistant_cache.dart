import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_backend.dart';
import 'remote_assistant_cache.dart';

class AssistantCache {
  AssistantCache({
    Future<SharedPreferences> Function()? prefsLoader,
    this._remote,
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String prefsKey = 'assistant_summaries_v1';

  static const int maxEntries = 200;

  final Future<SharedPreferences> Function() _prefsLoader;
  final RemoteAssistantCache? _remote;

  Future<AssistantSummary?> read(String cacheKey) async {
    final entries = await _load();
    final local = entries[cacheKey];
    if (local != null) return local;

    final remote = _remote;
    if (remote == null) return null;
    AssistantSummary? shared;
    try {
      shared = await remote.read(cacheKey);
    } catch (_) {
      return null;
    }
    if (shared == null) return null;

    entries[cacheKey] = shared;
    await _save(entries);
    return shared;
  }

  Future<void> write(String cacheKey, AssistantSummary summary) async {
    final entries = await _load();
    entries[cacheKey] = summary;
    if (entries.length > maxEntries) {
      final oldestFirst = entries.entries.toList()
        ..sort((a, b) => a.value.generatedAt.compareTo(b.value.generatedAt));
      for (final stale in oldestFirst.take(entries.length - maxEntries)) {
        entries.remove(stale.key);
      }
    }
    await _save(entries);

    final remote = _remote;
    if (remote == null) return;
    try {
      await remote.write(cacheKey, summary);
    } catch (_) {}
  }

  Future<void> clear() async => (await _prefsLoader()).remove(prefsKey);

  Future<Map<String, AssistantSummary>> _load() async {
    final raw = (await _prefsLoader()).getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      return <String, AssistantSummary>{};
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: AssistantSummary.fromJson(
              entry.value as Map<String, dynamic>,
            ),
      };
    } catch (_) {
      return <String, AssistantSummary>{};
    }
  }

  Future<void> _save(Map<String, AssistantSummary> entries) async {
    final prefs = await _prefsLoader();
    await prefs.setString(
      prefsKey,
      jsonEncode({
        for (final entry in entries.entries) entry.key: entry.value.toJson(),
      }),
    );
  }
}
