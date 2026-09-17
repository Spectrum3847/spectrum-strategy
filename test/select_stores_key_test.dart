import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_form_fields.dart';

const ScoutConfigField _field = ScoutConfigField(
  title: 'Where did it score from',
  code: 'scoreFrom',
  type: ScoutFieldType.select,
  choices: <String, String>{'1': 'Outpost', '2': 'Depot', '3': 'Hub'},
);

Future<Map<String, dynamic>> _pumpForm(
  WidgetTester tester,
  Map<String, dynamic> values,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScoutFormSection(
            section: const ScoutConfigSection(
              name: 'Teleop',
              fields: <ScoutConfigField>[_field],
            ),
            keyPrefix: 'scout-field',
            values: values,
            textControllers: <String, TextEditingController>{},
            onFieldChanged: (String code, dynamic value) =>
                values[code] = value,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return values;
}

void main() {
  group('resolveStoredChoice', () {
    test('a key resolves to itself', () {
      expect(_field.resolveStoredChoice('2'), '2');
    });

    test('a label resolves to its key, which is the migration', () {
      expect(_field.resolveStoredChoice('Depot'), '2');
    });

    test('an unrecognised value resolves to nothing', () {
      expect(_field.resolveStoredChoice('Loading bay'), isNull);
      expect(_field.resolveStoredChoice(''), isNull);
      expect(_field.resolveStoredChoice(null), isNull);
    });

    test('labelForStored shows the label, or the raw value when unknown', () {
      expect(_field.labelForStored('2'), 'Depot');
      expect(_field.labelForStored('Depot'), 'Depot');
      expect(_field.labelForStored('Loading bay'), 'Loading bay');
    });
  });

  test('the default value is the first key, not the first label', () {
    expect(_field.effectiveDefault, '1');
  });

  testWidgets('the form shows labels and stores the key', (tester) async {
    final values = await _pumpForm(tester, <String, dynamic>{'scoreFrom': '1'});

    expect(find.text('Outpost'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('scout-field-scoreFrom')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hub').last);
    await tester.pumpAndSettle();

    expect(values['scoreFrom'], '3');
  });

  testWidgets('an entry holding a label is migrated on read', (tester) async {
    final values = await _pumpForm(tester, <String, dynamic>{
      'scoreFrom': 'Depot',
    });

    expect(find.text('Depot'), findsOneWidget);
    expect(values['scoreFrom'], '2');
  });

  testWidgets('an unrecognised stored value falls back to the first choice', (
    tester,
  ) async {
    final values = await _pumpForm(tester, <String, dynamic>{
      'scoreFrom': 'Loading bay',
    });

    expect(values['scoreFrom'], '1');
  });

  group('flipping the shipped default configs stays migration-safe', () {
    const ScoutConfigField robotField = ScoutConfigField(
      title: 'Robot Driver Station',
      code: 'robot',
      type: ScoutFieldType.select,
      choices: <String, String>{
        'R1': 'Red 1',
        'R2': 'Red 2',
        'R3': 'Red 3',
        'B1': 'Blue 1',
        'B2': 'Blue 2',
        'B3': 'Blue 3',
      },
    );

    test('a value stored under the old inverted map still resolves', () {
      expect(robotField.resolveStoredChoice('Red 1'), 'R1');
      expect(robotField.labelForStored('Red 1'), 'Red 1');
    });

    const ScoutConfigField drivetrainField = ScoutConfigField(
      title: 'Drivetrain Type',
      code: 'drivetrainType',
      type: ScoutFieldType.select,
      choices: <String, String>{
        'tank': 'Tank / Skid Steer',
        'swerve': 'Swerve',
        'mecanum': 'Mecanum',
        'omni': 'Omni',
        'other': 'Other',
      },
    );

    test('a pit entry stored under the old inverted map still resolves', () {
      expect(drivetrainField.resolveStoredChoice('Tank / Skid Steer'), 'tank');
      expect(
        drivetrainField.labelForStored('Tank / Skid Steer'),
        'Tank / Skid Steer',
      );
    });

    testWidgets(
      'a form built from the flipped map still shows the old entry correctly',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ScoutFormSection(
                  section: const ScoutConfigSection(
                    name: 'Drivetrain',
                    fields: <ScoutConfigField>[drivetrainField],
                  ),
                  keyPrefix: 'pit-field',
                  values: <String, dynamic>{
                    'drivetrainType': 'Tank / Skid Steer',
                  },
                  textControllers: <String, TextEditingController>{},
                  onFieldChanged: (String code, dynamic value) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tank / Skid Steer'), findsOneWidget);
        expect(find.text('tank'), findsNothing);
      },
    );
  });

  group('a retired choice', () {
    const retiredField = ScoutConfigField(
      title: 'Where did it score from',
      code: 'scoreFrom',
      type: ScoutFieldType.select,
      choices: <String, String>{'1': 'Outpost', '2': 'Depot', '3': 'Hub'},
      retiredChoiceKeys: {'2'},
    );

    testWidgets('still shows the label for an entry captured against it', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScoutFormSection(
                section: const ScoutConfigSection(
                  name: 'Teleop',
                  fields: <ScoutConfigField>[retiredField],
                ),
                keyPrefix: 'scout-field',
                values: <String, dynamic>{'scoreFrom': '2'},
                textControllers: <String, TextEditingController>{},
                onFieldChanged: (String code, dynamic value) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Depot'), findsOneWidget);
    });

    testWidgets('is not offered to a new answer', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScoutFormSection(
                section: const ScoutConfigSection(
                  name: 'Teleop',
                  fields: <ScoutConfigField>[retiredField],
                ),
                keyPrefix: 'scout-field',
                values: <String, dynamic>{'scoreFrom': '1'},
                textControllers: <String, TextEditingController>{},
                onFieldChanged: (String code, dynamic value) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('scout-field-scoreFrom')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Outpost').hitTestable(), findsOneWidget);
      expect(find.text('Hub').hitTestable(), findsOneWidget);
      expect(find.text('Depot'), findsNothing);
    });
  });
}
