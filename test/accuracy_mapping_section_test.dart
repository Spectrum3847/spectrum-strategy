import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/ui/accuracy_mapping_section.dart';

import 'support/fake_accuracy_mapping_service.dart';

Future<void> _pump(WidgetTester tester, FakeAccuracyMappingService service) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AccuracyMappingSection(service: service),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the loaded mapping through the injected service', (
    tester,
  ) async {
    final service = FakeAccuracyMappingService(
      initial: const {
        'year': 2026,
        'perFieldTolerancePct': 40,
        'mappings': [
          {'field': 'coralL1'},
        ],
      },
    );
    await _pump(tester, service);
    await tester.pumpAndSettle();

    expect(service.loadCalls, 1);
    expect(find.text('Active mapping'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('surfaces a load failure as an inline error card', (
    tester,
  ) async {
    final service = FakeAccuracyMappingService()
      ..loadError = StateError('permission-denied');
    await _pump(tester, service);
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to load mapping'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsOneWidget);
  });

  testWidgets('viewing and closing the JSON dialog does not throw', (
    tester,
  ) async {
    final service = FakeAccuracyMappingService(
      initial: const {'year': 2026, 'mappings': <Map<String, dynamic>>[]},
    );
    await _pump(tester, service);
    await tester.pumpAndSettle();

    await tester.tap(find.text('View JSON'));
    await tester.pumpAndSettle();
    expect(find.text('Current accuracy mapping'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('saving edited JSON goes through the injected service', (
    tester,
  ) async {
    final service = FakeAccuracyMappingService(
      initial: const {'year': 2026, 'mappings': <Map<String, dynamic>>[]},
    );
    await _pump(tester, service);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit mapping JSON'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '{"year": 2027, "mappings": []}',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(service.saveCalls, 1);
    expect(service.lastSaved?['year'], 2027);
    expect(find.textContaining('Mapping saved'), findsOneWidget);
  });
}
