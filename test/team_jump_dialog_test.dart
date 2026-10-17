import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/ui/team_jump_dialog.dart';

Future<List<int>> _open(WidgetTester tester, Set<int> knownTeams) async {
  final opened = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showTeamJump(
            context,
            knownTeams: knownTeams,
            onOpenTeam: opened.add,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return opened;
}

Future<void> _submit(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.go);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Enter on a known team opens it and closes the field', (
    tester,
  ) async {
    final opened = await _open(tester, {254, 3847});

    await _submit(tester, '3847');

    expect(opened, [3847]);
    expect(find.text('Go to team'), findsNothing);
  });

  testWidgets('the Go button does the same as Enter', (tester) async {
    final opened = await _open(tester, {254});

    await tester.enterText(find.byType(TextField), '254');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(opened, [254]);
  });

  testWidgets('a team that is not at the event gets an inline message', (
    tester,
  ) async {
    final opened = await _open(tester, {254});

    await _submit(tester, '999');

    expect(find.text('Team 999 is not at this event.'), findsOneWidget);
    expect(find.text('Go to team'), findsOneWidget);
    expect(opened, isEmpty);

    await tester.enterText(find.byType(TextField), '25');
    await tester.pump();
    expect(find.textContaining('is not at this event'), findsNothing);
  });

  testWidgets('an empty field asks for a number', (tester) async {
    final opened = await _open(tester, {254});

    await _submit(tester, '');

    expect(find.text('Enter a team number, like 3847.'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('any number opens when no teams are loaded to check against', (
    tester,
  ) async {
    final opened = await _open(tester, <int>{});

    await _submit(tester, '1678');

    expect(opened, [1678]);
  });

  testWidgets('only digits can be typed', (tester) async {
    await _open(tester, {254});

    await tester.enterText(find.byType(TextField), '2a5-4');

    expect(find.text('254'), findsOneWidget);
  });

  group('TeamJumpShortcut', () {
    Future<List<BuildContext>> pumpShortcut(
      WidgetTester tester, {
      bool? enabled = true,
    }) async {
      final jumps = <BuildContext>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TeamJumpShortcut(
              enabled: enabled,
              onJump: jumps.add,
              child: const TextField(),
            ),
          ),
        ),
      );
      return jumps;
    }

    testWidgets('Slash calls onJump', (tester) async {
      final jumps = await pumpShortcut(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);

      expect(jumps, hasLength(1));
    });

    testWidgets('Slash typed into a text field is left alone', (tester) async {
      final jumps = await pumpShortcut(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);

      expect(jumps, isEmpty);
    });

    testWidgets('Ctrl+Slash is not the shortcut', (tester) async {
      final jumps = await pumpShortcut(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);

      expect(jumps, isEmpty);
    });

    testWidgets('a disabled shortcut ignores Slash', (tester) async {
      final jumps = await pumpShortcut(tester, enabled: false);

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);

      expect(jumps, isEmpty);
    });

    testWidgets('by default only a desktop answers', (tester) async {
      final jumps = await pumpShortcut(tester, enabled: null);

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);

      expect(jumps, isEmpty);
    });
  });
}
