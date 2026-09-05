// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/models/strategy_point.dart';
import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/models/strategy_stroke.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/prescout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/cycle_log_controller.dart';
import 'package:spectrumstrategy/src/state/event_sections_controller.dart';
import 'package:spectrumstrategy/src/state/event_stats_controller.dart';
import 'package:spectrumstrategy/src/state/pick_list_controller.dart';
import 'package:spectrumstrategy/src/state/post_match_report_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/state/theme_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

const int kEntries = 480;

const int kBoards = 60;
const int kStrokesPerBoard = 20;

ScoutEntry makeEntry(int i) => ScoutEntry(
  id: 'entry-$i',
  matchId: 'qm${(i ~/ 6) + 1}',
  teamNumber: 1000 + (i % 40),
  notes: 'Solid cycles, defended late in the match.',
  authorUid: 'uid-${i % 12}',
  authorDisplayName: 'Scout ${i % 12}',
  updatedAt: DateTime.utc(2026, 3, 1).add(Duration(minutes: i)),
  byPhase: <StrategyPhase, ScoutPhaseData>{
    for (final p in StrategyPhase.values)
      p: ScoutPhaseData(
        score: i % 30,
        counters: <String, int>{
          for (var c = 0; c < 8; c++) 'counter$c': (i + c) % 12,
        },
      ),
  },
  fieldValues: <String, dynamic>{
    for (var f = 0; f < 32; f++) 'field$f': f.isEven ? 'v-$i-$f' : i + f,
  },
);

StrategySession makeBoard(int i) {
  final s = StrategySession.create(id: 'board-$i');
  for (var k = 0; k < kStrokesPerBoard; k++) {
    s.strokesByPhase[StrategyPhase.values[k % 3]]!.add(
      StrategyStroke(
        phase: StrategyPhase.values[k % 3],
        points: <StrategyPoint>[
          for (var p = 0; p < 60; p++) StrategyPoint(p / 60, (p * 2 % 60) / 60),
        ],
      ),
    );
  }
  return s;
}

Map<String, Object> seed() {
  return <String, Object>{
    for (var i = 0; i < kEntries; i++)
      'flutter.scouting_entry_v2_entry-$i': jsonEncode(makeEntry(i).toJson()),

    for (var i = 0; i < kBoards; i++)
      'flutter.strategy_match_v3_board-$i': jsonEncode(makeBoard(i).toJson()),
    'flutter.strategy_active_match_id': 'board-0',
    'flutter.theme_mode': 'dark',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('per-controller bootstrap', () async {
    final results = <String, int>{};

    Future<void> time(String name, Future<void> Function() run) async {
      SharedPreferences.setMockInitialValues(seed());
      final sw = Stopwatch()..start();
      await run();
      sw.stop();
      results[name] = sw.elapsedMilliseconds;
    }

    await time('StrategyController', () => StrategyController().bootstrap());
    await time('ScoutingController', () => ScoutingController().bootstrap());
    await time('PickListController', () => PickListController().bootstrap());
    await time('CycleLogController', () => CycleLogController().bootstrap());
    await time(
      'PostMatchReportController',
      () => PostMatchReportController().bootstrap(),
    );
    await time('ThemeController', () => ThemeController().bootstrap());
    await time(
      'EventStatsController',
      () => EventStatsController(tbaClient: null).bootstrap(),
    );
    await time(
      'EventSectionsController',
      () => EventSectionsController(tbaClient: null).bootstrap(),
    );

    await time(
      'ScoutConfigController',
      () => ScoutConfigController().bootstrap(),
    );
    await time(
      'PitScoutConfigController',
      () => PitScoutConfigController().bootstrap(),
    );
    await time(
      'PrescoutConfigController',
      () => PrescoutConfigController().bootstrap(),
    );

    final ordered = results.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    print('--- bootstrap, $kEntries scout entries + $kBoards boards');
    for (final e in ordered) {
      print('${e.value.toString().padLeft(5)} ms  ${e.key}');
    }
    print('slowest sets the first frame: ${ordered.first.key}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
