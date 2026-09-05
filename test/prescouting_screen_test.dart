import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/prescout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/prescouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/prescout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/prescouting_controller.dart';
import 'package:spectrumstrategy/src/ui/prescouting_screen.dart';
import 'package:spectrumstrategy/src/widgets/film_video_pane.dart';

import 'support/fake_prescout_config_service.dart';
import 'support/fake_prescouting_storage.dart';
import 'support/fake_prescouting_sync_service.dart';

Future<PrescoutingController> _bootController({
  FakePrescoutingStorage? storage,
  PrescoutingSyncService? sync,
}) async {
  final controller = PrescoutingController(
    storage: storage ?? FakePrescoutingStorage(),
    syncService: sync,
  );
  await controller.bootstrap();
  return controller;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required PrescoutingController controller,
  bool filmEmbedSupported = false,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final configController = PrescoutConfigController(
    service: FakePrescoutConfigService(),
  );
  await configController.bootstrap();

  await tester.pumpWidget(
    MaterialApp(
      home: PrescoutingScreen(
        controller: controller,
        configController: configController,

        filmEmbedSupported: filmEmbedSupported,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDataTab(WidgetTester tester) async {
  await tester.tap(find.text('Data'));
  await tester.pumpAndSettle();
}

Future<void> _selectEvent(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('prescout-event-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Chezy Champs').last);
  await tester.pumpAndSettle();
}

Future<void> _selectTeam(WidgetTester tester, int team) async {
  await tester.tap(find.byKey(const ValueKey('prescout-team-dropdown')));
  await tester.pumpAndSettle();

  await tester.tap(find.textContaining('$team').last);
  await tester.pumpAndSettle();
}

Future<void> _tapSaveRecord(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.text('Save record'),
    find.byKey(const ValueKey('prescout-record-form-list')),
    const Offset(0, -300),
  );

  await tester.ensureVisible(find.text('Save record'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save record'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('instructions tab renders the guidance headings', (tester) async {
    await _pumpScreen(tester, controller: await _bootController());

    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Teleop'), findsOneWidget);
    expect(find.text('Endgame'), findsOneWidget);

    expect(
      find.textContaining('Depot trench, neutral zone 2x'),
      findsOneWidget,
    );

    expect(find.textContaining('five of its matches'), findsOneWidget);

    expect(find.textContaining('fully prescouted'), findsOneWidget);
  });

  testWidgets('data tab requires an event before a team can be picked', (
    tester,
  ) async {
    await _pumpScreen(tester, controller: await _bootController());
    await _openDataTab(tester);

    expect(find.textContaining('Select an event above'), findsOneWidget);
    expect(find.byKey(const ValueKey('prescout-team-dropdown')), findsNothing);
  });

  testWidgets(
    'the team dropdown marks an in-progress team incomplete with its starter',
    (tester) async {
      final storage = FakePrescoutingStorage();
      await storage.saveEntry(
        PrescoutEntry(
          teamNumber: 254,
          fieldValues: <String, dynamic>{
            'watchedEvent': 'Chezy Champs',
            'matchNumber': '12',
          },
          authorDisplayName: 'Ada',
        ),
      );
      final controller = await _bootController(storage: storage);
      await _pumpScreen(tester, controller: controller);
      await _openDataTab(tester);
      await _selectEvent(tester);

      await tester.tap(find.byKey(const ValueKey('prescout-team-dropdown')));
      await tester.pumpAndSettle();
      expect(find.text('254 (incomplete - Ada)'), findsOneWidget);

      await tester.tap(find.text('254 (incomplete - Ada)'));
      await tester.pumpAndSettle();

      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    },
  );

  testWidgets(
    'saving a new record through the form adds an entry for the selected team',
    (tester) async {
      final storage = FakePrescoutingStorage();
      final controller = await _bootController(storage: storage);
      await _pumpScreen(tester, controller: controller);
      await _openDataTab(tester);
      await _selectEvent(tester);
      await _selectTeam(tester, 254);

      await tester.tap(find.text('Add record'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('prescout-field-matchNumber')),
        '3',
      );
      await _tapSaveRecord(tester);

      expect(controller.entries, hasLength(1));
      expect(controller.entries.single.teamNumber, 254);
      expect(controller.entries.single.eventKey, 'chezyChamps');
      expect(
        controller.entries.single.fieldValues['watchedEvent'],
        'Chezy Champs',
      );
      expect(controller.entries.single.fieldValues['matchNumber'], '3');

      expect(find.text('3'), findsOneWidget);
    },
  );

  testWidgets('saving a new record stamps the signed-in scouter, so the team '
      'dropdown shows their name rather than "unknown scouter"', (
    tester,
  ) async {
    final storage = FakePrescoutingStorage();
    final sync = FakePrescoutingSyncService(
      currentUserUid: 'uid-me',
      currentUserDisplayName: 'Ada Widget',
    );
    final controller = await _bootController(storage: storage, sync: sync);
    await _pumpScreen(tester, controller: controller);
    await _openDataTab(tester);
    await _selectEvent(tester);
    await _selectTeam(tester, 254);

    await tester.tap(find.text('Add record'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prescout-field-matchNumber')),
      '3',
    );
    await _tapSaveRecord(tester);

    expect(controller.entries.single.authorUid, 'uid-me');
    expect(controller.entries.single.authorDisplayName, 'Ada Widget');

    expect(find.text('254 (incomplete - Ada Widget)'), findsOneWidget);
  });

  testWidgets('a fully prescouted team is marked done and blocks new records', (
    tester,
  ) async {
    final storage = FakePrescoutingStorage();
    for (var i = 0; i < 5; i++) {
      await storage.saveEntry(
        PrescoutEntry(
          teamNumber: 254,
          fieldValues: <String, dynamic>{'matchNumber': '$i'},
          authorDisplayName: 'Ada',
        ),
      );
    }
    final controller = await _bootController(storage: storage);
    await _pumpScreen(tester, controller: controller);
    await _openDataTab(tester);
    await _selectEvent(tester);
    await _selectTeam(tester, 254);

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    final addButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add record'),
    );
    expect(addButton.onPressed, isNull);
  });

  testWidgets(
    'an off-list team with records is reachable and disappears once deleted '
    '(#1447)',
    (tester) async {
      final storage = FakePrescoutingStorage();
      await storage.saveEntry(
        PrescoutEntry(
          id: 'off-list-entry',
          teamNumber: 3847,
          fieldValues: <String, dynamic>{
            'watchedEvent': 'Chezy Champs',
            'matchNumber': '1',
          },
          authorDisplayName: 'Ada',
        ),
      );
      final controller = await _bootController(storage: storage);
      await _pumpScreen(tester, controller: controller);
      await _openDataTab(tester);
      await _selectEvent(tester);

      await tester.tap(find.byKey(const ValueKey('prescout-team-dropdown')));
      await tester.pumpAndSettle();
      expect(find.text('3847 (incomplete - Ada)'), findsOneWidget);

      await tester.tap(find.text('3847 (incomplete - Ada)'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(controller.entries, isEmpty);

      await tester.tap(find.byKey(const ValueKey('prescout-team-dropdown')));
      await tester.pumpAndSettle();
      expect(find.text('3847'), findsNothing);
    },
  );

  testWidgets('tapping another scout\'s record opens read-only, not the form', (
    tester,
  ) async {
    final storage = FakePrescoutingStorage();
    await storage.saveEntry(
      PrescoutEntry(
        id: 'teammate-entry',
        teamNumber: 1678,
        fieldValues: <String, dynamic>{
          'watchedEvent': 'Chezy Champs',
          'matchNumber': '7',
          'autoFuelScored': 9,
        },
        authorUid: 'teammate-uid',
        authorDisplayName: 'Teammate',
      ),
    );
    final controller = await _bootController(storage: storage);
    await _pumpScreen(tester, controller: controller);
    await _openDataTab(tester);
    await _selectEvent(tester);
    await _selectTeam(tester, 1678);

    await tester.tap(find.text('Teammate').last);
    await tester.pumpAndSettle();

    expect(find.text('Scouted by'), findsOneWidget);
    expect(find.text('Event Name'), findsOneWidget);
    expect(find.text('Match Number'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);

    expect(find.text('Save record'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(controller.entries.single.id, 'teammate-entry');
    expect(controller.entries.single.authorUid, 'teammate-uid');
    expect(controller.entries.single.fieldValues['autoFuelScored'], 9);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'the fuel counters take +1/+5/+10 taps, matching the match form (#1409)',
    (tester) async {
      final storage = FakePrescoutingStorage();
      final controller = await _bootController(storage: storage);
      await _pumpScreen(tester, controller: controller);
      await _openDataTab(tester);
      await _selectEvent(tester);
      await _selectTeam(tester, 254);

      await tester.tap(find.text('Add record'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, '+10').first);
      await tester.pumpAndSettle();

      expect(find.text('10'), findsOneWidget);
    },
  );

  testWidgets('summary tab searches down to one team', (tester) async {
    final storage = FakePrescoutingStorage();
    await storage.saveEntry(
      PrescoutEntry(
        teamNumber: 254,
        fieldValues: <String, dynamic>{
          'autoFuelScored': 10,
          'teleopFuelScored': 20,
        },
      ),
    );
    final controller = await _bootController(storage: storage);
    await _pumpScreen(tester, controller: controller);
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();

    expect(find.text('254'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('prescout-summary-search')),
      '254',
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(DataTable), matching: find.text('254')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('prescout-summary-search')),
      '9999',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching team.'), findsOneWidget);
  });

  testWidgets('the record form fills the screen until a film link is pasted', (
    tester,
  ) async {
    await _pumpScreen(tester, controller: await _bootController());
    await _openDataTab(tester);
    await _selectEvent(tester);
    await _selectTeam(tester, 254);
    await tester.tap(find.text('Add record'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('film-split-handle')), findsNothing);
    expect(find.byType(FilmVideoPane), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('prescout-field-videoUrl')),
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('film-split-handle')), findsOneWidget);
    expect(find.byType(FilmVideoPane), findsOneWidget);

    expect(
      find.byKey(const ValueKey('prescout-record-form-list')),
      findsOneWidget,
    );
  });

  testWidgets('a platform without an in-app player offers to open the film '
      'in a browser', (tester) async {
    await _pumpScreen(tester, controller: await _bootController());
    await _openDataTab(tester);
    await _selectEvent(tester);
    await _selectTeam(tester, 254);
    await tester.tap(find.text('Add record'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('prescout-field-videoUrl')),
      'https://youtu.be/dQw4w9WgXcQ',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('film-open-external')), findsOneWidget);
    expect(find.textContaining('no in-app player'), findsOneWidget);
  });

  testWidgets('searching down to one team lists that team\'s records (#1392)', (
    tester,
  ) async {
    final storage = FakePrescoutingStorage();
    await storage.saveEntry(
      PrescoutEntry(
        teamNumber: 254,
        fieldValues: <String, dynamic>{
          'watchedEvent': 'Chezy Champs',
          'matchNumber': '3',
          'autoFuelScored': 10,
          'teleopFuelScored': 20,
          'comments': 'Jammed on the second cycle.',
        },
        authorDisplayName: 'Grace',
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await storage.saveEntry(
      PrescoutEntry(
        teamNumber: 254,
        fieldValues: <String, dynamic>{
          'watchedEvent': 'Chezy Champs',
          'matchNumber': '9',
          'comments': 'Clean auto, fast cycles.',
        },
        authorDisplayName: 'Ada',
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    );
    await storage.saveEntry(
      PrescoutEntry(
        teamNumber: 1678,
        fieldValues: <String, dynamic>{'comments': 'Another team entirely.'},
      ),
    );
    final controller = await _bootController(storage: storage);
    await _pumpScreen(tester, controller: controller);
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prescout-summary-team-detail')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('prescout-summary-search')),
      '254',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prescout-summary-team-detail')),
      findsOneWidget,
    );
    expect(find.text('Team 254: 2 records'), findsOneWidget);

    expect(find.text('Jammed on the second cycle.'), findsOneWidget);
    expect(find.text('Clean auto, fast cycles.'), findsOneWidget);
    expect(find.text('Another team entirely.'), findsNothing);
  });

  testWidgets('a searched team nobody has prescouted says so', (tester) async {
    await _pumpScreen(tester, controller: await _bootController());
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('prescout-summary-search')),
      '9496',
    );
    await tester.pumpAndSettle();

    expect(find.text('Nobody has prescouted this team yet.'), findsOneWidget);
  });
}
