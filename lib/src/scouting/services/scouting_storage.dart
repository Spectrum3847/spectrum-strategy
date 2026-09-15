import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/scout_entry.dart';

abstract class ScoutingStorage {
  Future<List<ScoutEntry>> loadAll();
  Future<void> saveEntry(ScoutEntry entry);

  Future<void> saveEntries(Iterable<ScoutEntry> entries);
  Future<void> deleteEntry(String id);

  Future<Set<String>> loadSyncedIds();
  Future<void> saveSyncedIds(Set<String> ids);
}

class SharedPreferencesScoutingStorage implements ScoutingStorage {
  SharedPreferencesScoutingStorage({this._preferences});

  static const String _legacyEntriesKey = 'scouting_entries_v1';

  static const String _entryKeyPrefix = 'scouting_entry_v2_';

  static const String _syncedIdsKey = 'scouting_synced_ids_v1';

  final SharedPreferences? _preferences;
  bool _migrated = false;

  Future<SharedPreferences> get _resolvedPreferences async {
    return _preferences ?? SharedPreferences.getInstance();
  }

  String _entryKey(String id) => '$_entryKeyPrefix$id';

  Future<void> _migrateIfNeeded(SharedPreferences prefs) async {
    if (_migrated) {
      return;
    }
    _migrated = true;
    final legacyRaw = prefs.getString(_legacyEntriesKey);
    if (legacyRaw == null || legacyRaw.isEmpty) {
      return;
    }
    Map<String, dynamic> legacyMap;
    try {
      final decoded = jsonDecode(legacyRaw);
      legacyMap = decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{};
    } catch (_) {
      legacyMap = <String, dynamic>{};
    }
    final ids = legacyMap.keys.toList();
    for (final id in ids) {
      final key = _entryKey(id);
      if (prefs.containsKey(key)) {
        continue;
      }

      await prefs.setString(key, jsonEncode(legacyMap[id]));
    }

    final allPresent = ids.every((id) => prefs.containsKey(_entryKey(id)));
    if (allPresent) {
      await prefs.remove(_legacyEntriesKey);
    }
  }

  @override
  Future<List<ScoutEntry>> loadAll() async {
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);
    final entries = <ScoutEntry>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_entryKeyPrefix)) {
        continue;
      }
      final raw = prefs.getString(key);
      if (raw == null) {
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          continue;
        }
        entries.add(ScoutEntry.fromJson(decoded.cast<String, dynamic>()));
      } catch (_) {}
    }
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries;
  }

  @override
  Future<void> saveEntry(ScoutEntry entry) => saveEntries(<ScoutEntry>[entry]);

  @override
  Future<void> saveEntries(Iterable<ScoutEntry> entries) async {
    final list = entries.toList();
    if (list.isEmpty) {
      return;
    }
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);
    for (final entry in list) {
      await prefs.setString(_entryKey(entry.id), jsonEncode(entry.toJson()));
    }
  }

  @override
  Future<void> deleteEntry(String id) async {
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);

    await prefs.remove(_entryKey(id));
  }

  @override
  Future<Set<String>> loadSyncedIds() async {
    final prefs = await _resolvedPreferences;
    final raw = prefs.getString(_syncedIdsKey);
    if (raw == null || raw.isEmpty) {
      return <String>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['year'] != DateTime.now().year) {
      return <String>{};
    }
    final ids = decoded['ids'];
    if (ids is List) {
      return ids.map((e) => e.toString()).toSet();
    }
    return <String>{};
  }

  @override
  Future<void> saveSyncedIds(Set<String> ids) async {
    final prefs = await _resolvedPreferences;
    await prefs.setString(
      _syncedIdsKey,
      jsonEncode(<String, dynamic>{
        'year': DateTime.now().year,
        'ids': ids.toList(),
      }),
    );
  }
}
