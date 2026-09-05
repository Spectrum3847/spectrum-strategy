import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_shift_schedule.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_shift_grid.dart';

List<ScoutShiftRosterEntry> _roster(int count) => [
  for (var i = 0; i < count; i++)
    ScoutShiftRosterEntry(uid: 'u$i', name: 'Scouter $i'),
];

void main() {
  testWidgets('renders the names header and one row per match', (tester) async {
    final schedule = ScoutShiftSchedule.generate(
      eventKey: '2026miket',
      matchCount: 3,
      roster: _roster(2),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScoutShiftGrid(schedule: schedule, canEdit: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('names'), findsOneWidget);
    expect(find.text('Scouter 0'), findsOneWidget);
    expect(find.text('Scouter 1'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('a read-only grid does not open an edit dialog on tap', (
    tester,
  ) async {
    final schedule = ScoutShiftSchedule.generate(
      eventKey: '2026miket',
      matchCount: 3,
      roster: _roster(2),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScoutShiftGrid(schedule: schedule, canEdit: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scout-shift-cell-0-1')));
    await tester.pumpAndSettle();

    expect(find.text('Edit cell'), findsNothing);
  });

  testWidgets('editing a cell calls onCellEdit with the chosen color', (
    tester,
  ) async {
    final schedule = ScoutShiftSchedule.generate(
      eventKey: '2026miket',
      matchCount: 3,
      roster: _roster(2),
    );
    int? editedCol;
    int? editedMatch;
    String? editedText;
    ScheduleCellColor? editedColor;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScoutShiftGrid(
            schedule: schedule,
            canEdit: true,
            onCellEdit: (col, match, text, color) {
              editedCol = col;
              editedMatch = match;
              editedText = text;
              editedColor = color;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scout-shift-cell-0-1')));
    await tester.pumpAndSettle();
    expect(find.text('Edit cell'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'note');
    await tester.tap(find.text('red'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(editedCol, 0);
    expect(editedMatch, 1);
    expect(editedText, 'note');
    expect(editedColor, ScheduleCellColor.red);
  });

  testWidgets(
    'saving a cell edit dialog with nothing changed does not call onCellEdit',
    (tester) async {
      final schedule = ScoutShiftSchedule.generate(
        eventKey: '2026miket',
        matchCount: 3,
        roster: _roster(2),
      );
      var editCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoutShiftGrid(
              schedule: schedule,
              canEdit: true,
              onCellEdit: (col, match, text, color) => editCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('scout-shift-cell-0-1')));
      await tester.pumpAndSettle();
      expect(find.text('Edit cell'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(editCalled, isFalse);
    },
  );

  testWidgets('renaming a column calls onRenameColumn', (tester) async {
    final schedule = ScoutShiftSchedule.generate(
      eventKey: '2026miket',
      matchCount: 3,
      roster: _roster(2),
    );
    int? renamedCol;
    String? renamedName;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScoutShiftGrid(
            schedule: schedule,
            canEdit: true,
            onRenameColumn: (col, name) {
              renamedCol = col;
              renamedName = name;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scouter 0'));
    await tester.pumpAndSettle();
    expect(find.text('Rename scouter'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Alex');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(renamedCol, 0);
    expect(renamedName, 'Alex');
  });
}
