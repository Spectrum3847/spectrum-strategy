import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';
import 'package:spectrumstrategy/src/widgets/entry_flag_badge.dart';

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

  ScoutEntry entry({
    required int team,
    required int match,
    required String station,
  }) {
    return ScoutEntry(
      matchId: 'session-uuid',
      teamNumber: team,

      fieldValues: <String, dynamic>{
        'matchNumber': match,
        'pTnumber': team,
        'robot': station,
      },
    );
  }

  Color? rowFillForTeam(WidgetTester tester, int team) {
    final boxes = find.ancestor(
      of: find.text('$team').first,
      matching: find.byType(DatabaseRowFill),
    );
    if (boxes.evaluate().isEmpty) return null;
    return tester.widget<DatabaseRowFill>(boxes.first).color;
  }

  testWidgets('a duplicate team tints its rows and names itself', (
    tester,
  ) async {
    await pumpWith(tester, [
      entry(team: 3847, match: 1, station: 'Red 1'),
      entry(team: 3847, match: 1, station: 'Red 2'),
    ]);

    expect(find.text('Check'), findsOneWidget);
    expect(find.byType(EntryFlagBadge), findsNWidgets(2));
    expect(find.text('Same team'), findsNWidgets(2));
    expect(rowFillForTeam(tester, 3847), StrategyPalette.flagSevere);
  });

  testWidgets('a duplicate station takes the second tint', (tester) async {
    await pumpWith(tester, [
      entry(team: 3847, match: 1, station: 'Red 1'),
      entry(team: 1477, match: 1, station: 'Red 1'),
    ]);

    expect(find.text('Same station'), findsNWidgets(2));
    expect(rowFillForTeam(tester, 3847), StrategyPalette.flagWarn);
    expect(rowFillForTeam(tester, 1477), StrategyPalette.flagWarn);
  });

  testWidgets('a clean table carries no flag column at all', (tester) async {
    await pumpWith(tester, [
      entry(team: 3847, match: 1, station: 'Red 1'),
      entry(team: 1477, match: 1, station: 'Red 2'),
    ]);

    expect(find.text('Check'), findsNothing);
    expect(find.byType(EntryFlagBadge), findsNothing);
    expect(rowFillForTeam(tester, 3847), isNull);
  });

  testWidgets('the flag survives a filter that hides its partner', (
    tester,
  ) async {
    await pumpWith(tester, [
      entry(team: 3847, match: 1, station: 'Red 1'),
      entry(team: 3847, match: 1, station: 'Red 2'),
      entry(team: 1477, match: 1, station: 'Red 3'),
    ]);

    await tester.enterText(find.byType(TextField).first, '1477');
    await tester.pumpAndSettle();

    expect(find.byType(EntryFlagBadge), findsNothing);

    await tester.enterText(find.byType(TextField).first, '3847');
    await tester.pumpAndSettle();

    expect(find.byType(EntryFlagBadge), findsNWidgets(2));
  });

  testWidgets('a match number off the schedule takes the third tint', (
    tester,
  ) async {
    await pumpWith(tester, [
      ScoutEntry(
        matchId: 'session-uuid',
        teamNumber: 3847,
        tbaMatchKey: '2026txhou_qm5',
        fieldValues: const <String, dynamic>{
          'matchNumber': 4,
          'pTnumber': 3847,
          'robot': 'Red 1',
        },
      ),
    ]);

    expect(find.text('Match number'), findsOneWidget);
    expect(rowFillForTeam(tester, 3847), StrategyPalette.flagNotice);
  });

  testWidgets('the Rows view tints the flagged card too', (tester) async {
    await pumpWith(tester, [
      entry(team: 3847, match: 1, station: 'Red 1'),
      entry(team: 3847, match: 1, station: 'Red 2'),
    ]);

    await tester.tap(find.text('Rows'));
    await tester.pumpAndSettle();

    expect(find.byType(EntryFlagBadge), findsNWidgets(2));
    final card = tester.widget<Card>(find.byType(Card).first);
    expect(card.color, StrategyPalette.flagSevere);
  });
}
