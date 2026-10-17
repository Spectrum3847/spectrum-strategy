import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/pick_list.dart';

abstract class PickListStorage {
  Future<List<PickList>> loadAll();
  Future<void> save(PickList list);
  Future<void> delete(String id);

  Future<Set<String>> loadSyncedIds();
  Future<void> saveSyncedIds(Set<String> ids);
}

class SharedPreferencesPickListStorage implements PickListStorage {
  SharedPreferencesPickListStorage({this._preferences});

  static const String _key = 'pick_lists_v1';
  static const String _syncedIdsKey = 'pick_lists_synced_ids_v1';

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
  Future<List<PickList>> loadAll() async {
    final prefs = await _prefs;
    final map = await _read(prefs);
    final lists = map.values
        .whereType<Map>()
        .map((e) => PickList.fromJson(e.cast<String, dynamic>()))
        .toList();
    lists.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return lists;
  }

  @override
  Future<void> save(PickList list) async {
    final prefs = await _prefs;
    final map = await _read(prefs);
    map[list.id] = list.toJson();
    await prefs.setString(_key, jsonEncode(map));
  }

  @override
  Future<void> delete(String id) async {
    final prefs = await _prefs;
    final map = await _read(prefs);
    map.remove(id);
    await prefs.setString(_key, jsonEncode(map));
  }

  @override
  Future<Set<String>> loadSyncedIds() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_syncedIdsKey);
    if (raw == null || raw.isEmpty) {
      return <String>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.map((e) => e.toString()).toSet();
    }
    return <String>{};
  }

  @override
  Future<void> saveSyncedIds(Set<String> ids) async {
    final prefs = await _prefs;
    await prefs.setString(_syncedIdsKey, jsonEncode(ids.toList()));
  }
}
