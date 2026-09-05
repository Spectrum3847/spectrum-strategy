import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/state/trex_assignments_controller.dart';
import 'package:spectrumstrategy/src/state/trex_trait_report_controller.dart';
import 'package:spectrumstrategy/src/ui/trex_screen.dart';

import 'support/fake_trex_assignments_sync_service.dart';
import 'support/fake_trex_trait_report_storage.dart';

void main() {
  testWidgets('shows both tabs when both controllers are wired', (
    tester,
  ) async {
    final assignments = TRexAssignmentsController(
      syncService: FakeTRexAssignmentsSyncService(),
    );
    await assignments.bootstrap();
    addTearDown(assignments.dispose);

    final traits = TrexTraitReportController(
      storage: FakeTrexTraitReportStorage(),
    );
    await traits.bootstrap();
    addTearDown(traits.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TrexScreen(
          trexController: assignments,
          trexTraitReportController: traits,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Assignments'), findsOneWidget);
    expect(find.text('Traits'), findsOneWidget);
  });

  testWidgets('shows only the traits tab when the assignments controller '
      'is null', (tester) async {
    final traits = TrexTraitReportController(
      storage: FakeTrexTraitReportStorage(),
    );
    await traits.bootstrap();
    addTearDown(traits.dispose);

    await tester.pumpWidget(
      MaterialApp(home: TrexScreen(trexTraitReportController: traits)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Assignments'), findsNothing);
    expect(find.text('Traits'), findsOneWidget);
  });

  testWidgets('shows a placeholder when no controller is wired', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TrexScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No T-Rex data source is wired in.'), findsOneWidget);
  });
}
