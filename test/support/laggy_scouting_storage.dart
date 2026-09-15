import 'dart:async';
import 'dart:convert';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_storage.dart';

class LaggyScoutingStorage implements ScoutingStorage {
  final List<ScoutEntry> savedEntries = <ScoutEntry>[];
  final List<String> deletedIds = <String>[];
  final Map<String, String> _entries = <String, String>{};
  Completer<void>? firstSaveGate;

  @override
  Future<List<ScoutEntry>> loadAll() async {
    final entries = _entries.values
        .map(
          (raw) => ScoutEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        )
        .toList();
    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries;
  }

  @override
  Future<void> saveEntry(ScoutEntry entry) async {
    final clone = ScoutEntry.fromJson(entry.toJson());
    savedEntries.add(clone);
    _entries[entry.id] = jsonEncode(entry.toJson());
    final gate = firstSaveGate;
    if (gate != null) {
      await gate.future;
    }
  }

  final List<List<ScoutEntry>> savedBatches = <List<ScoutEntry>>[];

  @override
  Future<void> saveEntries(Iterable<ScoutEntry> entries) async {
    final list = entries.toList();
    savedBatches.add(list);
    for (final entry in list) {
      await saveEntry(entry);
    }
  }

  @override
  Future<void> deleteEntry(String id) async {
    deletedIds.add(id);
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
