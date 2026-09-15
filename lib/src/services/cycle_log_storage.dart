import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cycle_log.dart';

abstract class CycleLogStorage {
  Future<List<CycleLog>> loadAll();
  Future<void> save(CycleLog log);
  Future<void> delete(String key);
}

class SharedPreferencesCycleLogStorage implements CycleLogStorage {
  SharedPreferencesCycleLogStorage({this._preferences});

  static const String _key = 'cycle_logs_v1';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ?? SharedPreferences.getInstance();

  Future<Map<String, dynamic>> _read(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? decoded.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  @override
  Future<List<CycleLog>> loadAll() async {
    final prefs = await _prefs;
    final map = await _read(prefs);
    final logs = <CycleLog>[];
    for (final entry in map.values.whereType<Map>()) {
      try {
        logs.add(CycleLog.fromJson(entry.cast<String, dynamic>()));
      } catch (_) {}
    }
    return logs;
  }

  @override
  Future<void> save(CycleLog log) async {
    final prefs = await _prefs;
    final map = await _read(prefs);
    map[log.key] = log.toJson();
    await prefs.setString(_key, jsonEncode(map));
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await _prefs;
    final map = await _read(prefs);
    map.remove(key);
    await prefs.setString(_key, jsonEncode(map));
  }
}
