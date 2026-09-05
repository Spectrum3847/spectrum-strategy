import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/widgets/film_split_view.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: FilmSplitView(
          primary: ColoredBox(
            color: Color(0xFF112233),
            child: SizedBox.expand(child: Text('form')),
          ),
          secondary: ColoredBox(
            color: Color(0xFF332211),
            child: SizedBox.expand(child: Text('film')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('splits side by side on a wide surface', (tester) async {
    await _pump(tester, const Size(1200, 800));

    final form = tester.getRect(find.text('form'));
    final film = tester.getRect(find.text('film'));
    expect(form.center.dx, lessThan(film.center.dx));
    expect(form.center.dy, closeTo(film.center.dy, 1));
  });

  testWidgets('stacks on a narrow surface', (tester) async {
    await _pump(tester, const Size(500, 900));

    final form = tester.getRect(find.text('form'));
    final film = tester.getRect(find.text('film'));
    expect(form.center.dy, lessThan(film.center.dy));
  });

  testWidgets('dragging the handle right gives the form more room', (
    tester,
  ) async {
    await _pump(tester, const Size(1200, 800));
    final before = tester.getRect(find.text('film')).width;

    await tester.drag(
      find.byKey(const ValueKey('film-split-handle')),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('film')).width, lessThan(before - 150));
  });

  testWidgets('neither pane can be dragged away entirely', (tester) async {
    await _pump(tester, const Size(1200, 800));

    await tester.drag(
      find.byKey(const ValueKey('film-split-handle')),
      const Offset(5000, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('film')).width, greaterThan(200));
    expect(find.text('film'), findsOneWidget);
  });
}
