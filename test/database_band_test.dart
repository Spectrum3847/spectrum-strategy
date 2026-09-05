import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';

void main() {
  Future<void> pumpWith(WidgetTester tester, List<ScoutEntry> entries) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await scouting.bootstrap();
    await config.bootstrap();
    for (final entry in entries) {
      await scouting.saveEntry(entry);
    }

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
  }

  ScoutEntry entry({required int team, required int match, String? station}) {
    return ScoutEntry(
      matchId: 'session-uuid',
      teamNumber: team,

      fieldValues: <String, dynamic>{
        'matchNumber': match,
        'pTnumber': team,
        'robot': ?station,
      },
    );
  }

  Color? rowFillForTeam(WidgetTester tester, int team) {
    final boxes = find.ancestor(
      of: find.text('$team'),
      matching: find.byType(DatabaseRowFill),
    );
    if (boxes.evaluate().isEmpty) return null;
    return tester.widget<DatabaseRowFill>(boxes.first).color;
  }

  List<ScoutEntry> fullMatch(int match, int firstTeam) {
    const stations = <String>['R1', 'R2', 'R3', 'B1', 'B2', 'B3'];
    return [
      for (var i = 0; i < stations.length; i++)
        entry(team: firstTeam + i, match: match, station: stations[i]),
    ];
  }

  testWidgets('two matches read as two blocks', (tester) async {
    await pumpWith(tester, [...fullMatch(1, 100), ...fullMatch(2, 200)]);

    final block1 = [for (var t = 100; t < 106; t++) rowFillForTeam(tester, t)];
    final block2 = [for (var t = 200; t < 206; t++) rowFillForTeam(tester, t)];

    expect(block1.toSet(), hasLength(1));
    expect(block2.toSet(), hasLength(1));
    expect(block1.first, isNot(block2.first));
    expect(block2.first, StrategyPalette.surfaceStrong);
  });

  testWidgets('a match with five entries is still one block', (tester) async {
    await pumpWith(tester, [
      ...fullMatch(1, 100).sublist(0, 5),
      ...fullMatch(2, 200),
    ]);

    final block1 = [for (var t = 100; t < 105; t++) rowFillForTeam(tester, t)];
    final block2 = [for (var t = 200; t < 206; t++) rowFillForTeam(tester, t)];
    expect(block1.toSet(), hasLength(1));
    expect(block2.toSet(), hasLength(1));
    expect(block1.first, isNot(block2.first));
  });

  testWidgets('three matches alternate rather than run away', (tester) async {
    await pumpWith(tester, [
      ...fullMatch(1, 100),
      ...fullMatch(2, 200),
      ...fullMatch(3, 300),
    ]);

    expect(rowFillForTeam(tester, 100), rowFillForTeam(tester, 300));
    expect(rowFillForTeam(tester, 100), isNot(rowFillForTeam(tester, 200)));
  });

  testWidgets('the banding follows a re-sort', (tester) async {
    await pumpWith(tester, [...fullMatch(1, 100), ...fullMatch(2, 200)]);

    await tester.tap(find.textContaining('Match 1 first', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Newest first').last);
    await tester.pumpAndSettle();

    final block1 = [for (var t = 100; t < 106; t++) rowFillForTeam(tester, t)];
    final block2 = [for (var t = 200; t < 206; t++) rowFillForTeam(tester, t)];
    expect(block1.toSet(), hasLength(1));
    expect(block2.toSet(), hasLength(1));
    expect(block1.first, isNot(block2.first));
  });

  testWidgets('a flagged row keeps its flag tint over the band', (
    tester,
  ) async {
    await pumpWith(tester, [
      ...fullMatch(1, 100),

      entry(team: 200, match: 2, station: 'R1'),
      entry(team: 200, match: 2, station: 'R2'),
    ]);

    expect(rowFillForTeam(tester, 200), StrategyPalette.flagSevere);
  });
}
