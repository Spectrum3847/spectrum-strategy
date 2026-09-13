import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/trex_trait_report.dart';
import 'package:spectrumstrategy/src/state/trex_trait_report_controller.dart';
import 'package:spectrumstrategy/src/ui/trex_database_screen.dart';

import 'support/fake_trex_trait_report_storage.dart';

Future<TrexTraitReportController> _controllerWith(
  List<TrexTraitReport> reports,
) async {
  final controller = TrexTraitReportController(
    storage: FakeTrexTraitReportStorage(),
  );
  await controller.bootstrap();
  for (final report in reports) {
    final saved = await controller.submitReport(report);
    expect(saved, isTrue);
  }
  return controller;
}

Future<void> _pump(
  WidgetTester tester,
  TrexTraitReportController controller,
) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: TrexDatabaseScreen(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('groups every report by team with no filter applied', (
    tester,
  ) async {
    final controller = await _controllerWith([
      TrexTraitReport(
        trait: 'autonomous',
        teamNumber: 100,
        matchNumber: 1,
        eventName: 'East Event',
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      TrexTraitReport(
        trait: 'autonomous',
        teamNumber: 200,
        matchNumber: 2,
        eventName: 'West Event',
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      TrexTraitReport(
        trait: 'defense',
        teamNumber: 300,
        matchNumber: 3,
        eventName: 'East Event',
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    await _pump(tester, controller);

    expect(find.text('Team 100'), findsOneWidget);
    expect(find.text('Team 200'), findsOneWidget);
    expect(find.text('Team 300'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the team search narrows the list to a matching team', (
    tester,
  ) async {
    final controller = await _controllerWith([
      TrexTraitReport(
        trait: 'autonomous',
        teamNumber: 100,
        matchNumber: 1,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      TrexTraitReport(
        trait: 'autonomous',
        teamNumber: 300,
        matchNumber: 1,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    await _pump(tester, controller);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search team number'),
      '300',
    );
    await tester.pumpAndSettle();

    expect(find.text('Team 100'), findsNothing);
    expect(find.text('Team 300'), findsOneWidget);
  });

  testWidgets('the funnel filter narrows the list to a picked event', (
    tester,
  ) async {
    final controller = await _controllerWith([
      TrexTraitReport(
        trait: 'autonomous',
        teamNumber: 100,
        matchNumber: 1,
        eventName: 'East Event',
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      TrexTraitReport(
        trait: 'autonomous',
        teamNumber: 200,
        matchNumber: 2,
        eventName: 'West Event',
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    await _pump(tester, controller);

    await tester.tap(find.byTooltip('Filter by event or trait'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('West Event'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Team 100'), findsNothing);
    expect(find.text('Team 200'), findsOneWidget);
  });

  testWidgets('the funnel filter narrows the list to a picked trait', (
    tester,
  ) async {
    final controller = await _controllerWith([
      TrexTraitReport(
        trait: 'autonomous',
        teamNumber: 100,
        matchNumber: 1,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      TrexTraitReport(
        trait: 'defense',
        teamNumber: 300,
        matchNumber: 1,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    await _pump(tester, controller);

    await tester.tap(find.byTooltip('Filter by event or trait'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Defense'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Team 100'), findsNothing);
    expect(find.text('Team 300'), findsOneWidget);
  });
}
