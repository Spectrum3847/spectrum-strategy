import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';

void main() {
  ScoutEntry entry(int team, int match) => ScoutEntry(
    matchId: 'qm$match',
    teamNumber: team,
    fieldValues: <String, dynamic>{'pTnumber': team},
  );

  Future<ScoutingController> pumpTable(
    WidgetTester tester,
    int rowCount,
  ) async {
    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await scouting.bootstrap();
    await config.bootstrap();
    for (var i = 0; i < rowCount; i++) {
      await scouting.saveEntry(entry(100 + i, i + 1));
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
    return scouting;
  }

  testWidgets('an off-screen row does not exist until scrolled into view', (
    tester,
  ) async {
    await pumpTable(tester, 40);

    expect(find.text('100'), findsWidgets);

    expect(find.text('139'), findsNothing);

    await tester.drag(find.byType(TableView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(find.text('139'), findsWidgets);
  });

  testWidgets('the header stays pinned while the body scrolls under it', (
    tester,
  ) async {
    await pumpTable(tester, 40);

    expect(find.text('Team Number'), findsOneWidget);

    await tester.drag(find.byType(TableView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(find.text('Team Number'), findsOneWidget);
    expect(find.text('139'), findsWidgets);
  });

  const bodyCellPadding = 8.0;

  testWidgets(
    'the header stays column-aligned with the body across a horizontal scroll',
    (tester) async {
      await pumpTable(tester, 1);

      double dxOf(Finder finder) => tester.getTopLeft(finder).dx;
      final headerDx = dxOf(find.text('Team Number'));
      final cellDx = dxOf(find.text('100'));
      expect(cellDx, headerDx + bodyCellPadding);

      await tester.drag(find.byType(TableView), const Offset(-250, 0));
      await tester.pumpAndSettle();

      expect(
        dxOf(find.text('100')),
        dxOf(find.text('Team Number')) + bodyCellPadding,
      );
    },
  );

  Finder resizeHandles() => find.byWidgetPredicate(
    (widget) =>
        widget is MouseRegion &&
        widget.cursor == SystemMouseCursors.resizeColumn,
  );

  testWidgets('dragging a header divider resizes the column', (tester) async {
    await pumpTable(tester, 1);

    double dxOf(Finder finder) => tester.getTopLeft(finder).dx;
    final before = dxOf(find.text('Author'));

    await tester.drag(resizeHandles().first, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(dxOf(find.text('Author')), greaterThan(before));

    expect(
      dxOf(find.text('100')),
      dxOf(find.text('Team Number')) + bodyCellPadding,
    );
  });
}
