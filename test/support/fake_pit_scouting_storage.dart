import 'dart:convert';

import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_scouting_storage.dart';

class FakePitScoutingStorage implements PitScoutingStorage {
  final Map<String, String> _entries = <String, String>{};

  @override
  Future<List<PitScoutEntry>> loadAll() async {
    final list = _entries.values
        .map(
          (raw) =>
              PitScoutEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        )
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<void> saveEntry(PitScoutEntry entry) async {
    _entries[entry.id] = jsonEncode(entry.toJson());
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
