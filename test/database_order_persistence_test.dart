import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';

void main() {
  Future<void> pumpTab(WidgetTester tester) async {
    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await scouting.bootstrap();
    await config.bootstrap();
    await scouting.saveEntry(
      ScoutEntry(
        matchId: 'session-uuid',
        teamNumber: 3847,
        fieldValues: const <String, dynamic>{'matchNumber': 1},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatabaseTab(
            scoutingController: scouting,
            configController: config,
            eventController: EventController(),
            canEditAnyEntry: false,
            canAddManualEntry: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder orderControl(String label) =>
      find.textContaining(label, findRichText: true);

  testWidgets('a stored submitted order comes back', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'database_entry_order': 'submitted',
    });

    await pumpTab(tester);

    expect(orderControl('Submitted first'), findsOneWidget);
  });

  testWidgets('the two older stored values still come back', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'database_entry_order': 'newestFirst',
    });

    await pumpTab(tester);

    expect(orderControl('Newest first'), findsOneWidget);
  });

  testWidgets('a stored value no order has falls back to the default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'database_entry_order': 'byTeamNumberDescending',
    });

    await pumpTab(tester);

    expect(orderControl('Match 1 first'), findsOneWidget);
  });

  testWidgets('picking submitted order writes it back', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await pumpTab(tester);
    await tester.tap(orderControl('Match 1 first'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submitted first').last);
    await tester.pumpAndSettle();

    expect(orderControl('Submitted first'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('database_entry_order'), 'submitted');
  });
}
