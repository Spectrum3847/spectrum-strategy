import 'dart:convert';

import 'package:spectrumstrategy/src/scouting/models/prescout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/prescouting_storage.dart';

class FakePrescoutingStorage implements PrescoutingStorage {
  final Map<String, String> _entries = <String, String>{};

  @override
  Future<List<PrescoutEntry>> loadAll() async {
    final list = _entries.values
        .map(
          (raw) =>
              PrescoutEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        )
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<void> saveEntry(PrescoutEntry entry) async {
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
