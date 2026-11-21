import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_storage.dart';

const _legacyEntriesKey = 'scouting_entries_v1';
const _entryKeyPrefix = 'scouting_entry_v2_';

Future<SharedPreferences> _prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
  });
  return SharedPreferences.getInstance();
}

void main() {
  test('saveEntry then loadAll round-trips on a fresh install', () async {
    final prefs = await _prefsWith(<String, Object>{});
    final storage = SharedPreferencesScoutingStorage(preferences: prefs);

    final entry = ScoutEntry(matchId: 'match-1', teamNumber: 3847);
    await storage.saveEntry(entry);

    final loaded = await storage.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.single.id, entry.id);

    expect(prefs.getString(_legacyEntriesKey), isNull);
    expect(prefs.getString('$_entryKeyPrefix${entry.id}'), isNotNull);
  });

  test('saveEntries writes every entry as its own key', () async {
    final prefs = await _prefsWith(<String, Object>{});
    final storage = SharedPreferencesScoutingStorage(preferences: prefs);

    final entries = <ScoutEntry>[
      for (var i = 0; i < 5; i++)
        ScoutEntry(id: 'e-$i', matchId: 'match-1', teamNumber: 1000 + i),
    ];
    await storage.saveEntries(entries);

    final loaded = await storage.loadAll();
    expect(loaded.map((e) => e.id).toSet(), entries.map((e) => e.id).toSet());

    final updated = <ScoutEntry>[
      entries[0].copyWith(notes: 'updated'),
      entries[1].copyWith(notes: 'also updated'),
    ];
    await storage.saveEntries(updated);
    final reloaded = await storage.loadAll();
    expect(reloaded, hasLength(5));
    expect(reloaded.firstWhere((e) => e.id == 'e-0').notes, 'updated');
    expect(reloaded.firstWhere((e) => e.id == 'e-2').notes, isEmpty);
  });

  test('deleteEntry removes the entry key', () async {
    final prefs = await _prefsWith(<String, Object>{});
    final storage = SharedPreferencesScoutingStorage(preferences: prefs);

    final entry = ScoutEntry(matchId: 'match-1', teamNumber: 3847);
    await storage.saveEntry(entry);
    await storage.deleteEntry(entry.id);

    expect(await storage.loadAll(), isEmpty);
    expect(prefs.getString('$_entryKeyPrefix${entry.id}'), isNull);
  });

  test('an entry key written with no other bookkeeping still comes back from '
      'loadAll and can be deleted', () async {
    final entry = ScoutEntry(
      id: 'orphan-1',
      matchId: 'match-1',
      teamNumber: 42,
    );
    final prefs = await _prefsWith(<String, Object>{
      '$_entryKeyPrefix${entry.id}': jsonEncode(entry.toJson()),
    });
    final storage = SharedPreferencesScoutingStorage(preferences: prefs);

    final loaded = await storage.loadAll();
    expect(loaded.map((e) => e.id), <String>['orphan-1']);

    await storage.deleteEntry(entry.id);
    expect(await storage.loadAll(), isEmpty);
    expect(prefs.getString('$_entryKeyPrefix${entry.id}'), isNull);
  });

  test(
    'a legacy whole-blob install migrates every entry, malformed ones included',
    () async {
      final good1 = ScoutEntry(id: 'ok-1', matchId: 'match-1', teamNumber: 254);
      final good2 = ScoutEntry(id: 'ok-2', matchId: 'match-1', teamNumber: 971);
      final legacyBlob = <String, dynamic>{
        good1.id: good1.toJson(),
        good2.id: good2.toJson(),

        'malformed-1': 'not a map',
      };
      final prefs = await _prefsWith(<String, Object>{
        _legacyEntriesKey: jsonEncode(legacyBlob),
      });
      final storage = SharedPreferencesScoutingStorage(preferences: prefs);

      final loaded = await storage.loadAll();
      expect(loaded.map((e) => e.id).toSet(), <String>{'ok-1', 'ok-2'});

      expect(prefs.getString(_legacyEntriesKey), isNull);

      final malformedRaw = prefs.getString('${_entryKeyPrefix}malformed-1');
      expect(malformedRaw, isNotNull);
      expect(jsonDecode(malformedRaw!), 'not a map');
    },
  );

  test('an interrupted migration (some entries already copied) is safe to '
      'repeat and never overwrites what already landed', () async {
    final alreadyCopied = ScoutEntry(
      id: 'ok-1',
      matchId: 'match-1',
      teamNumber: 254,
    );
    final notYetCopied = ScoutEntry(
      id: 'ok-2',
      matchId: 'match-1',
      teamNumber: 971,
    );
    final legacyBlob = <String, dynamic>{
      alreadyCopied.id: alreadyCopied.toJson(),
      notYetCopied.id: notYetCopied.toJson(),
    };

    final prefs = await _prefsWith(<String, Object>{
      _legacyEntriesKey: jsonEncode(legacyBlob),
      '$_entryKeyPrefix${alreadyCopied.id}': jsonEncode(alreadyCopied.toJson()),
    });
    final storage = SharedPreferencesScoutingStorage(preferences: prefs);

    final loaded = await storage.loadAll();
    expect(loaded.map((e) => e.id).toSet(), <String>{'ok-1', 'ok-2'});
    expect(prefs.getString(_legacyEntriesKey), isNull);
  });

  test('migration never overwrites an entry key that was updated since the '
      'legacy blob was written', () async {
    final legacyVersion = ScoutEntry(
      id: 'e-1',
      matchId: 'match-1',
      teamNumber: 1,
      notes: 'legacy value',
    );
    final newerVersion = legacyVersion.copyWith(notes: 'saved after copy');
    final prefs = await _prefsWith(<String, Object>{
      _legacyEntriesKey: jsonEncode(<String, dynamic>{
        legacyVersion.id: legacyVersion.toJson(),
      }),
      '$_entryKeyPrefix${legacyVersion.id}': jsonEncode(newerVersion.toJson()),
    });
    final storage = SharedPreferencesScoutingStorage(preferences: prefs);

    final loaded = await storage.loadAll();
    expect(loaded.single.notes, 'saved after copy');
  });

  test(
    'saveSyncedIds stays season-scoped independent of the entry storage format',
    () async {
      final prefs = await _prefsWith(<String, Object>{});
      final storage = SharedPreferencesScoutingStorage(preferences: prefs);

      await storage.saveSyncedIds(<String>{'a', 'b'});
      expect(await storage.loadSyncedIds(), <String>{'a', 'b'});
    },
  );
}
