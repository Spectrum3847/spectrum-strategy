import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/match_brief.dart';

abstract class MatchBriefStorage {
  Future<List<MatchBrief>> loadAll();
  Future<void> saveBrief(MatchBrief brief);

  Future<Set<String>> loadPendingIds();
  Future<void> savePendingIds(Set<String> ids);
}

class SharedPreferencesMatchBriefStorage implements MatchBriefStorage {
  SharedPreferencesMatchBriefStorage({this._preferences});

  static const String _briefsKey = 'match_briefs_v1';
  static const String _pendingIdsKey = 'match_briefs_pending_v1';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _resolvedPreferences async {
    return _preferences ?? SharedPreferences.getInstance();
  }

  Map<String, dynamic> _readMap(SharedPreferences prefs) {
    final raw = prefs.getString(_briefsKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, dynamic>() : {};
  }

  @override
  Future<List<MatchBrief>> loadAll() async {
    final data = _readMap(await _resolvedPreferences);
    final briefs = <MatchBrief>[];
    for (final value in data.values) {
      if (value is! Map) continue;
      try {
        briefs.add(MatchBrief.fromJson(value.cast<String, dynamic>()));
      } catch (_) {
        // Intentionally empty.
      }
    }
    return briefs;
  }

  @override
  Future<void> saveBrief(MatchBrief brief) async {
    final prefs = await _resolvedPreferences;
    final data = _readMap(prefs);
    data[brief.id] = brief.toJson();
    await prefs.setString(_briefsKey, jsonEncode(data));
  }

  @override
  Future<Set<String>> loadPendingIds() async {
    final prefs = await _resolvedPreferences;
    return prefs.getStringList(_pendingIdsKey)?.toSet() ?? <String>{};
  }

  @override
  Future<void> savePendingIds(Set<String> ids) async {
    final prefs = await _resolvedPreferences;
    await prefs.setStringList(_pendingIdsKey, ids.toList());
  }
}
