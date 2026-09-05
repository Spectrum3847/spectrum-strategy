import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/state/trex_trait_report_controller.dart';
import 'package:spectrumstrategy/src/ui/trex_traits_screen.dart';

import 'support/fake_trex_trait_report_storage.dart';

Future<void> _pump(
  WidgetTester tester,
  TrexTraitReportController controller,
) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: TrexTraitsScreen(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the Autonomous tab first, with its lookout instructions', (
    tester,
  ) async {
    final controller = TrexTraitReportController(
      storage: FakeTrexTraitReportStorage(),
    );
    await controller.bootstrap();
    await _pump(tester, controller);

    expect(find.text('Autonomous'), findsWidgets);
    expect(find.textContaining('Failures + fixes'), findsOneWidget);
  });

  testWidgets('switching tabs swaps the instructions box', (tester) async {
    final controller = TrexTraitReportController(
      storage: FakeTrexTraitReportStorage(),
    );
    await controller.bootstrap();
    await _pump(tester, controller);

    await tester.tap(find.text('Defense'));
    await tester.pumpAndSettle();

    expect(find.text('Defense T-Rex lookout'), findsOneWidget);
  });

  testWidgets('submitting the form adds a report to the database', (
    tester,
  ) async {
    final storage = FakeTrexTraitReportStorage();
    final controller = TrexTraitReportController(storage: storage);
    await controller.bootstrap();
    await _pump(tester, controller);

    await tester.enterText(
      find.widgetWithText(TextField, 'Team number'),
      '3847',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Match number'),
      '12',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Event name'),
      '2026miket',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Report'),
      'Fast, clean auton to the depot bump.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(controller.reportsForTeam(3847), hasLength(1));
    expect(find.text('Team 3847'), findsOneWidget);
    expect(find.textContaining('submitted for team 3847'), findsOneWidget);
  });

  testWidgets('submitting with no team number shows a validation message', (
    tester,
  ) async {
    final controller = TrexTraitReportController(
      storage: FakeTrexTraitReportStorage(),
    );
    await controller.bootstrap();
    await _pump(tester, controller);

    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a team number.'), findsOneWidget);
    expect(controller.reports, isEmpty);
  });

  testWidgets('the search bar narrows the database to a matching team', (
    tester,
  ) async {
    final storage = FakeTrexTraitReportStorage();
    final controller = TrexTraitReportController(storage: storage);
    await controller.bootstrap();
    await _pump(tester, controller);

    await tester.enterText(
      find.widgetWithText(TextField, 'Team number'),
      '3847',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Match number'), '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Search team number'),
      '254',
    );
    await tester.pumpAndSettle();

    expect(find.text('Team 3847'), findsNothing);
    expect(find.textContaining('No team matches'), findsOneWidget);
  });
}
