import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/event_picker_dialog.dart';
import 'package:spectrumstrategy/src/ui/glass_chrome.dart';
import 'package:spectrumstrategy/src/widgets/glass_panel.dart';

Widget _host({required bool glass, required WidgetBuilder builder}) =>
    MaterialApp(
      home: GlassChrome(
        enabled: glass,
        child: Scaffold(body: Builder(builder: builder)),
      ),
    );

void main() {
  Future<void> openDialog(WidgetTester tester, {required bool glass}) async {
    await tester.pumpWidget(
      _host(
        glass: glass,
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => EventPickerDialog(
              eventController: EventController(),
              initialYear: 2026,
              glass: glass,
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('is a plain AlertDialog when glass chrome is off', (
    tester,
  ) async {
    await openDialog(tester, glass: false);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(GlassPanel), findsNothing);
    expect(find.text('Select Event'), findsOneWidget);
  });

  testWidgets('draws on GlassPanel when glass chrome is on', (tester) async {
    await openDialog(tester, glass: true);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(GlassPanel), findsOneWidget);
    expect(find.text('Select Event'), findsOneWidget);
  });

  testWidgets('sizes to its own content on both paths, not the full screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final card = find.byWidgetPredicate(
      (w) => w is Material && w.type == MaterialType.card,
    );

    await openDialog(tester, glass: false);
    final flatHeight = tester.getSize(card).height;
    expect(flatHeight, lessThan(700));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await openDialog(tester, glass: true);
    final glassHeight = tester.getSize(find.byType(GlassPanel)).height;
    expect(glassHeight, lessThan(700));
  });
}
