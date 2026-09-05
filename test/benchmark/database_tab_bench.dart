// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/entry_flags.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../support/fake_scout_config_service.dart';
import '../support/fake_scouting_storage.dart';

ScoutEntry makeEntry(int i) {
  const stations = <String>['R1', 'R2', 'R3', 'B1', 'B2', 'B3'];
  return ScoutEntry(
    id: 'entry-$i',
    matchId: 'qm${(i ~/ 6) + 1}',
    teamNumber: 1000 + (i % 40),
    alliance: i.isEven ? 'Red' : 'Blue',
    notes: 'Solid cycles, defended late. Entry $i.',
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
      'matchNumber': (i ~/ 6) + 1,
      'robot': stations[i % 6],
      for (var f = 0; f < 30; f++) 'field$f': f.isEven ? 'v-$i-$f' : i + f,
    },
  );
}

void main() {
  for (final n in <int>[60, 180, 360, 600]) {
    testWidgets('database table view N=$n', (tester) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final entries = <ScoutEntry>[for (var i = 0; i < n; i++) makeEntry(i)];
      final scouting = ScoutingController(storage: FakeScoutingStorage());
      final config = ScoutConfigController(service: FakeScoutConfigService());
      await scouting.bootstrap();
      await config.bootstrap();
      for (final e in entries) {
        await scouting.saveEntry(e);
      }

      var sw = Stopwatch()..start();
      const detectIters = 20;
      for (var i = 0; i < detectIters; i++) {
        EntryFlags.detect(
          entries,
          scheduledMatchNumbers: <int>[for (var m = 1; m <= 80; m++) m],
        );
      }
      sw.stop();
      final detectMs = sw.elapsedMicroseconds / 1000 / detectIters;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DatabaseTab(
              scoutingController: scouting,
              configController: config,
              eventController: EventController(),
              canEditAnyEntry: false,
              canAddManualEntry: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rows').first);
      await tester.pumpAndSettle();
      var swRows = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        scouting.notifyListeners();
        await tester.pump();
      }
      swRows.stop();
      final rowsViewMs = swRows.elapsedMicroseconds / 1000 / 5;
      await tester.tap(find.text('Table').first);
      await tester.pumpAndSettle();

      final tableView = tester.widget<TableView>(find.byType(TableView));
      final rows = tableView.delegate.rowCount ?? -1;
      final cols = tableView.delegate.columnCount ?? -1;
      final builtCells = find.byType(TableViewCell).evaluate().length;

      sw = Stopwatch()..start();
      const notifyIters = 5;
      for (var i = 0; i < notifyIters; i++) {
        scouting.notifyListeners();
        await tester.pump();
      }
      sw.stop();
      final notifyMs = sw.elapsedMicroseconds / 1000 / notifyIters;

      print(
        'DB tab N=$n: EntryFlags.detect=${detectMs.toStringAsFixed(1)} ms, '
        'rebuild=${notifyMs.toStringAsFixed(1)} ms, '
        'rows-view rebuild=${rowsViewMs.toStringAsFixed(1)} ms, '
        'rows=$rows cols=$cols logicalCells=${rows * cols} '
        'builtCells=$builtCells',
      );
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}
