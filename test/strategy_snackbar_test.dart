import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/ui/strategy_tab.dart';

import 'support/fake_match_directory.dart';

void main() {
  testWidgets('Clear all snackbar hides on its own', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final strategy = StrategyController(directory: FakeMatchDirectory());
    await strategy.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StrategyTab(
            controller: strategy,
            eventController: EventController(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Clear all'));
    await tester.tap(find.text('Clear all'));

    await tester.pumpAndSettle();
    expect(find.text('Board cleared'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Board cleared'), findsNothing);
  });
}
