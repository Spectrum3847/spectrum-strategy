import 'dart:convert';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_storage.dart';

class FakeScoutingStorage implements ScoutingStorage {
  final Map<String, String> _entries = <String, String>{};

  Map<String, String> get rawEntries =>
      Map<String, String>.unmodifiable(_entries);

  @override
  Future<List<ScoutEntry>> loadAll() async {
    final list = _entries.values
        .map(
          (raw) => ScoutEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        )
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<void> saveEntry(ScoutEntry entry) async {
    _entries[entry.id] = jsonEncode(entry.toJson());
  }

  @override
  Future<void> saveEntries(Iterable<ScoutEntry> entries) async {
    for (final entry in entries) {
      await saveEntry(entry);
    }
  }

  @override
  Future<void> deleteEntry(String id) async {
    _entries.remove(id);
  }

  Set<String> syncedIds = <String>{};

  @override
  Future<Set<String>> loadSyncedIds() async => Set<String>.of(syncedIds);

  @override
  Future<void> saveSyncedIds(Set<String> ids) async {
    syncedIds = Set<String>.of(ids);
  }
}
