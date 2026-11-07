import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/widgets/keyboard_shortcuts.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Ctrl+S runs the save callback', (tester) async {
    var saves = 0;
    await _pump(
      tester,
      SaveShortcut(
        onSave: () => saves++,
        child: const TextField(autofocus: true),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    expect(saves, 1);
  });

  testWidgets('Cmd+S runs it too, for macOS', (tester) async {
    var saves = 0;
    await _pump(
      tester,
      SaveShortcut(
        onSave: () => saves++,
        child: const TextField(autofocus: true),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();

    expect(saves, 1);
  });

  testWidgets('a plain S does not save, so typing is safe', (tester) async {
    var saves = 0;
    await _pump(
      tester,
      SaveShortcut(
        onSave: () => saves++,
        child: const TextField(autofocus: true),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();

    expect(saves, 0);
  });

  testWidgets('a null onSave leaves the child alone', (tester) async {
    await _pump(tester, const SaveShortcut(onSave: null, child: Text('form')));

    expect(find.byType(CallbackShortcuts), findsNothing);
    expect(find.text('form'), findsOneWidget);
  });

  testWidgets('left and right arrows step through a row', (tester) async {
    final List<String> steps = <String>[];
    await _pump(
      tester,
      HorizontalStepShortcuts(
        onPrevious: () => steps.add('previous'),
        onNext: () => steps.add('next'),
        child: TextButton(
          autofocus: true,
          onPressed: () {},
          child: const Text('Auton'),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(steps, <String>['next', 'previous']);
  });

  testWidgets('Escape closes a dialog', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const AlertDialog(content: Text('a dialog')),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('a dialog'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('a dialog'), findsNothing);
  });

  testWidgets('Escape closes a modal bottom sheet', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (_) => const SizedBox(height: 120, child: Text('a sheet')),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('a sheet'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('a sheet'), findsNothing);
  });
}
