library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/assistant_chat_session.dart';

abstract class AssistantChatStorage {
  Future<List<AssistantChatSession>> loadAll();
  Future<void> save(AssistantChatSession session);
  Future<void> delete(String id);
}

class SharedPreferencesAssistantChatStore implements AssistantChatStorage {
  SharedPreferencesAssistantChatStore({
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsLoader;

  static const String keyPrefix = 'assistant_chat_v1_';
  static const String indexKey = 'assistant_chat_index_v1';

  @override
  Future<List<AssistantChatSession>> loadAll() async {
    final prefs = await _prefsLoader();

    final keys = prefs.getKeys().where((k) => k.startsWith(keyPrefix));
    final sessions = <AssistantChatSession>[];
    for (final key in keys) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        sessions.add(
          AssistantChatSession.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  @override
  Future<void> save(AssistantChatSession session) async {
    final prefs = await _prefsLoader();
    await prefs.setString(
      '$keyPrefix${session.id}',
      jsonEncode(session.toLocalJson()),
    );
    await _reindex(prefs);
  }

  @override
  Future<void> delete(String id) async {
    final prefs = await _prefsLoader();
    await prefs.remove('$keyPrefix$id');
    await _reindex(prefs);
  }

  Future<void> _reindex(SharedPreferences prefs) async {
    final ids = prefs
        .getKeys()
        .where((k) => k.startsWith(keyPrefix))
        .map((k) => k.substring(keyPrefix.length))
        .toList();
    await prefs.setStringList(indexKey, ids);
  }
}
