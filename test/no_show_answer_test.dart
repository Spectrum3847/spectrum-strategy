import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/services/no_show_answer.dart';

const _starting = ScoutConfigField(
  title: 'Robot Starting Position',
  type: ScoutFieldType.select,
  code: 'starting',
  defaultValue: '',
  choices: <String, String>{
    'No Show': 'No Show',
    'Depot Trench': 'Depot Trench',
  },
);

const _config = ScoutConfig(
  title: 'Scout',
  sections: [
    ScoutConfigSection(
      name: 'Match',
      fields: [
        _starting,
        ScoutConfigField(
          title: 'Fuel scored',
          type: ScoutFieldType.counter,
          code: 'fuel',
        ),
        ScoutConfigField(
          title: 'Accuracy',
          type: ScoutFieldType.range,
          code: 'accuracy',
          defaultValue: 50,
        ),
        ScoutConfigField(
          title: 'Played defense',
          type: ScoutFieldType.boolean,
          code: 'defense',
        ),
      ],
    ),
  ],
);

bool _contradicted(Map<String, dynamic> values) =>
    isContradictedNoShow(_starting, values, _config);

void main() {
  test('No Show with a scored counter contradicts itself', () {
    expect(_contradicted({'starting': 'No Show', 'fuel': 12}), isTrue);
    expect(_contradicted({'starting': 'No Show', 'fuel': '3'}), isTrue);
  });

  test('No Show with a checked box or a moved range contradicts itself', () {
    expect(_contradicted({'starting': 'No Show', 'defense': true}), isTrue);
    expect(_contradicted({'starting': 'No Show', 'accuracy': 80}), isTrue);
  });

  test('No Show with nothing played stands', () {
    expect(
      _contradicted({
        'starting': 'No Show',
        'fuel': 0,
        'accuracy': 50,
        'defense': false,
      }),
      isFalse,
    );
    expect(_contradicted({'starting': 'No Show'}), isFalse);
  });

  test('a real start is never contradicted', () {
    expect(_contradicted({'starting': 'Depot Trench', 'fuel': 12}), isFalse);
    expect(_contradicted({'starting': '', 'fuel': 12}), isFalse);
  });

  test('only a select can be a No Show answer', () {
    const text = ScoutConfigField(
      title: 'Notes',
      type: ScoutFieldType.text,
      code: 'notes',
    );
    expect(
      isContradictedNoShow(text, {'notes': 'No Show', 'fuel': 4}, _config),
      isFalse,
    );
  });
}
