import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/entry_delivery.dart';
import 'package:spectrumstrategy/src/scouting/widgets/delivery_tracker.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

Future<void> _pumpTracker(
  WidgetTester tester,
  EntryDelivery delivery, {
  String? reason,
}) {
  return _pump(
    tester,
    DeliveryTracker(delivery: delivery, rejectionReason: reason),
  );
}

void main() {
  group('DeliveryTracker', () {
    testWidgets('saved only stops after the first step', (tester) async {
      await _pumpTracker(tester, EntryDelivery.savedOnly);

      expect(find.text('Saved on this device'), findsOneWidget);
      expect(
        find.text('Sign in with a team account to send entries.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(
        find.byIcon(Icons.radio_button_unchecked_rounded),
        findsNWidgets(2),
      );
    });

    testWidgets('pending shows the send step as in progress', (tester) async {
      await _pumpTracker(tester, EntryDelivery.pending);

      expect(
        find.text('Goes out by itself once this device is online.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
    });

    testWidgets('sent by QR does not claim the database has it', (
      tester,
    ) async {
      await _pumpTracker(tester, EntryDelivery.sentByQr);

      expect(find.text('Sent by QR'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
      expect(
        find.text('Confirmed once this device syncs its own copy.'),
        findsOneWidget,
      );
    });

    testWidgets('sent waits on the database to show it back', (tester) async {
      await _pumpTracker(tester, EntryDelivery.sent);

      expect(find.text('The team database accepted it.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    });

    testWidgets('confirmed checks all three steps', (tester) async {
      await _pumpTracker(tester, EntryDelivery.confirmed);

      expect(find.text('Saved on this device'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('In the database'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
    });

    testWidgets('rejected shows the reason in the error color', (tester) async {
      await _pumpTracker(
        tester,
        EntryDelivery.rejected,
        reason: 'permission-denied: no access',
      );

      expect(find.text('Not accepted'), findsOneWidget);
      expect(
        find.text('The team database refused it: permission-denied: no access'),
        findsOneWidget,
      );
      expect(find.text('Sent'), findsNothing);

      final context = tester.element(find.byType(DeliveryTracker));
      final scheme = Theme.of(context).colorScheme;
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.error_outline_rounded),
      );
      expect(icon.color, scheme.error);
      final title = tester.widget<Text>(find.text('Not accepted'));
      expect(title.style?.color, scheme.error);
    });

    testWidgets('rejected without a reason still says so', (tester) async {
      await _pumpTracker(tester, EntryDelivery.rejected);

      expect(
        find.text('The team database refused it. It stays on this device.'),
        findsOneWidget,
      );
    });
  });

  group('SavedEntryConfirmation', () {
    testWidgets('shows the tracker and calls back on Next match', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        SavedEntryConfirmation(
          title: 'Team 3847 saved',
          delivery: EntryDelivery.sent,
          onNextMatch: () => taps++,
        ),
      );

      expect(find.text('Team 3847 saved'), findsOneWidget);
      expect(find.byType(DeliveryTracker), findsOneWidget);

      await tester.tap(find.text('Next match'));
      expect(taps, 1);
    });
  });

  group('DeliveryBanner', () {
    testWidgets('is empty when everything is confirmed', (tester) async {
      await _pump(tester, const DeliveryBanner(unconfirmed: 0, rejected: 0));

      expect(find.byType(Card), findsNothing);
    });

    testWidgets('counts one entry in the singular', (tester) async {
      await _pump(tester, const DeliveryBanner(unconfirmed: 1, rejected: 0));

      expect(find.text('1 entry is not in the database yet'), findsOneWidget);
      expect(find.textContaining('not accepted'), findsNothing);
    });

    testWidgets('counts several entries and the rejected ones', (tester) async {
      await _pump(tester, const DeliveryBanner(unconfirmed: 3, rejected: 2));

      expect(
        find.text('3 entries are not in the database yet'),
        findsOneWidget,
      );
      expect(find.text('2 not accepted by the database'), findsOneWidget);
    });
  });
}
