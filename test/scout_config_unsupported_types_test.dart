import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';

import 'support/fake_pit_scout_config_service.dart';
import 'support/fake_scout_config_service.dart';

String configJson(List<Map<String, dynamic>> fields) => jsonEncode({
  'title': 'Test',
  'page_title': '',
  'delimiter': '\t',
  'sections': [
    {'name': 'Auto', 'fields': fields},
  ],
});

Map<String, dynamic> field(String code, String type) => <String, dynamic>{
  'title': code,
  'type': type,
  'required': false,
  'code': code,
  'formResetBehavior': 'reset',
};

void main() {
  test('the QRScout 2026 types this app cannot render are reported', () {
    final config = ScoutConfig.fromJson(
      jsonDecode(
        configJson([
          field('a', 'action-tracker'),
          field('sm', 'TBA-match-number'),
          field('st', 'TBA-team-and-robot'),
          field('c', 'checkbox-select'),

          field('m', 'multi-select'),

          field('t', 'timer'),
          field('i', 'image'),
        ]),
      ) as Map<String, dynamic>,
    );

    expect(config.unsupportedFieldTypes, <String>['timer', 'image']);
  });

  test('an implemented type is not reported as unsupported', () {
    final config = ScoutConfig.fromJson(
      jsonDecode(configJson([field('a', 'action-tracker')]))
          as Map<String, dynamic>,
    );

    expect(config.unsupportedFieldTypes, isEmpty);
    expect(config.allFields.single.type, ScoutFieldType.actionTracker);
  });

  test('the two schedule-backed types are implemented', () {
    final config = ScoutConfig.fromJson(
      jsonDecode(
        configJson([
          field('matchNumber', 'TBA-match-number'),
          field('robotTeam', 'TBA-team-and-robot'),
        ]),
      ) as Map<String, dynamic>,
    );

    expect(config.unsupportedFieldTypes, isEmpty);
    expect(config.allFields.map((f) => f.type), <ScoutFieldType>[
      ScoutFieldType.tbaMatchNumber,
      ScoutFieldType.tbaTeamAndRobot,
    ]);
  });

  test('the types that do map are not reported', () {
    final config = ScoutConfig.fromJson(
      jsonDecode(
        configJson([
          field('a', 'text'),
          field('b', 'number'),
          field('c', 'boolean'),
          field('d', 'select'),
          field('e', 'range'),
          field('f', 'counter'),
          field('g', 'multi-counter'),

          field('h', 'checkbox'),
          field('i', 'dropdown'),
          field('j', 'slider'),
        ]),
      ) as Map<String, dynamic>,
    );

    expect(config.unsupportedFieldTypes, isEmpty);
  });

  test('the same unknown type twice is reported once', () {
    final config = ScoutConfig.fromJson(
      jsonDecode(
        configJson([
          field('a', 'timer'),
          field('b', 'checkbox_select'),
          field('c', 'CHECKBOX-SELECT'),
        ]),
      ) as Map<String, dynamic>,
    );

    expect(config.unsupportedFieldTypes, <String>['timer']);
  });

  test('a config built in code reports nothing', () {
    const config = ScoutConfig(
      title: 'Built',
      pageTitle: '',
      delimiter: '\t',
      sections: <ScoutConfigSection>[
        ScoutConfigSection(
          name: 'Auto',
          fields: <ScoutConfigField>[
            ScoutConfigField(
              title: 'Notes',
              type: ScoutFieldType.text,
              code: 'n',
            ),
          ],
        ),
      ],
    );

    expect(config.unsupportedFieldTypes, isEmpty);
    expect(config.allFields.single.typeIsUnsupported, isFalse);
  });

  test('a round trip keeps an unsupported type instead of writing text', () {
    final config = ScoutConfig.fromJson(
      jsonDecode(configJson([field('c', 'timer')])) as Map<String, dynamic>,
    );

    final reloaded = ScoutConfig.fromJson(
      jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
    );
    expect(reloaded.unsupportedFieldTypes, <String>['timer']);
    expect(reloaded.allFields.single.rawType, 'timer');
  });

  test('a supported type still round-trips to its canonical name', () {
    final config = ScoutConfig.fromJson(
      jsonDecode(configJson([field('d', 'dropdown')])) as Map<String, dynamic>,
    );

    expect(config.toJson()['sections'][0]['fields'][0]['type'], 'select');
  });

  test('editing a field title keeps the unsupported marker', () {
    final config = ScoutConfig.fromJson(
      jsonDecode(configJson([field('c', 'timer')])) as Map<String, dynamic>,
    );
    final edited = config.allFields.single.copyWith(title: 'Match');

    expect(edited.rawType, 'timer');
    expect(edited.typeIsUnsupported, isTrue);
  });

  group('both config controllers surface unsupported types', () {
    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    test('the match config controller does', () async {
      final controller = ScoutConfigController(
        service: FakeScoutConfigService(),
      );
      await controller.bootstrap();

      await controller.loadFromJsonString(configJson([field('c', 'timer')]));

      expect(controller.config.unsupportedFieldTypes, <String>['timer']);
      controller.dispose();
    });

    test('the pit config controller does too', () async {
      final controller = PitScoutConfigController(
        service: FakePitScoutConfigService(),
      );
      await controller.bootstrap();

      await controller.loadFromJsonString(configJson([field('a', 'image')]));

      expect(controller.config.unsupportedFieldTypes, <String>['image']);
      controller.dispose();
    });
  });

  group('known versus unrecognised', () {
    test('splits the two apart', () {
      final config = ScoutConfig.fromJson(
        jsonDecode(
          configJson([
            field('a', 'image'),
            field('b', 'timer'),
            field('c', 'quantum-flux-input'),
          ]),
        ) as Map<String, dynamic>,
      );

      final split = config.unsupportedTypesSplit;
      expect(split.known, <String>['image', 'timer']);
      expect(split.unrecognised, <String>['quantum-flux-input']);
    });

    test('every known type carries a reason', () {
      for (final entry in ScoutConfig.knownUnsupportedTypes.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      }
    });

    test('reasonUnsupported tolerates the spelling the file used', () {
      expect(ScoutConfig.reasonUnsupported('image'), isNotNull);
      expect(ScoutConfig.reasonUnsupported('timer'), isNotNull);
      expect(ScoutConfig.reasonUnsupported('multi-select'), isNull);
      expect(ScoutConfig.reasonUnsupported('multi_select'), isNull);
      expect(ScoutConfig.reasonUnsupported('checkbox-select'), isNull);
      expect(ScoutConfig.reasonUnsupported('action-tracker'), isNull);
      expect(ScoutConfig.reasonUnsupported('TBA-match-number'), isNull);
      expect(ScoutConfig.reasonUnsupported('tba_team_and_robot'), isNull);
      expect(ScoutConfig.reasonUnsupported('text'), isNull);
    });

    test('an implemented type is in neither list', () {
      final config = ScoutConfig.fromJson(
        jsonDecode(configJson([field('a', 'action-tracker')]))
            as Map<String, dynamic>,
      );

      final split = config.unsupportedTypesSplit;
      expect(split.known, isEmpty);
      expect(split.unrecognised, isEmpty);
    });
  });
}
