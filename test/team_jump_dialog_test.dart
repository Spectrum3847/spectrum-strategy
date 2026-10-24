import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/ui/team_jump_dialog.dart';

Future<List<int>> _open(
  WidgetTester tester,
  Set<int> knownTeams, {
  Set<String> matchKeys = const <String>{},
  List<String>? openedMatches,
}) async {
  final opened = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showTeamJump(
            context,
            knownTeams: knownTeams,
            onOpenTeam: opened.add,
            eventKey: '2026test',
            knownMatchKeys: matchKeys,
            onOpenMatch: openedMatches?.add,
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
    expect(find.text('Go to team or match'), findsNothing);
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
    expect(find.text('Go to team or match'), findsOneWidget);
    expect(opened, isEmpty);

    await tester.enterText(find.byType(TextField), '25');
    await tester.pump();
    expect(find.textContaining('is not at this event'), findsNothing);
  });

  testWidgets('an empty field asks for a number', (tester) async {
    final opened = await _open(tester, {254});

    await _submit(tester, '');

    expect(
      find.text('Enter a team number like 3847 or a match like q45.'),
      findsOneWidget,
    );
    expect(opened, isEmpty);
  });

  testWidgets('any number opens when no teams are loaded to check against', (
    tester,
  ) async {
    final opened = await _open(tester, <int>{});

    await _submit(tester, '1678');

    expect(opened, [1678]);
  });

  testWidgets('punctuation cannot be typed', (tester) async {
    await _open(tester, {254});

    await tester.enterText(find.byType(TextField), 'q4-5');

    expect(find.text('q45'), findsOneWidget);
  });

  group('MatchQuery.parse', () {
    String? suffix(String q) => MatchQuery.parse(q)?.suffix;

    test('reads the qualification spellings', () {
      for (final q in ['q45', 'Q45', 'qm45', 'm45', 'match 45', 'match45']) {
        expect(suffix(q), 'qm45', reason: q);
      }
      expect(MatchQuery.parse('q45')?.label, 'Qualification 45');
    });

    test('reads playoff sets and games', () {
      expect(suffix('sf3'), 'sf3m1');
      expect(suffix('sf3m2'), 'sf3m2');
      expect(suffix('f1'), 'f1m1');
      expect(suffix('f1m2'), 'f1m2');
      expect(MatchQuery.parse('sf3')?.label, 'Semifinal 3');
      expect(MatchQuery.parse('f1m2')?.label, 'Final 1 match 2');
    });

    test('a team number or other text is not a match', () {
      for (final q in ['', '45', '3847', 'q', 'q0', 'sf0', 'cheesy', 'qm4x']) {
        expect(MatchQuery.parse(q), isNull, reason: q);
      }
    });
  });

  testWidgets('a match in the schedule shows as a row and opens by key', (
    tester,
  ) async {
    final matches = <String>[];
    await _open(
      tester,
      {254},
      matchKeys: {'2026test_qm45'},
      openedMatches: matches,
    );

    await tester.enterText(find.byType(TextField), 'q45');
    await tester.pump();
    expect(find.text('Qualification 45'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('match-result')));
    await tester.pumpAndSettle();

    expect(matches, ['2026test_qm45']);
    expect(find.text('Go to team or match'), findsNothing);
  });

  testWidgets('Enter on a match query opens the match', (tester) async {
    final matches = <String>[];
    final teams = await _open(
      tester,
      {45},
      matchKeys: {'2026test_qm45'},
      openedMatches: matches,
    );

    await _submit(tester, 'qm45');

    expect(matches, ['2026test_qm45']);
    expect(teams, isEmpty);
  });

  testWidgets('a match that is not scheduled gets an inline message', (
    tester,
  ) async {
    final matches = <String>[];
    await _open(tester, {254}, openedMatches: matches);

    await _submit(tester, 'q45');

    expect(
      find.text('Qualification 45 is not in the schedule.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('match-result')), findsNothing);
    expect(matches, isEmpty);
  });

  testWidgets('a bare number stays a team even when a match has it', (
    tester,
  ) async {
    final matches = <String>[];
    final teams = await _open(
      tester,
      {45},
      matchKeys: {'2026test_qm45'},
      openedMatches: matches,
    );

    await _submit(tester, '45');

    expect(teams, [45]);
    expect(matches, isEmpty);
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
