import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';

void main() {
  test('ScoutConfig.fromJson falls back to tab for an empty delimiter', () {
    final config = ScoutConfig.fromJson(<String, dynamic>{
      'delimiter': '',
      'sections': <dynamic>[],
    });
    expect(config.delimiter, '\t');

    expect(config.decodeValues('a\tb'), isA<Map<String, dynamic>>());
  });

  test('ScoutConfig.fromJson rejects an over-long delimiter', () {
    final config = ScoutConfig.fromJson(<String, dynamic>{
      'delimiter': 'not-a-delimiter',
      'sections': <dynamic>[],
    });
    expect(config.delimiter, '\t');
  });

  test('ScoutConfig.fromJson keeps a valid single-character delimiter', () {
    final config = ScoutConfig.fromJson(<String, dynamic>{
      'delimiter': ',',
      'sections': <dynamic>[],
    });
    expect(config.delimiter, ',');
  });

  test('ScoutConfig.fromJson defaults the delimiter to tab when absent', () {
    final config = ScoutConfig.fromJson(<String, dynamic>{
      'sections': <dynamic>[],
    });
    expect(config.delimiter, '\t');
  });

  test('ScoutConfig.fromJson defaults revision to 0 when absent', () {
    final config = ScoutConfig.fromJson(<String, dynamic>{
      'sections': <dynamic>[],
    });
    expect(config.revision, 0);
  });

  test('ScoutConfig round-trips revision through toJson/fromJson', () {
    const config = ScoutConfig(
      title: 'Test',
      sections: <ScoutConfigSection>[],
      revision: 7,
    );
    final decoded = ScoutConfig.fromJson(config.toJson());
    expect(decoded.revision, 7);
  });

  test('ScoutConfig.copyWith keeps revision unless one is given', () {
    const config = ScoutConfig(
      title: 'Test',
      sections: <ScoutConfigSection>[],
      revision: 3,
    );
    expect(config.copyWith(title: 'Renamed').revision, 3);
    expect(config.copyWith(revision: 9).revision, 9);
  });

  test('encodeValues strips the delimiter and newlines from field values', () {
    final config = ScoutConfig.fromJson(<String, dynamic>{
      'sections': <dynamic>[
        <String, dynamic>{
          'name': 'Match',
          'fields': <dynamic>[
            <String, dynamic>{
              'code': 'matchNumber',
              'title': 'Match',
              'type': 'number',
            },
            <String, dynamic>{
              'code': 'notes',
              'title': 'Notes',
              'type': 'text',
            },
            <String, dynamic>{
              'code': 'after',
              'title': 'After',
              'type': 'text',
            },
          ],
        },
      ],
    });

    final payload = config.encodeValues(<String, dynamic>{
      'matchNumber': '12',
      'notes': 'pushed\tbot\nhard',
      'after': 'aligned',
    });
    final decoded = config.decodeValues(payload);

    expect(decoded['matchNumber'], anyOf('12', 12));
    expect(decoded['notes'], 'pushed bot hard');
    expect(decoded['after'], 'aligned');
  });

  test('ScoutConfigField.copyWith replaces choices when given a new map', () {
    const field = ScoutConfigField(
      title: 'Drivetrain Type',
      type: ScoutFieldType.select,
      code: 'drivetrainType',
      choices: {'tank': 'Tank', 'swerve': 'Swerve'},
    );

    final updated = field.copyWith(choices: {'tank': 'Tank Drive'});

    expect(updated.choices, {'tank': 'Tank Drive'});

    expect(updated.title, field.title);
    expect(updated.code, field.code);
  });

  test('ScoutConfigField.copyWith keeps existing choices when none given', () {
    const field = ScoutConfigField(
      title: 'Drivetrain Type',
      type: ScoutFieldType.select,
      code: 'drivetrainType',
      choices: {'tank': 'Tank'},
    );

    final updated = field.copyWith(title: 'Drivetrain Kind');

    expect(updated.choices, field.choices);
  });

  group('retired choices', () {
    const field = ScoutConfigField(
      title: 'Where did it score from',
      type: ScoutFieldType.select,
      code: 'scoreFrom',
      choices: {'1': 'Outpost', '2': 'Depot', '3': 'Hub'},
      retiredChoiceKeys: {'2'},
    );

    test('activeChoices drops the retired key but choices keeps it', () {
      expect(field.activeChoices, {'1': 'Outpost', '3': 'Hub'});
      expect(field.choices, {'1': 'Outpost', '2': 'Depot', '3': 'Hub'});
    });

    test(
      'resolveStoredChoice and labelForStored still resolve a retired key',
      () {
        expect(field.resolveStoredChoice('2'), '2');
        expect(field.labelForStored('2'), 'Depot');
      },
    );

    test('effectiveDefault never picks a retired choice', () {
      expect(field.effectiveDefault, '1');
    });

    test('effectiveDefault falls back to a retired choice when every choice is '
        'retired', () {
      const allRetired = ScoutConfigField(
        title: 'Where did it score from',
        type: ScoutFieldType.select,
        code: 'scoreFrom',
        choices: {'1': 'Outpost'},
        retiredChoiceKeys: {'1'},
      );
      expect(allRetired.effectiveDefault, '1');
    });

    test('choiceOptions offers the active choices plus a kept retired key', () {
      expect(field.choiceOptions(const ['2']), {
        '1': 'Outpost',
        '3': 'Hub',
        '2': 'Depot',
      });
    });

    test(
      'choiceOptions without a retired key to keep is just activeChoices',
      () {
        expect(field.choiceOptions(const []), field.activeChoices);
        expect(field.choiceOptions(const ['1']), field.activeChoices);
      },
    );

    test('copyWith keeps retiredChoiceKeys when none given', () {
      final updated = field.copyWith(title: 'Renamed');
      expect(updated.retiredChoiceKeys, {'2'});
    });

    test('copyWith replaces retiredChoiceKeys when given', () {
      final updated = field.copyWith(retiredChoiceKeys: {'1', '2'});
      expect(updated.retiredChoiceKeys, {'1', '2'});
    });

    test('toJson/fromJson round-trips retiredChoiceKeys', () {
      final json = field.toJson();
      expect(json['retiredChoiceKeys'], ['2']);

      final decoded = ScoutConfigField.fromJson(json);
      expect(decoded.retiredChoiceKeys, {'2'});
      expect(decoded.choices, field.choices);
    });

    test('toJson omits retiredChoiceKeys when nothing is retired', () {
      const noneRetired = ScoutConfigField(
        title: 'Drivetrain Type',
        type: ScoutFieldType.select,
        code: 'drivetrainType',
        choices: {'tank': 'Tank'},
      );
      expect(noneRetired.toJson().containsKey('retiredChoiceKeys'), isFalse);
    });

    test('fromJson defaults retiredChoiceKeys to empty for a plain QRScout '
        'config', () {
      final decoded = ScoutConfigField.fromJson(<String, dynamic>{
        'title': 'Drivetrain Type',
        'type': 'select',
        'code': 'drivetrainType',
        'choices': {'tank': 'Tank'},
      });
      expect(decoded.retiredChoiceKeys, isEmpty);
    });
  });
}
