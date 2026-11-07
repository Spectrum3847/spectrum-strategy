import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_form_fields.dart';

const _configJson = '''
{
  "title": "Test",
  "page_title": "Test",
  "delimiter": "\\t",
  "sections": [
    {
      "name": "Endgame",
      "fields": [
        {
          "title": "Penalties",
          "type": "checkbox-select",
          "code": "penalties",
          "required": false,
          "formResetBehavior": "reset",
          "defaultValue": [],
          "choices": {
            "foul": "Foul",
            "techFoul": "Tech Foul",
            "card": "Yellow Card"
          }
        }
      ]
    }
  ]
}
''';

final String _defaultedConfigJson = _configJson.replaceFirst(
  '"defaultValue": []',
  '"defaultValue": ["foul"]',
);

ScoutConfigField _field() {
  final config = ScoutConfig.fromJson(
    jsonDecode(_configJson) as Map<String, dynamic>,
  );
  return config.allFields.single;
}

void main() {
  group('the checkbox-select model', () {
    test('the type is recognised, not degraded to text', () {
      final field = _field();

      expect(field.type, ScoutFieldType.checkboxSelect);
      expect(field.typeIsUnsupported, isFalse);
      expect(field.choices, hasLength(3));
    });

    test('it survives a save and reload of the config', () {
      final reloaded = ScoutConfig.fromJson(
        jsonDecode(
          jsonEncode(
            ScoutConfig.fromJson(
              jsonDecode(_configJson) as Map<String, dynamic>,
            ).toJson(),
          ),
        ) as Map<String, dynamic>,
      );

      expect(
        jsonDecode(
          jsonEncode(reloaded.toJson()),
        )['sections'][0]['fields'][0]['type'],
        'checkbox-select',
      );
      expect(reloaded.allFields.single.type, ScoutFieldType.checkboxSelect);
    });

    test('keys read back from both shapes the value arrives in', () {
      expect(ScoutConfigField.selectedKeys(<String>['a', 'b']), ['a', 'b']);
      expect(ScoutConfigField.selectedKeys('a,b'), ['a', 'b']);

      expect(ScoutConfigField.selectedKeys(' a , ,b '), ['a', 'b']);
      expect(ScoutConfigField.selectedKeys(''), isEmpty);
      expect(ScoutConfigField.selectedKeys(null), isEmpty);
    });

    test('nothing ticked serialises to an empty field, not to a literal', () {
      final field = _field();

      expect(field.serializeValue(''), '');
      expect(field.serializeValue(null), '');

      expect(field.serializeValue(<String>['foul', 'card']), 'foul,card');
    });

    test('the default is the configured list, already joined', () {
      final defaulted = ScoutConfig.fromJson(
        jsonDecode(_defaultedConfigJson) as Map<String, dynamic>,
      ).allFields.single;

      expect(defaulted.effectiveDefault, 'foul');
      expect(_field().effectiveDefault, '');
    });
  });

  group('multi-select maps onto the same field', () {
    ScoutConfigField multiSelectField() {
      final config = ScoutConfig.fromJson(
        jsonDecode(
          _configJson.replaceFirst(
            '"type": "checkbox-select"',
            '"type": "multi-select"',
          ),
        ) as Map<String, dynamic>,
      );
      return config.allFields.single;
    }

    test('the type is recognised, not degraded to text', () {
      expect(multiSelectField().type, ScoutFieldType.checkboxSelect);
    });

    test('the choices survive with their keys', () {
      expect(multiSelectField().choices!.keys, <String>[
        'foul',
        'techFoul',
        'card',
      ]);
    });

    test('the spelling variants all land on the same type', () {
      for (final spelling in <String>[
        'multi-select',
        'multi_select',
        'multiSelect',
        'MULTISELECT',
      ]) {
        expect(
          ScoutFieldType.fromString(spelling),
          ScoutFieldType.checkboxSelect,
          reason: spelling,
        );
      }
    });

    test('it is no longer listed as knowingly unsupported', () {
      expect(
        ScoutConfig.knownUnsupportedTypes.keys,
        isNot(contains('multiselect')),
      );
    });
  });

  group('the checkbox-select form control', () {
    Future<Map<String, dynamic>> pumpField(
      WidgetTester tester, {
      dynamic initial,
      String? configJson,
    }) async {
      final config = ScoutConfig.fromJson(
        jsonDecode(configJson ?? _configJson) as Map<String, dynamic>,
      );
      final values = <String, dynamic>{'penalties': ?initial};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: ScoutFormSection(
                  section: config.sections.single,
                  keyPrefix: 'test',
                  values: values,
                  textControllers: const <String, TextEditingController>{},
                  onFieldChanged: (code, value) =>
                      setState(() => values[code] = value),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return values;
    }

    testWidgets('every choice is a chip, labelled not keyed', (tester) async {
      await pumpField(tester);

      expect(find.byType(FilterChip), findsNWidgets(3));

      expect(find.text('Tech Foul'), findsOneWidget);
      expect(find.text('techFoul'), findsNothing);
    });

    testWidgets('ticking two stores both keys, comma joined', (tester) async {
      final values = await pumpField(tester);

      await tester.tap(find.text('Foul'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yellow Card'));
      await tester.pumpAndSettle();

      expect(values['penalties'], 'foul,card');
    });

    testWidgets('the stored order follows the config, not the taps', (
      tester,
    ) async {
      final values = await pumpField(tester);

      await tester.tap(find.text('Yellow Card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Foul'));
      await tester.pumpAndSettle();

      expect(values['penalties'], 'foul,card');
    });

    testWidgets('unticking removes only that key', (tester) async {
      final values = await pumpField(tester, initial: 'foul,techFoul,card');

      await tester.tap(find.text('Tech Foul'));
      await tester.pumpAndSettle();

      expect(values['penalties'], 'foul,card');
    });

    testWidgets('a configured default arrives pre-ticked', (tester) async {
      await pumpField(tester, configJson: _defaultedConfigJson);

      final ticked = tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .where((chip) => chip.selected)
          .map((chip) => (chip.label as Text).data)
          .toList();
      expect(ticked, <String>['Foul']);
    });

    testWidgets('a stored selection shows as ticked on reopen', (tester) async {
      await pumpField(tester, initial: 'card');

      final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
      final ticked = <String>[
        for (final chip in chips)
          if (chip.selected) ((chip.label as Text).data ?? ''),
      ];
      expect(ticked, <String>['Yellow Card']);
    });
  });
}
