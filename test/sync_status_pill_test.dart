import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/widgets/sync_status_pill.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the given label and icon', (tester) async {
    await _pump(
      tester,
      const SyncStatusPill(label: 'Synced', icon: Icons.cloud_done_rounded),
    );

    expect(find.text('Synced'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);
  });

  testWidgets('a normal pill uses onSurface ink, not error', (tester) async {
    await _pump(
      tester,
      const SyncStatusPill(label: 'Synced', icon: Icons.cloud_done_rounded),
    );

    final context = tester.element(find.byType(SyncStatusPill));
    final scheme = Theme.of(context).colorScheme;

    final icon = tester.widget<Icon>(find.byIcon(Icons.cloud_done_rounded));
    expect(icon.color, scheme.onSurface);
  });

  testWidgets('isFailure tints the icon and border with the error color', (
    tester,
  ) async {
    await _pump(
      tester,
      const SyncStatusPill(
        label: '3 edits not saved',
        icon: Icons.cloud_off_rounded,
        isFailure: true,
      ),
    );

    final context = tester.element(find.byType(SyncStatusPill));
    final scheme = Theme.of(context).colorScheme;

    expect(find.text('3 edits not saved'), findsOneWidget);

    final icon = tester.widget<Icon>(find.byIcon(Icons.cloud_off_rounded));
    expect(icon.color, scheme.error);

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.border!.top.color, scheme.error);
  });
}
