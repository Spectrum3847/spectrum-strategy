import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_form_check.dart';

ScoutConfigField _field(
  String code,
  ScoutFieldType type, {
  bool required = true,
  Map<String, String>? choices,
  String visibleWhenCode = '',
  String visibleWhenValue = '',
  double? min,
  double? max,
}) => ScoutConfigField(
  title: 'Title $code',
  type: type,
  code: code,
  required: required,
  choices: choices,
  visibleWhenCode: visibleWhenCode,
  visibleWhenValue: visibleWhenValue,
  min: min,
  max: max,
);

ScoutConfig _config(List<ScoutConfigField> fields) => ScoutConfig(
  title: 'Test',
  sections: [ScoutConfigSection(name: 'S', fields: fields)],
);

List<String> _empty(List<ScoutConfigField> fields, Map<String, dynamic> v) =>
    emptyRequiredFields(_config(fields), v).map((f) => f.code).toList();

void main() {
  group('emptyRequiredFields', () {
    test('flags blank text, unset select and a missing team', () {
      final fields = [
        _field('scouter', ScoutFieldType.text),
        _field(
          'start',
          ScoutFieldType.select,
          choices: const {'a': 'A', 'b': 'B'},
        ),
        _field('team', ScoutFieldType.tbaTeamAndRobot),
        _field('notes', ScoutFieldType.longText),
      ];

      expect(
        _empty(fields, {
          'scouter': '  ',
          'start': '',
          'team': {'teamNumber': 0, 'robotPosition': 'R1'},
          'notes': 'ok',
        }),
        ['scouter', 'start', 'team'],
      );
    });

    test('flags a number outside its min and max', () {
      final fields = [
        _field('team', ScoutFieldType.number, min: 1, max: 19999),
        _field('free', ScoutFieldType.number),
      ];

      expect(_empty(fields, {'team': '0', 'free': '0'}), ['team']);
      expect(_empty(fields, {'team': '', 'free': ''}), ['team', 'free']);
      expect(_empty(fields, {'team': '20000', 'free': '5'}), ['team']);
      expect(_empty(fields, {'team': '3847', 'free': '0'}), isEmpty);
    });

    test('never flags a counter at zero, a false boolean or a range', () {
      final fields = [
        _field('count', ScoutFieldType.counter),
        _field('flag', ScoutFieldType.boolean),
        _field('rate', ScoutFieldType.range),
        _field('tracker', ScoutFieldType.actionTracker),
      ];

      expect(_empty(fields, {'count': 0, 'flag': false, 'rate': 0}), isEmpty);
    });

    test('skips fields that are not required or not visible', () {
      final fields = [
        _field('optional', ScoutFieldType.text, required: false),
        _field('mode', ScoutFieldType.select, choices: const {'a': 'A'}),
        _field(
          'other',
          ScoutFieldType.text,
          visibleWhenCode: 'mode',
          visibleWhenValue: 'other',
        ),
      ];

      expect(
        _empty(fields, {'optional': '', 'mode': 'a', 'other': ''}),
        isEmpty,
      );
      expect(_empty(fields, {'optional': '', 'mode': 'other', 'other': ''}), [
        'other',
      ]);
    });

    test('reports nothing for a robot marked No Show', () {
      final fields = [
        _field(
          'start',
          ScoutFieldType.select,
          choices: const {'No Show': 'No Show', 'c': 'Center'},
        ),
        _field('scouter', ScoutFieldType.text),
      ];

      expect(_empty(fields, {'start': 'No Show', 'scouter': ''}), isEmpty);
      expect(_empty(fields, {'start': 'c', 'scouter': ''}), ['scouter']);
    });
  });
}
