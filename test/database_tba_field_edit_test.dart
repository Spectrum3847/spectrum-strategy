import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';

void main() {
  const config = ScoutConfig(
    title: 'TBA fields',

    revision: 2,
    sections: <ScoutConfigSection>[
      ScoutConfigSection(
        name: 'Prematch',
        fields: <ScoutConfigField>[
          ScoutConfigField(
            title: 'Match',
            type: ScoutFieldType.tbaMatchNumber,
            code: 'matchNumber',
          ),
        ],
      ),
    ],
  );

  Future<ScoutingController> pumpTab(WidgetTester tester) async {
    final service = FakeScoutConfigService();
    await service.save(config);
    final configController = ScoutConfigController(service: service);
    final scouting = ScoutingController(storage: FakeScoutingStorage());
    await scouting.bootstrap();
    await configController.bootstrap();
    await scouting.saveEntry(
      ScoutEntry(
        matchId: '2026txdri1_qm7',
        teamNumber: 3847,
        alliance: 'Red',
        authorDisplayName: 'Alex',
        updatedAt: DateTime.utc(2026, 3, 1),
        fieldValues: const <String, dynamic>{'matchNumber': 7},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatabaseTab(
            scoutingController: scouting,
            configController: configController,
            eventController: EventController(),
            canEditAnyEntry: true,
            canAddManualEntry: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return scouting;
  }

  testWidgets('a TBA match number opens filled and saves as a number', (
    tester,
  ) async {
    final scouting = await pumpTab(tester);

    await tester.tap(find.text('Rows'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Team 3847').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit entry'));
    await tester.pumpAndSettle();

    final box = find.widgetWithText(TextField, '7');
    expect(box, findsOneWidget);

    await tester.enterText(box, '9');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = scouting.entries.single.fieldValues['matchNumber'];

    expect(saved, 9);
    expect(saved, isA<num>());
  });
}
