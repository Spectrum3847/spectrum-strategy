import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/ui/pit_scouting_screen.dart';

import 'support/fake_pit_photo_store.dart';
import 'support/fake_pit_scout_config_service.dart';
import 'support/fake_pit_scouting_storage.dart';

class _FlakyPitScoutingStorage extends FakePitScoutingStorage {
  bool failNextSave = false;

  @override
  Future<void> saveEntry(PitScoutEntry entry) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('simulated storage failure');
    }
    await super.saveEntry(entry);
  }
}

Future<PitScoutingController> _bootController({
  bool withPhotoStore = false,
}) async {
  final controller = PitScoutingController(
    storage: FakePitScoutingStorage(),
    photoStore: withPhotoStore ? FakePitPhotoStore() : null,
  );
  await controller.bootstrap();

  await controller.saveEntry(
    PitScoutEntry(
      teamNumber: 3847,
      authorUid: '',
      photoIds: withPhotoStore ? null : const ['photo1'],
    ),
  );
  return controller;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required bool withPhotoStore,
}) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final pitScouting = await _bootController(withPhotoStore: withPhotoStore);
  final configController = PitScoutConfigController(
    service: FakePitScoutConfigService(),
  );
  await configController.bootstrap();

  await tester.pumpWidget(
    MaterialApp(
      home: PitScoutingScreen(
        controller: pitScouting,
        configController: configController,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Questionnaire'));
  await tester.pumpAndSettle();
}

void main() {
  group('PitScoutingScreen without a photo store', () {
    testWidgets('shows the unsupported message and no capture buttons', (
      tester,
    ) async {
      await _pumpScreen(tester, withPhotoStore: false);

      expect(find.text('Camera'), findsNothing);
      expect(find.text('Gallery'), findsNothing);
      expect(
        find.textContaining('Pit photos are not supported on web'),
        findsOneWidget,
      );

      expect(find.byType(FutureBuilder<Uint8List>), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the entry really does reference a photo', (tester) async {
      final controller = await _bootController();
      expect(controller.entries.single.photoIds, isNotEmpty);
    });
  });

  group('PitScoutingScreen with a photo store', () {
    testWidgets('shows the capture buttons for an own entry', (tester) async {
      await _pumpScreen(tester, withPhotoStore: true);

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(
        find.textContaining('Pit photos are not supported on web'),
        findsNothing,
      );
    });
  });

  testWidgets('a failed save shows the pill', (tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final storage = _FlakyPitScoutingStorage();
    final controller = PitScoutingController(storage: storage);
    await controller.bootstrap();
    final configController = PitScoutConfigController(
      service: FakePitScoutConfigService(),
    );
    await configController.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        home: PitScoutingScreen(
          controller: controller,
          configController: configController,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Questionnaire'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not saved'), findsNothing);

    storage.failNextSave = true;
    await tester.enterText(find.byType(TextField).first, '3847');
    await tester.tap(find.text('Save pit entry'));
    await tester.pumpAndSettle();

    expect(find.text('1 edit not saved'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '254');
    await tester.tap(find.text('Save pit entry'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not saved'), findsNothing);
  });

  testWidgets('only the database and questionnaire tabs show', (tester) async {
    final pitScouting = await _bootController(withPhotoStore: false);
    final configController = PitScoutConfigController(
      service: FakePitScoutConfigService(),
    );
    await configController.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        home: PitScoutingScreen(
          controller: pitScouting,
          configController: configController,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Database'), findsOneWidget);
    expect(find.text('Questionnaire'), findsOneWidget);
    expect(find.text('T-Rex assignments'), findsNothing);
    expect(find.text('T-Rex traits'), findsNothing);
    expect(find.byType(Tab), findsNWidgets(2));
  });
}
