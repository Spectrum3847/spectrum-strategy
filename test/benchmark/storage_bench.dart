// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/models/strategy_point.dart';
import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/models/strategy_stroke.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_storage.dart';
import 'package:spectrumstrategy/src/services/match_directory.dart';

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

double ms(Stopwatch s, int iters) => s.elapsedMicroseconds / 1000 / iters;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('measurements', () async {
    final line = StringBuffer();
    void report(String s) {
      line.writeln(s);
      print(s);
    }

    final one = makeEntry(1);
    final oneJson = jsonEncode(one.toJson());
    report('ScoutEntry encoded size: ${oneJson.length} bytes');

    var sw = Stopwatch()..start();
    for (var i = 0; i < 2000; i++) {
      ScoutEntry.fromJson(one.toJson());
    }
    sw.stop();
    report('ScoutEntry.fromJson(toJson()) : ${ms(sw, 2000)} ms/entry');

    for (final n in <int>[100, 250, 500, 1000, 2000]) {
      final blob = <String, dynamic>{
        for (var i = 0; i < n; i++) 'entry-$i': makeEntry(i).toJson(),
      };
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.scouting_entries_v1': jsonEncode(blob),
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = SharedPreferencesScoutingStorage(preferences: prefs);

      sw = Stopwatch()..start();
      const iters = 20;
      for (var i = 0; i < iters; i++) {
        await storage.saveEntry(makeEntry(i));
      }
      sw.stop();
      final perSave = ms(sw, iters);

      final sw2 = Stopwatch()..start();
      final loaded = await storage.loadAll();
      sw2.stop();

      report(
        'N=$n blob=${(jsonEncode(blob).length / 1024).round()}KB  '
        'saveEntry=${perSave.toStringAsFixed(2)} ms  '
        'loadAll=${ms(sw2, 1).toStringAsFixed(2)} ms (${loaded.length})',
      );
    }

    StrategySession buildSession(int strokes) {
      final session = StrategySession.create();
      for (var s = 0; s < strokes; s++) {
        session.strokesByPhase[StrategyPhase.values[s % 3]]!.add(
          StrategyStroke(
            phase: StrategyPhase.values[s % 3],
            points: <StrategyPoint>[
              for (var p = 0; p < 60; p++)
                StrategyPoint(p / 60, (p * 2 % 60) / 60),
            ],
          ),
        );
      }
      return session;
    }

    for (final strokes in <int>[20, 100, 400]) {
      final session = buildSession(strokes);
      final size = jsonEncode(session.toJson()).length;
      sw = Stopwatch()..start();
      const iters = 100;
      for (var i = 0; i < iters; i++) {
        StrategySession.fromJson(session.toJson());
      }
      sw.stop();
      report(
        'session strokes=$strokes (${(size / 1024).round()}KB) '
        'fromJson(toJson())=${ms(sw, iters).toStringAsFixed(2)} ms',
      );
    }

    for (final (n, st) in <(int, int)>[
      (20, 20),
      (60, 20),
      (120, 20),
      (20, 60),
      (60, 60),
      (120, 60),
    ]) {
      final session = buildSession(st);
      final boardValues = <String, Object>{
        for (var i = 0; i < n; i++)
          'flutter.strategy_match_v3_m$i': jsonEncode(session.toJson()),
      };
      final totalBytes = boardValues.values
          .map((v) => (v as String).length)
          .fold<int>(0, (a, b) => a + b);
      SharedPreferences.setMockInitialValues(boardValues);
      final prefs = await SharedPreferences.getInstance();
      final dir = SharedPreferencesMatchDirectory(preferences: prefs);

      final swList = Stopwatch()..start();
      final summaries = await dir.listMatches();
      swList.stop();

      final existing = StrategySession.fromJson(
        (jsonDecode(
          boardValues['flutter.strategy_match_v3_m0']! as String,
        ) as Map).cast<String, dynamic>(),
      );
      sw = Stopwatch()..start();
      const iters = 10;
      for (var i = 0; i < iters; i++) {
        await dir.saveMatch(existing);
      }
      sw.stop();

      final swList2 = Stopwatch()..start();
      await dir.listMatches();
      swList2.stop();

      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.strategy_matches_v2': jsonEncode(<String, dynamic>{
          for (var i = 0; i < n; i++) 'm$i': session.toJson(),
        }),
      });
      final migratedDir = SharedPreferencesMatchDirectory(
        preferences: await SharedPreferences.getInstance(),
      );
      final swMigrated = Stopwatch()..start();
      final migrated = await migratedDir.listMatches();
      swMigrated.stop();

      report(
        'listMatches(${summaries.length})='
        '${ms(swList, 1).toStringAsFixed(1)} ms  '
        'listMatches(post-migration ${migrated.length})='
        '${ms(swMigrated, 1).toStringAsFixed(1)} ms  '
        'listMatches(warm)=${ms(swList2, 1).toStringAsFixed(2)} ms  '
        'matches=$n strokes/match=$st total=${(totalBytes / 1024).round()}KB '
        'saveMatch=${ms(sw, iters).toStringAsFixed(2)} ms',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
