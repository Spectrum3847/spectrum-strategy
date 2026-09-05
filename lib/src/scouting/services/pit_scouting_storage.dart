import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/pit_scout_entry.dart';

abstract class PitScoutingStorage {
  Future<List<PitScoutEntry>> loadAll();
  Future<void> saveEntry(PitScoutEntry entry);
  Future<void> deleteEntry(String id);

  Future<Set<String>> loadSyncedIds();
  Future<void> saveSyncedIds(Set<String> ids);
}

class SharedPreferencesPitScoutingStorage implements PitScoutingStorage {
  SharedPreferencesPitScoutingStorage({this._preferences});

  static const String _entriesKey = 'pit_scout_entries_v1';
  static const String _syncedIdsKey = 'pit_scout_synced_ids_v1';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _resolvedPreferences async {
    return _preferences ?? SharedPreferences.getInstance();
  }

  Future<Map<String, dynamic>> _readMap(SharedPreferences prefs) async {
    final raw = prefs.getString(_entriesKey);
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }

  Future<void> _writeMap(
    SharedPreferences prefs,
    Map<String, dynamic> data,
  ) async {
    await prefs.setString(_entriesKey, jsonEncode(data));
  }

  @override
  Future<List<PitScoutEntry>> loadAll() async {
    final prefs = await _resolvedPreferences;
    final data = await _readMap(prefs);
    final entries = <PitScoutEntry>[];
    for (final value in data.values) {
      if (value is! Map) {
        continue;
      }
      try {
        entries.add(PitScoutEntry.fromJson(value.cast<String, dynamic>()));
      } catch (_) {}
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries;
  }

  @override
  Future<void> saveEntry(PitScoutEntry entry) async {
    final prefs = await _resolvedPreferences;
    final data = await _readMap(prefs);
    data[entry.id] = entry.toJson();
    await _writeMap(prefs, data);
  }

  @override
  Future<void> deleteEntry(String id) async {
    final prefs = await _resolvedPreferences;
    final data = await _readMap(prefs);
    if (data.remove(id) != null) {
      await _writeMap(prefs, data);
    }
  }

  @override
  Future<Set<String>> loadSyncedIds() async {
    final prefs = await _resolvedPreferences;
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
    final prefs = await _resolvedPreferences;
    await prefs.setString(_syncedIdsKey, jsonEncode(ids.toList()));
  }
}
