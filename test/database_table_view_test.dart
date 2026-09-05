import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import 'package:spectrumstrategy/src/scouting/services/scouting_storage.dart';

import 'support/fake_scout_config_service.dart';
import 'support/laggy_scouting_storage.dart';
import 'support/fake_scouting_storage.dart';

void main() {
  const seededAuthorUid = 'author-uid-1';

  Future<ScoutingController> pumpTable(
    WidgetTester tester, {
    required bool canEdit,
    bool? canAddManualEntry,
    String? currentUserUid,
    String alliance = 'Red',
    String robot = 'R1',
    String authorDisplayName = 'Alex',
    ScoutingStorage? storage,
    bool wideViewport = true,
  }) async {
    if (wideViewport) {
      tester.view.physicalSize = const Size(2800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    final scouting = ScoutingController(
      storage: storage ?? FakeScoutingStorage(),
    );
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await scouting.bootstrap();
    await config.bootstrap();

    await scouting.saveEntry(
      ScoutEntry(
        matchId: '2026txdri1_qm1',
        teamNumber: 3847,
        alliance: alliance,
        authorUid: seededAuthorUid,
        authorDisplayName: authorDisplayName,
        notes: 'Fast cycles',

        fieldValues: {
          'scouter': 'Alex',
          'matchNumber': 1,
          'robot': robot,
          'pTnumber': 3847,
          'starting': 'No Show',
          'autoFuelScored': 4,
          'auLow': 'N/A',
          'teleopFuelScored': 0,
          'scoringEff': 0,

          'tRdefense': false,
          'tRpasser': true,
          'ePclimb': 'N/A',
          'eLow': 'N/A',
          'eMiddle': 'N/A',
          'eHigh': 'N/A',
          'ryCard': true,
          'dieCard': true,
          'comments': '',
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatabaseTab(
            scoutingController: scouting,
            configController: config,
            eventController: EventController(),
            canEditAnyEntry: canEdit,
            canAddManualEntry: canAddManualEntry ?? canEdit,
            currentUserUid: currentUserUid,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return scouting;
  }

  testWidgets('the row order control is offered in the Table view too', (
    tester,
  ) async {
    await pumpTable(tester, canEdit: false);

    expect(
      find.textContaining('Match 1 first', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.textContaining('Match 1 first', findRichText: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Newest first').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Newest first', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets(
    'scouted field columns appear in exactly the form order the issue asks '
    'for, left to right',
    (tester) async {
      await pumpTable(tester, canEdit: false);

      double dxOf(Finder finder) => tester.getTopLeft(finder).dx;

      final scouterName = dxOf(find.text('Scouter Name'));
      final matchNumber = dxOf(find.text('Match Number'));
      final robotStation = dxOf(find.text('Robot Driver Station'));
      final teamNumber = dxOf(find.text('Team Number'));
      final startingPosition = dxOf(find.text('Robot Starting Position'));
      final autoFuel = dxOf(find.text('Fuel Scored').first);
      final levelOneClimb = dxOf(find.text('Level 1 Climb'));
      final teleopFuel = dxOf(find.text('Fuel Scored').last);
      final scoringAccuracy = dxOf(find.text('Scoring Accuracy (%)'));
      final defense = dxOf(find.text('Defense'));
      final passerPusher = dxOf(find.text('Passer/Pusher'));
      final climbPosition = dxOf(find.text('Climb Position'));
      final lowClimb = dxOf(find.text('Low Climb (L1)'));
      final middleClimb = dxOf(find.text('Middle Climb (L2)'));
      final highClimb = dxOf(find.text('High Climb (L3)'));
      final yellowRedCard = dxOf(find.text('Yellow/Red Card'));
      final disconnectDie = dxOf(find.text('Disconnect/Die'));
      final comments = dxOf(find.text('Comments'));
      final author = dxOf(find.text('Author'));
      final notes = dxOf(find.text('Notes'));

      expect(scouterName, lessThan(matchNumber));
      expect(matchNumber, lessThan(robotStation));
      expect(robotStation, lessThan(teamNumber));
      expect(teamNumber, lessThan(startingPosition));
      expect(startingPosition, lessThan(autoFuel));
      expect(autoFuel, lessThan(levelOneClimb));
      expect(levelOneClimb, lessThan(teleopFuel));
      expect(teleopFuel, lessThan(scoringAccuracy));
      expect(scoringAccuracy, lessThan(defense));
      expect(defense, lessThan(passerPusher));
      expect(passerPusher, lessThan(climbPosition));
      expect(climbPosition, lessThan(lowClimb));
      expect(lowClimb, lessThan(middleClimb));
      expect(middleClimb, lessThan(highClimb));
      expect(highClimb, lessThan(yellowRedCard));
      expect(yellowRedCard, lessThan(disconnectDie));
      expect(disconnectDie, lessThan(comments));

      expect(comments, lessThan(author));
      expect(author, lessThan(notes));
    },
  );

  testWidgets(
    'tapping the Team Number cell edits it and keeps entry.teamNumber in sync',
    (tester) async {
      final scouting = await pumpTable(tester, canEdit: true);

      await tester.tap(find.text('3847'));
      await tester.pumpAndSettle();

      final field = find.widgetWithText(TextField, '3847');
      expect(field, findsOneWidget);

      await tester.enterText(field, '254');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = scouting.entries.single;

      expect(saved.fieldValues['pTnumber'], 254);
      expect(saved.teamNumber, 254);
    },
  );

  testWidgets(
    'entering a non-numeric Team Number cell value does not save (#1382)',
    (tester) async {
      final scouting = await pumpTable(tester, canEdit: true);

      await tester.tap(find.text('3847'));
      await tester.pumpAndSettle();

      final field = find.widgetWithText(TextField, '3847');
      await tester.enterText(field, 'abc');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Enter a whole number.'), findsOneWidget);
      final entry = scouting.entries.single;
      expect(entry.teamNumber, 3847);
      expect(entry.fieldValues['pTnumber'], 3847);
    },
  );

  testWidgets('zero and negative Team Number cell values do not save (#1382)', (
    tester,
  ) async {
    final scouting = await pumpTable(tester, canEdit: true);

    for (final invalid in ['0', '-1']) {
      await tester.tap(find.text('3847'));
      await tester.pumpAndSettle();

      final field = find.widgetWithText(TextField, '3847');
      await tester.enterText(field, invalid);
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Enter a whole number.'), findsOneWidget);
      final entry = scouting.entries.single;
      expect(entry.teamNumber, 3847);
      expect(entry.fieldValues['pTnumber'], 3847);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('table cells are not tappable when canEditAnyEntry is false', (
    tester,
  ) async {
    await pumpTable(tester, canEdit: false);

    await tester.tap(find.text('3847'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  group('role-gated editability (#1382)', () {
    testWidgets('a scouter can edit a cell on their own entry even without '
        'canEditAnyEntry', (tester) async {
      final scouting = await pumpTable(
        tester,
        canEdit: false,
        currentUserUid: seededAuthorUid,
      );

      await tester.tap(find.text('3847'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '3847'), '254');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(scouting.entries.single.teamNumber, 254);
    });

    testWidgets('a scouter cannot edit a cell on someone else\'s entry', (
      tester,
    ) async {
      await pumpTable(
        tester,
        canEdit: false,
        currentUserUid: 'someone-else-uid',
      );

      await tester.tap(find.text('3847'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('cell edit round-trip preserves value types (#1382)', () {
    testWidgets('a counter (numeric) field saves as a number, not a string', (
      tester,
    ) async {
      final scouting = await pumpTable(tester, canEdit: true);

      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '+1'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final value = scouting.entries.single.fieldValues['autoFuelScored'];
      expect(value, isA<num>());
      expect(value, 5);
    });

    testWidgets('a boolean field saves as a bool, not a string', (
      tester,
    ) async {
      final scouting = await pumpTable(
        tester,
        canEdit: true,
        wideViewport: false,
      );

      final defenseCell = find.text('false');
      await tester.dragUntilVisible(
        defenseCell,
        find.byType(TableView),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(defenseCell);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final value = scouting.entries.single.fieldValues['tRdefense'];
      expect(value, isA<bool>());
      expect(value, isTrue);
    });
  });

  testWidgets('a select cell stores the choice key, not its label (#1382)', (
    tester,
  ) async {
    final scouting = await pumpTable(tester, canEdit: true);

    await tester.tap(find.text('Red 1'));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blue 2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(scouting.entries.single.fieldValues['robot'], 'B2');
  });

  testWidgets(
    'a legacy/invalid select value falls back to a valid dropdown selection',
    (tester) async {
      final scouting = await pumpTable(tester, canEdit: true, robot: 'ZZ');

      await tester.tap(find.text('ZZ'));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(scouting.entries.single.fieldValues['robot'], 'R1');
    },
  );

  testWidgets('tapping the Author cell opens an editable text field', (
    tester,
  ) async {
    final scouting = await pumpTable(
      tester,
      canEdit: true,
      wideViewport: false,
      authorDisplayName: 'Casey',
    );

    final authorCell = find.text('Casey');
    await tester.dragUntilVisible(
      authorCell,
      find.byType(TableView),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(authorCell);
    await tester.pumpAndSettle();

    expect(find.text('Scouted by'), findsOneWidget);
    final field = find.widgetWithText(TextField, 'Casey');
    await tester.enterText(field, 'Jordan');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(scouting.entries.single.authorDisplayName, 'Jordan');
  });

  testWidgets('tapping the Notes cell opens an editable text field', (
    tester,
  ) async {
    final scouting = await pumpTable(
      tester,
      canEdit: true,
      wideViewport: false,
    );

    final notesCell = find.text('Fast cycles');
    await tester.dragUntilVisible(
      notesCell,
      find.byType(TableView),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(notesCell);
    await tester.pumpAndSettle();

    final field = find.widgetWithText(TextField, 'Fast cycles');
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Slow cycles');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(scouting.entries.single.notes, 'Slow cycles');
  });

  testWidgets('tapping the Match Number cell edits and persists it', (
    tester,
  ) async {
    final scouting = await pumpTable(tester, canEdit: true);

    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    final field = find.widgetWithText(TextField, '1');
    await tester.enterText(field, '2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(scouting.entries.single.fieldValues['matchNumber'], 2);
  });

  group('save is guarded while in flight', () {
    testWidgets('a second tap on Save does not write twice', (tester) async {
      final storage = LaggyScoutingStorage();
      final scouting = await pumpTable(tester, canEdit: true, storage: storage);
      final savesBefore = storage.savedEntries.length;

      await tester.tap(find.text('3847'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '3847'), '254');

      storage.firstSaveGate = Completer<void>();
      await tester.tap(find.text('Save'));
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pump();

      storage.firstSaveGate!.complete();
      await tester.pumpAndSettle();

      expect(storage.savedEntries.length - savesBefore, 1);
      expect(scouting.entries.single.teamNumber, 254);
    });

    testWidgets('Save is disabled while the write is pending', (tester) async {
      final storage = LaggyScoutingStorage();
      await pumpTable(tester, canEdit: true, storage: storage);

      await tester.tap(find.text('3847'));
      await tester.pumpAndSettle();

      storage.firstSaveGate = Completer<void>();
      await tester.tap(find.text('Save'));
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(button.onPressed, isNull);

      storage.firstSaveGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('dismissing the dialog mid-save does not throw', (
      tester,
    ) async {
      final storage = LaggyScoutingStorage();
      await pumpTable(tester, canEdit: true, storage: storage);

      await tester.tap(find.text('3847'));
      await tester.pumpAndSettle();

      storage.firstSaveGate = Completer<void>();
      await tester.tap(find.text('Save'));
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      storage.firstSaveGate!.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the Database tab offers a scan action', (tester) async {
    await pumpTable(tester, canEdit: true);

    expect(find.widgetWithText(OutlinedButton, 'Scan'), findsOneWidget);
  });

  group('add entry', () {
    testWidgets('is offered when canEditAnyEntry is true', (tester) async {
      await pumpTable(tester, canEdit: true);

      expect(find.widgetWithText(OutlinedButton, 'Add entry'), findsOneWidget);
    });

    testWidgets('is hidden when canEditAnyEntry is false', (tester) async {
      await pumpTable(tester, canEdit: false);

      expect(find.widgetWithText(OutlinedButton, 'Add entry'), findsNothing);
    });

    testWidgets('is offered for a scouter, who cannot edit other rows', (
      tester,
    ) async {
      await pumpTable(tester, canEdit: false, canAddManualEntry: true);

      expect(find.widgetWithText(OutlinedButton, 'Add entry'), findsOneWidget);
    });

    testWidgets('stays hidden for a viewer', (tester) async {
      await pumpTable(tester, canEdit: false, canAddManualEntry: false);

      expect(find.widgetWithText(OutlinedButton, 'Add entry'), findsNothing);
    });

    testWidgets(
      'saves a new entry marked as added manually, with the team number and '
      'station filled into the config\'s own fields',
      (tester) async {
        final scouting = await pumpTable(tester, canEdit: true);
        final before = scouting.entries.length;

        await tester.tap(find.widgetWithText(OutlinedButton, 'Add entry'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('addEntryTeamField')),
          '254',
        );
        await tester.enterText(
          find.byKey(const Key('addEntryMatchField')),
          '5',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await tester.pumpAndSettle();

        expect(scouting.entries.length, before + 1);
        final added = scouting.entries.firstWhere((e) => e.teamNumber == 254);
        expect(added.addedManually, isTrue);
        expect(added.fieldValues['matchNumber'], 5);
        expect(added.alliance, 'Red');

        expect(added.fieldValues['pTnumber'], 254);
        expect(added.fieldValues['robot'], 'R1');
      },
    );

    testWidgets('rejects a non-numeric team number', (tester) async {
      final scouting = await pumpTable(tester, canEdit: true);
      final before = scouting.entries.length;

      await tester.tap(find.widgetWithText(OutlinedButton, 'Add entry'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('addEntryTeamField')), 'abc');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();

      expect(find.text('Enter a whole team number.'), findsOneWidget);
      expect(scouting.entries.length, before);
    });

    testWidgets('a manually added row is marked in the table view', (
      tester,
    ) async {
      final scouting = await pumpTable(tester, canEdit: true);
      await scouting.saveEntry(
        ScoutEntry(matchId: '', teamNumber: 41, addedManually: true),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
    });
  });
}
