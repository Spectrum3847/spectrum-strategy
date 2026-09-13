import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/ui/docs_viewer_screen.dart';

void main() {
  testWidgets('docs tab lists grouped docs (developer sees all)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DocsTab(roles: {UserRole.developer})),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Start here'), findsOneWidget);
    expect(find.text('Setup & configuration'), findsOneWidget);
    expect(find.text('Reference'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Scouting Accuracy: Mapping Guide'), findsOneWidget);

    expect(find.text('Role manuals'), findsOneWidget);
    expect(find.text('Scouter Manual'), findsOneWidget);
    expect(find.text('Strategy Manual'), findsOneWidget);
    expect(find.text('Admin Manual'), findsOneWidget);
    expect(find.text('Developer Manual'), findsOneWidget);
  });

  testWidgets('docs are role-filtered: a scouter sees only member docs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DocsTab(roles: {UserRole.scouter})),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Using Spectrum Strategy'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Scouter Manual'), findsOneWidget);

    expect(find.text('Strategy Manual'), findsNothing);
    expect(find.text('Admin Manual'), findsNothing);
    expect(find.text('Developer Manual'), findsNothing);
    expect(find.text('Scouting Accuracy: Mapping Guide'), findsNothing);
    expect(find.text('Scouting Accuracy: Slack Setup'), findsNothing);
    expect(find.text('CI Workflows'), findsNothing);
    expect(find.text('Reference'), findsNothing);
  });

  testWidgets('tapping a doc opens the renderer with bundled content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DocsTab(roles: {UserRole.developer})),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    expect(find.text('Start here'), findsNothing);
    expect(find.widgetWithText(AppBar, 'Overview'), findsOneWidget);

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
