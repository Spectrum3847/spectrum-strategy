import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:statbotics_client/statbotics_client.dart';
import 'package:spectrumstrategy/src/models/trex_trait.dart';
import 'package:spectrumstrategy/src/models/trex_trait_report.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/trex_trait_report_controller.dart';
import 'package:spectrumstrategy/src/ui/trex_traits_screen.dart';

import 'support/fake_trex_trait_report_storage.dart';
import 'support/fake_trex_trait_report_sync_service.dart';

Future<void> _pump(
  WidgetTester tester,
  TrexTraitReportController controller, {
  bool canEditAnyEntry = false,
  String eventKey = '',
  EventController? eventController,
}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TrexTraitsScreen(
          controller: controller,
          canEditAnyEntry: canEditAnyEntry,
          eventKey: eventKey,
          eventController: eventController,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TrexTraitReport _seedReport({
  required String id,
  required int teamNumber,
  String eventKey = '',
}) => TrexTraitReport(
  id: id,
  trait: 'autonomous',
  teamNumber: teamNumber,
  matchNumber: 1,
  eventKey: eventKey,
  report: 'A write-up.',
  updatedAt: DateTime.utc(2026, 8, 1),
);

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

  testWidgets('submitting with no event shows a validation message', (
    tester,
  ) async {
    final controller = TrexTraitReportController(
      storage: FakeTrexTraitReportStorage(),
    );
    await controller.bootstrap();
    await _pump(tester, controller);

    await tester.enterText(
      find.widgetWithText(TextField, 'Team number'),
      '3847',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Match number'), '1');
    await tester.enterText(
      find.widgetWithText(TextField, 'Report'),
      'A write-up.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Enter an event.'), findsOneWidget);
    expect(controller.reports, isEmpty);
  });

  testWidgets('submitting with no report text shows a validation message', (
    tester,
  ) async {
    final controller = TrexTraitReportController(
      storage: FakeTrexTraitReportStorage(),
    );
    await controller.bootstrap();
    await _pump(tester, controller);

    await tester.enterText(
      find.widgetWithText(TextField, 'Team number'),
      '3847',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Match number'), '1');
    await tester.enterText(
      find.widgetWithText(TextField, 'Event name'),
      '2026miket',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a report.'), findsOneWidget);
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
    await tester.enterText(
      find.widgetWithText(TextField, 'Event name'),
      '2026miket',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Report'),
      'A write-up.',
    );
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

  testWidgets('the report author can delete their own report', (tester) async {
    final storage = FakeTrexTraitReportStorage();
    final sync = FakeTrexTraitReportSyncService(currentUserUid: 'me');
    final controller = TrexTraitReportController(
      storage: storage,
      syncService: sync,
    );
    await controller.bootstrap();
    await _pump(tester, controller);

    await tester.enterText(
      find.widgetWithText(TextField, 'Team number'),
      '3847',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Match number'), '1');
    await tester.enterText(
      find.widgetWithText(TextField, 'Event name'),
      '2026miket',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Report'),
      'A write-up.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team 3847'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete report'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(controller.reports, isEmpty);
    expect(find.text('Team 3847'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    "a scout with no elevated role cannot delete someone else's report",
    (tester) async {
      final storage = FakeTrexTraitReportStorage();
      await storage.saveReport(
        TrexTraitReport(
          id: 'other',
          trait: TrexTrait.autonomous.key,
          teamNumber: 254,
          matchNumber: 3,
          authorUid: 'someone-else',
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      final sync = FakeTrexTraitReportSyncService(currentUserUid: 'me');
      final controller = TrexTraitReportController(
        storage: storage,
        syncService: sync,
      );
      await controller.bootstrap();
      await _pump(tester, controller, canEditAnyEntry: false);
      await tester.tap(find.text('Team 254'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Delete report'), findsNothing);
    },
  );

  testWidgets('a signed-in scout with no elevated role cannot delete an '
      'empty-author report', (tester) async {
    final storage = FakeTrexTraitReportStorage();
    await storage.saveReport(
      TrexTraitReport(
        id: 'no-author',
        trait: TrexTrait.autonomous.key,
        teamNumber: 118,
        matchNumber: 5,
        updatedAt: DateTime.utc(2026, 8, 1),
      ),
    );
    final sync = FakeTrexTraitReportSyncService(currentUserUid: 'me');
    final controller = TrexTraitReportController(
      storage: storage,
      syncService: sync,
    );
    await controller.bootstrap();
    await _pump(tester, controller, canEditAnyEntry: false);
    await tester.tap(find.text('Team 118'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Delete report'), findsNothing);
  });

  testWidgets(
    'the database filters to the active event, keeping keyless reports',
    (tester) async {
      final storage = FakeTrexTraitReportStorage();
      await storage.saveReport(
        _seedReport(id: 'r1', teamNumber: 3847, eventKey: '2026miket'),
      );
      await storage.saveReport(
        _seedReport(id: 'r2', teamNumber: 118, eventKey: '2026txhou'),
      );
      await storage.saveReport(_seedReport(id: 'r3', teamNumber: 254));
      final controller = TrexTraitReportController(storage: storage);
      await controller.bootstrap();

      await _pump(tester, controller, eventKey: '2026miket');

      expect(find.text('Team 3847'), findsOneWidget);
      expect(find.text('Team 254'), findsOneWidget);
      expect(find.text('Team 118'), findsNothing);
    },
  );

  testWidgets('the "All events" toggle shows every event\'s reports', (
    tester,
  ) async {
    final storage = FakeTrexTraitReportStorage();
    await storage.saveReport(
      _seedReport(id: 'r1', teamNumber: 3847, eventKey: '2026miket'),
    );
    await storage.saveReport(
      _seedReport(id: 'r2', teamNumber: 118, eventKey: '2026txhou'),
    );
    final controller = TrexTraitReportController(storage: storage);
    await controller.bootstrap();

    await _pump(tester, controller, eventKey: '2026miket');
    expect(find.text('Team 118'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'All events'));
    await tester.pumpAndSettle();

    expect(find.text('Team 118'), findsOneWidget);
  });

  testWidgets(
    'the event field is a picker over available events, defaulting to the '
    'active event (#1775)',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = FakeTrexTraitReportStorage();
      final controller = TrexTraitReportController(storage: storage);
      await controller.bootstrap();
      final eventController = EventController(
        client: StatboticsClient(
          httpClient: MockClient((request) async {
            if (request.url.path.contains('/event/2026miket')) {
              return http.Response(
                '{"key":"2026miket","name":"Milwaukee","year":2026}',
                200,
              );
            }
            if (request.url.path.contains('/events')) {
              return http.Response(
                '[{"key":"2026miket","name":"Milwaukee","year":2026},'
                '{"key":"2026txhou","name":"Houston","year":2026}]',
                200,
              );
            }
            return http.Response('[]', 200);
          }),
        ),
      );
      await eventController.setEventKey('2026miket');

      await _pump(tester, controller, eventController: eventController);

      expect(find.widgetWithText(TextField, 'Event name'), findsNothing);
      expect(find.text('Milwaukee'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Houston').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Team number'),
        '3847',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Match number'),
        '12',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Report'),
        'A write-up.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(controller.reportsForTeam(3847).single.eventName, 'Houston');
    },
  );
}
