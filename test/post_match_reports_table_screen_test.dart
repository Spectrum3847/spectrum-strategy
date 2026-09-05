import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/state/post_match_report_controller.dart';
import 'package:spectrumstrategy/src/ui/post_match_reports_table_screen.dart';

import 'support/fake_post_match_report_storage.dart';
import 'support/fake_post_match_report_sync_service.dart';

void main() {
  Future<PostMatchReportController> ready() async {
    final controller = PostMatchReportController(
      storage: FakePostMatchReportStorage(),
      syncService: FakePostMatchReportSyncService(),
    );
    await controller.bootstrap();
    return controller;
  }

  testWidgets('an empty event shows the empty state, not a bare table', (
    tester,
  ) async {
    final controller = await ready();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostMatchReportsTableScreen(
            controller: controller,
            eventKey: '2026miket',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No post match reports for this event yet.'),
      findsOneWidget,
    );
    expect(find.byType(DataTable), findsNothing);

    controller.dispose();
  });

  testWidgets('one row per match, ordered qualifiers first by number', (
    tester,
  ) async {
    final controller = await ready();
    await controller.save(
      eventKey: '2026miket',
      matchId: 'qm10',
      auto: 'ten',
      teleop: '',
      endgame: '',
      notes: '',
    );
    await controller.save(
      eventKey: '2026miket',
      matchId: 'qm2',
      auto: 'two',
      teleop: '',
      endgame: '',
      notes: '',
    );

    await controller.save(
      eventKey: '2026txhou',
      matchId: 'qm1',
      auto: 'other event',
      teleop: '',
      endgame: '',
      notes: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostMatchReportsTableScreen(
            controller: controller,
            eventKey: '2026miket',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('qm2'), findsOneWidget);
    expect(find.text('qm10'), findsOneWidget);
    expect(find.text('other event'), findsNothing);

    final qm2Y = tester.getTopLeft(find.text('qm2')).dy;
    final qm10Y = tester.getTopLeft(find.text('qm10')).dy;
    expect(qm2Y, lessThan(qm10Y));

    controller.dispose();
  });

  testWidgets('a blank section renders as a dash, not empty space', (
    tester,
  ) async {
    final controller = await ready();
    await controller.save(
      eventKey: '2026miket',
      matchId: 'qm1',
      auto: 'scored two',
      teleop: '',
      endgame: '',
      notes: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostMatchReportsTableScreen(
            controller: controller,
            eventKey: '2026miket',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('scored two'), findsOneWidget);
    expect(find.text('--'), findsNWidgets(3));

    controller.dispose();
  });

  testWidgets('tapping a row opens that match\'s report', (tester) async {
    final controller = await ready();
    await controller.save(
      eventKey: '2026miket',
      matchId: 'qm14',
      auto: 'scored two',
      teleop: '',
      endgame: '',
      notes: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostMatchReportsTableScreen(
            controller: controller,
            eventKey: '2026miket',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('qm14'));
    await tester.pumpAndSettle();

    expect(find.text('Match qm14 report'), findsOneWidget);

    controller.dispose();
  });
}
