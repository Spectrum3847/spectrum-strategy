import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/ui/pit_question_editor.dart';

import 'support/fake_pit_scout_config_service.dart';

Future<void> _pump(WidgetTester tester, PitScoutConfigController controller) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PitQuestionEditor(controller: controller),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PitScoutConfigController controller;

  setUp(() async {
    controller = PitScoutConfigController(service: FakePitScoutConfigService());
    await controller.bootstrap();
  });

  tearDown(() => controller.dispose());

  testWidgets('adding a question appends it to its section', (tester) async {
    await _pump(tester, controller);

    await tester.ensureVisible(find.text('Add question').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add question').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Question'),
      'Bumper Color',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Bumper Color'), findsOneWidget);
    final drivetrain = controller.config.sections.firstWhere(
      (s) => s.name == 'Drivetrain',
    );
    expect(drivetrain.fields.last.title, 'Bumper Color');
    expect(drivetrain.fields.last.code, 'bumperColor');
  });

  testWidgets('editing a question keeps its code but changes the title', (
    tester,
  ) async {
    await _pump(tester, controller);

    await tester.tap(find.byTooltip('Edit question').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Question'),
      'Drivetrain Kind',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Drivetrain Kind'), findsOneWidget);
    expect(controller.config.allFields.first.title, 'Drivetrain Kind');
    expect(controller.config.allFields.first.code, 'drivetrainType');
  });

  testWidgets('deleting a question asks for confirmation, then removes it', (
    tester,
  ) async {
    await _pump(tester, controller);
    final before = controller.config.allFields.length;

    await tester.tap(find.byTooltip('Delete question').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(controller.config.allFields.length, before - 1);
  });

  testWidgets('moving a question down swaps its order within the section', (
    tester,
  ) async {
    await _pump(tester, controller);

    final firstTitle = controller.config.sections.first.fields[0].title;
    final secondTitle = controller.config.sections.first.fields[1].title;

    await tester.tap(find.byTooltip('Move down').first);
    await tester.pumpAndSettle();

    expect(controller.config.sections.first.fields[0].title, secondTitle);
    expect(controller.config.sections.first.fields[1].title, firstTitle);
  });

  testWidgets('adding a section appends an empty one', (tester) async {
    await _pump(tester, controller);
    final before = controller.config.sections.length;

    await tester.ensureVisible(find.text('Add section'));
    await tester.tap(find.text('Add section'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Section name'),
      'Autonomous',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(controller.config.sections.length, before + 1);
    expect(controller.config.sections.last.name, 'Autonomous');
    expect(controller.config.sections.last.fields, isEmpty);
  });

  testWidgets('a non-empty section refuses to delete', (tester) async {
    await _pump(tester, controller);

    await tester.tap(find.byTooltip('Delete section').first);
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(controller.config.sections.first.name, 'Drivetrain');
  });

  testWidgets('editing a select question shows its current choices', (
    tester,
  ) async {
    await _pump(tester, controller);

    await tester.tap(find.byTooltip('Edit question').first);
    await tester.pumpAndSettle();

    expect(find.text('Choices'), findsOneWidget);
    expect(find.text('Tank / Skid Steer'), findsOneWidget);
    expect(find.text('Swerve'), findsOneWidget);
  });

  testWidgets('adding a choice appends it to the select field', (tester) async {
    await _pump(tester, controller);
    final before = controller.config.allFields.first.choices!.length;

    await tester.tap(find.byTooltip('Edit question').first);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add choice'));
    await tester.tap(find.text('Add choice'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Choice label'),
      'Custom',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final choices = controller.config.allFields.first.choices!;
    expect(choices.length, before + 1);
    expect(choices['custom'], 'Custom');
  });

  testWidgets('removing a choice retires it, but never the last active one', (
    tester,
  ) async {
    await _pump(tester, controller);
    final totalChoices = controller.config.allFields.first.choices!.length;

    await tester.tap(find.byTooltip('Edit question').first);
    await tester.pumpAndSettle();

    final startingCount = find.byTooltip('Remove choice').evaluate().length;
    for (var i = 0; i < startingCount - 1; i++) {
      await tester.tap(find.byTooltip('Remove choice').first);
      await tester.pump();
    }

    final lastRemoveButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Remove choice').first,
        matching: find.byType(IconButton),
      ),
    );
    expect(lastRemoveButton.onPressed, isNull);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final field = controller.config.allFields.first;

    expect(field.choices!.length, totalChoices);

    expect(field.activeChoices.length, 1);
    expect(field.retiredChoiceKeys.length, totalChoices - 1);
  });

  testWidgets(
    're-opening the editor after removing a choice hides it, not just its '
    'remove button',
    (tester) async {
      await _pump(tester, controller);

      await tester.tap(find.byTooltip('Edit question').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove choice').first);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit question').first);
      await tester.pumpAndSettle();

      expect(find.text('Tank / Skid Steer'), findsNothing);
      expect(find.text('Swerve'), findsOneWidget);
    },
  );

  testWidgets('reordering a choice moves it within the choice list', (
    tester,
  ) async {
    await _pump(tester, controller);

    await tester.tap(find.byTooltip('Edit question').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Move choice down').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(controller.config.allFields.first.choices!.keys.first, 'swerve');
  });

  testWidgets('renaming a choice changes its label but keeps its key', (
    tester,
  ) async {
    await _pump(tester, controller);

    await tester.tap(find.byTooltip('Edit question').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Rename choice').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Choice label'),
      'Tank Drive',
    );
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final choices = controller.config.allFields.first.choices!;
    expect(choices.keys.first, 'tank');
    expect(choices['tank'], 'Tank Drive');
  });
}
