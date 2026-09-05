import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_config_service.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/ui/pit_database_view.dart';
import 'package:spectrumstrategy/src/ui/pit_scouting_screen.dart';

import 'support/fake_pit_photo_store.dart';
import 'support/fake_pit_scouting_storage.dart';

class _FixedPitConfigService extends ScoutConfigService {
  _FixedPitConfigService(this._config) : super.pit();

  final ScoutConfig _config;

  @override
  Future<ScoutConfig?> loadStored() async => _config;

  @override
  Future<void> save(ScoutConfig config) async {}
}

const ScoutConfig _orderedConfig = ScoutConfig(
  title: 'Pit Scouting',
  pageTitle: '',
  delimiter: '\t',

  revision: 2,
  sections: <ScoutConfigSection>[
    ScoutConfigSection(
      name: 'Robot',
      fields: <ScoutConfigField>[
        ScoutConfigField(
          title: 'Drivetrain Type',
          code: 'drivetrainType',
          type: ScoutFieldType.select,

          choices: <String, String>{'swerve': 'Swerve', 'tank': 'Tank'},
        ),
        ScoutConfigField(
          title: 'Frame Dimensions',
          code: 'frameDimensions',
          type: ScoutFieldType.text,
        ),
        ScoutConfigField(
          title: 'Notes',
          code: 'notes',
          type: ScoutFieldType.text,
        ),
      ],
    ),
  ],
);

void main() {
  group('PitDatabaseView', () {
    testWidgets(
      'renders an entry\'s answers in the pit form\'s question order',
      (tester) async {
        final controller = PitScoutingController(
          storage: FakePitScoutingStorage(),
          photoStore: FakePitPhotoStore(),
        );
        await controller.bootstrap();
        await controller.saveEntry(
          PitScoutEntry(
            teamNumber: 3847,
            authorDisplayName: 'Alexandria',
            fieldValues: const <String, dynamic>{
              'notes': 'Watch their auto, it is fast',
              'drivetrainType': 'swerve',
              'frameDimensions': '28x30',
            },
          ),
        );
        final configController = PitScoutConfigController(
          service: _FixedPitConfigService(_orderedConfig),
        );
        await configController.bootstrap();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PitDatabaseView(
                controller: controller,
                configController: configController,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Team 3847'));
        await tester.pumpAndSettle();

        double dyOf(String text) => tester.getTopLeft(find.text(text)).dy;

        final drivetrain = dyOf('Drivetrain Type');
        final frame = dyOf('Frame Dimensions');
        final notes = dyOf('Notes');

        expect(drivetrain, lessThan(frame));
        expect(frame, lessThan(notes));

        expect(find.textContaining('Swerve'), findsOneWidget);
      },
    );

    testWidgets(
      'shows a placeholder when a remote entry only carries photoKeys and no '
      'local bytes are available',
      (tester) async {
        final controller = PitScoutingController(
          storage: FakePitScoutingStorage(),
        );
        await controller.bootstrap();
        await controller.saveEntry(
          PitScoutEntry(
            teamNumber: 254,
            authorUid: 'uid-remote',

            photoKeys: const <String, String>{'r2-key-abc': 'r2-key-abc'},
          ),
        );
        final configController = PitScoutConfigController(
          service: _FixedPitConfigService(_orderedConfig),
        );
        await configController.bootstrap();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PitDatabaseView(
                controller: controller,
                configController: configController,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Team 254'));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
        expect(find.byIcon(Icons.broken_image_rounded), findsNothing);
      },
    );

    testWidgets('shows an empty state when there are no pit entries', (
      tester,
    ) async {
      final controller = PitScoutingController(
        storage: FakePitScoutingStorage(),
      );
      await controller.bootstrap();
      final configController = PitScoutConfigController(
        service: _FixedPitConfigService(_orderedConfig),
      );
      await configController.bootstrap();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PitDatabaseView(
              controller: controller,
              configController: configController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No pit entries submitted yet.'), findsOneWidget);
    });

    testWidgets('lists entries oldest submission first', (tester) async {
      final storage = FakePitScoutingStorage();
      await storage.saveEntry(
        PitScoutEntry(teamNumber: 100, updatedAt: DateTime.utc(2026, 3, 1)),
      );
      await storage.saveEntry(
        PitScoutEntry(teamNumber: 200, updatedAt: DateTime.utc(2026, 3, 2)),
      );
      final controller = PitScoutingController(storage: storage);
      await controller.bootstrap();
      final configController = PitScoutConfigController(
        service: _FixedPitConfigService(_orderedConfig),
      );
      await configController.bootstrap();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PitDatabaseView(
              controller: controller,
              configController: configController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final firstY = tester.getTopLeft(find.text('Team 100')).dy;
      final secondY = tester.getTopLeft(find.text('Team 200')).dy;
      expect(firstY, lessThan(secondY));
    });

    testWidgets('offers no edit affordance: the view is read-only', (
      tester,
    ) async {
      final controller = PitScoutingController(
        storage: FakePitScoutingStorage(),
        photoStore: FakePitPhotoStore(),
      );
      await controller.bootstrap();
      await controller.saveEntry(PitScoutEntry(teamNumber: 3847));
      final configController = PitScoutConfigController(
        service: _FixedPitConfigService(_orderedConfig),
      );
      await configController.bootstrap();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PitDatabaseView(
              controller: controller,
              configController: configController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Team 3847'));
      await tester.pumpAndSettle();

      expect(find.text('Edit entry'), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    });
  });

  group('PitScoutingScreen Database tab', () {
    testWidgets('the Database tab shows every submission, tabbed ahead of the '
        'questionnaire', (tester) async {
      final pitController = PitScoutingController(
        storage: FakePitScoutingStorage(),
        photoStore: FakePitPhotoStore(),
      );
      await pitController.bootstrap();
      await pitController.saveEntry(PitScoutEntry(teamNumber: 3847));
      final pitConfig = PitScoutConfigController(
        service: _FixedPitConfigService(_orderedConfig),
      );
      await pitConfig.bootstrap();

      await tester.pumpWidget(
        MaterialApp(
          home: PitScoutingScreen(
            controller: pitController,
            configController: pitConfig,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Database'), findsOneWidget);
      expect(find.text('Questionnaire'), findsOneWidget);
      expect(find.text('Team 3847'), findsOneWidget);
    });
  });
}
