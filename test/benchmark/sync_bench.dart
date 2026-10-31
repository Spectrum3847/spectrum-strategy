// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_storage.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

import '../support/fake_scouting_sync_service.dart';

ScoutEntry makeEntry(int i) {
  return ScoutEntry(
    id: 'entry-$i',
    matchId: 'qm${(i ~/ 6) + 1}',
    teamNumber: 1000 + (i % 40),
    alliance: i.isEven ? 'Red' : 'Blue',
    notes: 'Solid cycles, defended late in the match. Entry number $i.',
    authorUid: 'uid-${i % 12}',
    authorDisplayName: 'Scout ${i % 12}',
    updatedAt: DateTime.utc(2026, 3, 1).add(Duration(minutes: i)),
    byPhase: <StrategyPhase, ScoutPhaseData>{
      for (final p in StrategyPhase.values)
        p: ScoutPhaseData(
          score: i % 30,
          penalties: i % 3,
          notes: 'phase note $i',
          counters: <String, int>{
            for (var c = 0; c < 8; c++) 'counter$c': (i + c) % 12,
          },
        ),
    },
    fieldValues: <String, dynamic>{
      for (var f = 0; f < 32; f++) 'field$f': f.isEven ? 'value-$i-$f' : i + f,
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cold sync: empty device receives a full remote snapshot', () async {
    for (final n in <int>[100, 250, 500, 1000]) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final sync = FakeScoutingSyncService();
      final controller = ScoutingController(
        storage: SharedPreferencesScoutingStorage(preferences: prefs),
        syncService: sync,
      );
      await controller.bootstrap();

      final remote = <ScoutEntry>[for (var i = 0; i < n; i++) makeEntry(i)];
      final sw = Stopwatch()..start();
      sync.emitRemote(remote);
      await Future<void>.delayed(Duration.zero);
      await controller.saveNow();
      await controller.saveNow();
      sw.stop();
      print(
        'cold sync N=$n: ${sw.elapsedMilliseconds} ms to drain '
        '(${controller.entries.length} entries)',
      );
      controller.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('steady state: one new remote entry among N', () async {
    for (final n in <int>[100, 250, 500, 1000]) {
      final blob = <String, dynamic>{
        for (var i = 0; i < n; i++) 'entry-$i': makeEntry(i).toJson(),
      };
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.scouting_entries_v1': jsonEncode(blob),
        'flutter.scouting_synced_ids_v1': jsonEncode(<String, dynamic>{
          'year': DateTime.now().year,
          'ids': <String>[for (var i = 0; i < n; i++) 'entry-$i'],
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final sync = FakeScoutingSyncService();
      final controller = ScoutingController(
        storage: SharedPreferencesScoutingStorage(preferences: prefs),
        syncService: sync,
      );
      final swBoot = Stopwatch()..start();
      await controller.bootstrap();
      swBoot.stop();

      final remote = <ScoutEntry>[for (var i = 0; i <= n; i++) makeEntry(i)];
      final sw = Stopwatch()..start();
      sync.emitRemote(remote);
      await Future<void>.delayed(Duration.zero);
      await controller.saveNow();
      await controller.saveNow();
      sw.stop();
      print(
        'steady N=$n: bootstrap=${swBoot.elapsedMilliseconds} ms, '
        'one-new-entry snapshot=${sw.elapsedMilliseconds} ms',
      );
      controller.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('desktop poll: unchanged full snapshot every 30 s', () async {
    for (final n in <int>[100, 250, 500, 1000, 2000]) {
      final entries = <ScoutEntry>[for (var i = 0; i < n; i++) makeEntry(i)];
      final blob = <String, dynamic>{for (final e in entries) e.id: e.toJson()};
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.scouting_entries_v1': jsonEncode(blob),
        'flutter.scouting_synced_ids_v1': jsonEncode(<String, dynamic>{
          'year': DateTime.now().year,
          'ids': <String>[for (final e in entries) e.id],
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final sync = FakeScoutingSyncService();
      final controller = ScoutingController(
        storage: SharedPreferencesScoutingStorage(preferences: prefs),
        syncService: sync,
      );
      await controller.bootstrap();

      final raw = <Map<String, dynamic>>[for (final e in entries) e.toJson()];
      var sw = Stopwatch()..start();
      const iters = 10;
      for (var i = 0; i < iters; i++) {
        raw.map(ScoutEntry.fromJson).toList();
      }
      sw.stop();
      final decodeMs = sw.elapsedMicroseconds / 1000 / iters;

      sw = Stopwatch()..start();
      for (var i = 0; i < iters; i++) {
        sync.emitRemote(entries);
        await Future<void>.delayed(Duration.zero);
      }
      await controller.saveNow();
      sw.stop();
      final mergeMs = sw.elapsedMicroseconds / 1000 / iters;

      print(
        'poll N=$n: decode=${decodeMs.toStringAsFixed(1)} ms, '
        'merge (no change)=${mergeMs.toStringAsFixed(1)} ms, '
        'payload=${(jsonEncode(raw).length / 1024).round()} KB',
      );
      controller.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('saveEntry latency with N already stored', () async {
    for (final n in <int>[100, 250, 500, 1000]) {
      final blob = <String, dynamic>{
        for (var i = 0; i < n; i++) 'entry-$i': makeEntry(i).toJson(),
      };
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.scouting_entries_v1': jsonEncode(blob),
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = ScoutingController(
        storage: SharedPreferencesScoutingStorage(preferences: prefs),
      );
      await controller.bootstrap();
      final sw = Stopwatch()..start();
      await controller.saveEntry(makeEntry(n + 1));
      sw.stop();
      print('submit with N=$n stored: ${sw.elapsedMilliseconds} ms');
      controller.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
