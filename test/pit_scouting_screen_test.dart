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
import 'support/fake_pit_scouting_sync_service.dart';

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
  tester.view.physicalSize = const Size(800, 6000);
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
        canEditAnyEntry: false,
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Questionnaire'));
  await tester.pumpAndSettle();
}

void main() {
  group('PitScoutingScreen without a photo store', () {
    testWidgets('shows no capture buttons', (tester) async {
      await _pumpScreen(tester, withPhotoStore: false);

      expect(find.text('Camera'), findsNothing);
      expect(find.text('Gallery'), findsNothing);

      expect(find.byType(FutureBuilder<Uint8List>), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the entry really does reference a photo', (tester) async {
      final controller = await _bootController();
      expect(controller.entries.single.photoIds, isNotEmpty);
    });
  });

  group('PitScoutingScreen photo section', () {
    testWidgets('the questionnaire offers capture before anything is saved', (
      tester,
    ) async {
      await _pumpScreen(tester, withPhotoStore: true);

      expect(find.text('Photos'), findsOneWidget);
      expect(
        find.textContaining('attached when you save'),
        findsOneWidget,
        reason: 'the section has to say when the photos actually land',
      );

      expect(find.text('Camera'), findsWidgets);
      expect(find.text('Gallery'), findsWidgets);
    });

    testWidgets('no photo store means no photo section', (tester) async {
      await _pumpScreen(tester, withPhotoStore: false);

      expect(find.text('Photos'), findsNothing);
    });
  });

  group('PitScoutingScreen photo staging edge cases', () {
    testWidgets('the cap counts photos the target entry already has', (
      tester,
    ) async {
      final controller = PitScoutingController(
        storage: FakePitScoutingStorage(),
        photoStore: FakePitPhotoStore(),
      );
      await controller.bootstrap();

      await controller.saveEntry(
        PitScoutEntry(
          teamNumber: 3847,
          authorUid: '',
          photoIds: const ['a', 'b', 'c'],
        ),
      );
      final config = PitScoutConfigController(
        service: FakePitScoutConfigService(),
      );
      await config.bootstrap();

      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PitScoutingScreen(
            controller: controller,
            configController: config,
            canEditAnyEntry: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Questionnaire'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '3847');
      await tester.pumpAndSettle();

      final camera = tester.widget<OutlinedButton>(
        find
            .ancestor(
              of: find.text('Camera'),
              matching: find.byType(OutlinedButton),
            )
            .first,
      );
      expect(
        camera.onPressed,
        isNull,
        reason: 'the entry already holds maxPhotos, so staging must be off',
      );
    });

    testWidgets('the section does not overflow at phone width', (tester) async {
      await _pumpScreen(tester, withPhotoStore: true);
      tester.view.physicalSize = const Size(400, 6000);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Photos'), findsOneWidget);
    });
  });

  group('PitScoutingScreen with a photo store', () {
    testWidgets('capture lives only in the form now', (tester) async {
      await _pumpScreen(tester, withPhotoStore: true);

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Edit in the form above'), findsOneWidget);
    });

    testWidgets('editing an own entry loads its answers and names its team', (
      tester,
    ) async {
      await _pumpScreen(tester, withPhotoStore: true);

      await tester.tap(find.text('Edit in the form above'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Editing your saved entry'),
        findsOneWidget,
        reason: 'the form has to say it is amending, not filing',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '3847',
        reason: 'the loaded entry names its own team',
      );
    });
  });

  testWidgets('a failed save shows the pill', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
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
          canEditAnyEntry: false,
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
          canEditAnyEntry: false,
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

  group('deleting someone else\'s pit entry', () {
    Future<PitScoutingController> bootOtherAuthorEntry() async {
      final controller = PitScoutingController(
        storage: FakePitScoutingStorage(),
      );
      await controller.bootstrap();
      await controller.saveEntry(
        PitScoutEntry(teamNumber: 3847, authorUid: 'someone-else'),
      );
      return controller;
    }

    Future<void> pumpWith({
      required WidgetTester tester,
      required bool canEditAnyEntry,
    }) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final pitScouting = await bootOtherAuthorEntry();
      final configController = PitScoutConfigController(
        service: FakePitScoutConfigService(),
      );
      await configController.bootstrap();

      await tester.pumpWidget(
        MaterialApp(
          home: PitScoutingScreen(
            controller: pitScouting,
            configController: configController,
            canEditAnyEntry: canEditAnyEntry,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Questionnaire'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows only a lock for a scouter', (tester) async {
      await pumpWith(tester: tester, canEditAnyEntry: false);

      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    });

    testWidgets('shows the trash can for a role that matches firestore.rules '
        '(admin/strategy/developer)', (tester) async {
      await pumpWith(tester: tester, canEditAnyEntry: true);

      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });
  });

  group('authorUid is stamped when an entry is filed, not when it syncs', () {
    testWidgets('a new entry is saved with the signed-in uid already on it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final sync = FakePitScoutingSyncService(
        currentUserUid: 'matthieu-uid',
        currentUserDisplayName: 'Matthieu',
      );
      final controller = PitScoutingController(
        storage: FakePitScoutingStorage(),
        syncService: sync,
      );
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
            canEditAnyEntry: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Questionnaire'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '254');
      await tester.tap(find.text('Save pit entry'));
      await tester.pumpAndSettle();

      final saved = controller.entriesForTeam(254).single;
      expect(saved.authorUid, 'matthieu-uid');
      expect(saved.authorDisplayName, 'Matthieu');
    });

    testWidgets(
      're-saving an already-authored entry does not restamp it, even when '
      'the signed-in display name has since changed',
      (tester) async {
        tester.view.physicalSize = const Size(800, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final sync = FakePitScoutingSyncService(
          currentUserUid: 'matthieu-uid',
          currentUserDisplayName: 'New Name',
        );
        final controller = PitScoutingController(
          storage: FakePitScoutingStorage(),
          syncService: sync,
        );
        await controller.bootstrap();
        await controller.saveEntry(
          PitScoutEntry(
            teamNumber: 254,
            authorUid: 'matthieu-uid',
            authorDisplayName: 'Old Name',
          ),
        );
        final configController = PitScoutConfigController(
          service: FakePitScoutConfigService(),
        );
        await configController.bootstrap();

        await tester.pumpWidget(
          MaterialApp(
            home: PitScoutingScreen(
              controller: controller,
              configController: configController,
              canEditAnyEntry: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Questionnaire'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, '254');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save pit entry'));
        await tester.pumpAndSettle();

        final saved = controller.entriesForTeam(254).single;
        expect(saved.authorUid, 'matthieu-uid');
        expect(saved.authorDisplayName, 'Old Name');
      },
    );

    testWidgets(
      'an entry started while signed out is stamped on the next save after '
      'signing in',
      (tester) async {
        tester.view.physicalSize = const Size(800, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final sync = FakePitScoutingSyncService();
        final controller = PitScoutingController(
          storage: FakePitScoutingStorage(),
          syncService: sync,
        );
        await controller.bootstrap();
        await controller.saveEntry(PitScoutEntry(teamNumber: 254));
        expect(controller.entriesForTeam(254).single.authorUid, isEmpty);

        sync.setCurrentUser(uid: 'matthieu-uid', displayName: 'Matthieu');
        final configController = PitScoutConfigController(
          service: FakePitScoutConfigService(),
        );
        await configController.bootstrap();

        await tester.pumpWidget(
          MaterialApp(
            home: PitScoutingScreen(
              controller: controller,
              configController: configController,
              canEditAnyEntry: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Questionnaire'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, '254');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save pit entry'));
        await tester.pumpAndSettle();

        final saved = controller.entriesForTeam(254).single;
        expect(saved.authorUid, 'matthieu-uid');
        expect(saved.authorDisplayName, 'Matthieu');
      },
    );
  });
}
