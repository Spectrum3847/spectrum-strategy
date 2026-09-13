import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/state/trex_assignments_controller.dart';
import 'package:spectrumstrategy/src/state/trex_team_list_controller.dart';
import 'package:spectrumstrategy/src/ui/trex_assignments_view.dart';

import 'support/fake_trex_assignments_sync_service.dart';
import 'support/fake_trex_team_list_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') return null;
        return null;
      });

  Future<TRexAssignmentsController> readyController(
    FakeTRexAssignmentsSyncService sync,
  ) async {
    final controller = TRexAssignmentsController(syncService: sync);
    await controller.bootstrap();
    await controller.addColumn('Defense');
    await controller.addName(controller.assignments.columns.single.key, 'Alex');
    return controller;
  }

  testWidgets('a strategy lead sees editable fields for columns and names', (
    tester,
  ) async {
    final sync = FakeTRexAssignmentsSyncService();
    final controller = await readyController(sync);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TRexAssignmentsView(controller: controller, canEdit: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.text('Add trait'), findsOneWidget);

    expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
  });

  testWidgets(
    'a read-only role sees the same data with no editing affordances',
    (tester) async {
      final sync = FakeTRexAssignmentsSyncService();
      final controller = await readyController(sync);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TRexAssignmentsView(controller: controller, canEdit: false),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Defense'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Add trait'), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    },
  );

  testWidgets('an empty table shows an empty state instead of a blank grid', (
    tester,
  ) async {
    final sync = FakeTRexAssignmentsSyncService();
    final controller = TRexAssignmentsController(syncService: sync);
    await controller.bootstrap();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TRexAssignmentsView(controller: controller, canEdit: false),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No T-Rex traits have been added yet.'), findsOneWidget);
  });

  testWidgets(
    'move-right on a column and move-down on a name reorder the table',
    (tester) async {
      final sync = FakeTRexAssignmentsSyncService();
      final controller = TRexAssignmentsController(syncService: sync);
      await controller.bootstrap();
      await controller.addColumn('Defense');
      await controller.addColumn('Auton');
      final defenseKey = controller.assignments.columns.first.key;
      await controller.addName(defenseKey, 'Alex');
      await controller.addName(defenseKey, 'Sam');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TRexAssignmentsView(controller: controller, canEdit: true),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.chevron_right_rounded).first);
      await tester.pump();

      expect(controller.assignments.columns.map((c) => c.name), [
        'Auton',
        'Defense',
      ]);

      await tester.tap(find.byIcon(Icons.arrow_downward_rounded).first);
      await tester.pump();

      expect(controller.assignments.byKey(defenseKey)!.names, ['Sam', 'Alex']);
    },
  );

  testWidgets('copying as text puts the rendered table on the clipboard', (
    tester,
  ) async {
    final sync = FakeTRexAssignmentsSyncService();
    final controller = await readyController(sync);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TRexAssignmentsView(controller: controller, canEdit: false),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Copy as text'));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('T-Rex assignments copied as text'), findsOneWidget);
  });

  group('team list table', () {
    Future<TRexTeamListController> readyTeamListController(
      FakeTRexTeamListSyncService sync,
    ) async {
      final controller = TRexTeamListController(syncService: sync);
      await controller.bootstrap();
      await controller.addColumn('Defense');
      await controller.addTeam(controller.teamList.columns.single.key, '118');
      return controller;
    }

    testWidgets('a strategy lead can edit the title, columns, and teams', (
      tester,
    ) async {
      final sync = FakeTRexAssignmentsSyncService();
      final controller = await readyController(sync);
      addTearDown(controller.dispose);
      final teamSync = FakeTRexTeamListSyncService();
      final teamListController = await readyTeamListController(teamSync);
      addTearDown(teamListController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TRexAssignmentsView(
              controller: controller,
              teamListController: teamListController,
              canEdit: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Team assignments'), findsOneWidget);
      expect(find.text('118'), findsOneWidget);
      expect(find.text('Add column'), findsOneWidget);
      expect(find.text('Total teams: 1'), findsOneWidget);
    });

    testWidgets(
      'a read-only role sees the team list with no editing affordances',
      (tester) async {
        final sync = FakeTRexAssignmentsSyncService();
        final controller = await readyController(sync);
        addTearDown(controller.dispose);
        final teamSync = FakeTRexTeamListSyncService();
        final teamListController = await readyTeamListController(teamSync);
        addTearDown(teamListController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TRexAssignmentsView(
                controller: controller,
                teamListController: teamListController,
                canEdit: false,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('118'), findsOneWidget);
        expect(find.text('Add column'), findsNothing);
      },
    );

    testWidgets('an empty team list shows an empty state', (tester) async {
      final sync = FakeTRexAssignmentsSyncService();
      final controller = await readyController(sync);
      addTearDown(controller.dispose);
      final teamSync = FakeTRexTeamListSyncService();
      final teamListController = TRexTeamListController(syncService: teamSync);
      await teamListController.bootstrap();
      addTearDown(teamListController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TRexAssignmentsView(
              controller: controller,
              teamListController: teamListController,
              canEdit: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('No team assignments have been added yet.'),
        findsOneWidget,
      );
    });

    testWidgets('adding a team via the field pushes it to the controller', (
      tester,
    ) async {
      final sync = FakeTRexAssignmentsSyncService();
      final controller = await readyController(sync);
      addTearDown(controller.dispose);
      final teamSync = FakeTRexTeamListSyncService();
      final teamListController = await readyTeamListController(teamSync);
      addTearDown(teamListController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TRexAssignmentsView(
              controller: controller,
              teamListController: teamListController,
              canEdit: true,
            ),
          ),
        ),
      );
      await tester.pump();

      final addTeamField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == 'Add team',
      );
      await tester.enterText(addTeamField, '254');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(
        teamListController.teamList.columns.single.teams,
        containsAll(['118', '254']),
      );
    });

    testWidgets('copying as text includes both tables', (tester) async {
      final sync = FakeTRexAssignmentsSyncService();
      final controller = await readyController(sync);
      addTearDown(controller.dispose);
      final teamSync = FakeTRexTeamListSyncService();
      final teamListController = await readyTeamListController(teamSync);
      addTearDown(teamListController.dispose);

      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') return null;
              return null;
            }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TRexAssignmentsView(
              controller: controller,
              teamListController: teamListController,
              canEdit: false,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Copy as text'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(copied, contains('T-Rex assignments'));
      expect(copied, contains('Alex'));
      expect(copied, contains('Team assignments'));
      expect(copied, contains('118'));
    });
  });

  testWidgets('pasting a list adds every scouter to the trait column (#1410)', (
    tester,
  ) async {
    final sync = FakeTRexAssignmentsSyncService();
    final controller = await readyController(sync);
    addTearDown(controller.dispose);
    final columnKey = controller.assignments.columns.single.key;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TRexAssignmentsView(controller: controller, canEdit: true),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(ValueKey('trex-paste-names-$columnKey')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('paste-list-field')),
      'Grace Hopper\nAlan Turing, Katherine Johnson',
    );
    await tester.pumpAndSettle();
    expect(find.text('3 entries'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('paste-list-add')));
    await tester.pumpAndSettle();

    expect(controller.assignments.columns.single.names, <String>[
      'Alex',
      'Grace Hopper',
      'Alan Turing',
      'Katherine Johnson',
    ]);
  });

  testWidgets('a read-only role gets no paste affordance', (tester) async {
    final sync = FakeTRexAssignmentsSyncService();
    final controller = await readyController(sync);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TRexAssignmentsView(controller: controller, canEdit: false),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.content_paste_rounded), findsNothing);
  });
}
