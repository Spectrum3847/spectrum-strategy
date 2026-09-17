import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';

void main() {
  test('ScoutFieldType.fromString recognizes long-text', () {
    expect(ScoutFieldType.fromString('long-text'), ScoutFieldType.longText);
    expect(ScoutFieldType.fromString('long_text'), ScoutFieldType.longText);
  });

  test('a long-text field round-trips its type through toJson/fromJson', () {
    const field = ScoutConfigField(
      title: 'Notes',
      type: ScoutFieldType.longText,
      code: 'notes',
    );
    final decoded = ScoutConfigField.fromJson(field.toJson());
    expect(decoded.type, ScoutFieldType.longText);
    expect(field.toJson()['type'], 'long-text');
  });

  test('a long-text field defaults to an empty string like text does', () {
    const field = ScoutConfigField(
      title: 'Notes',
      type: ScoutFieldType.longText,
      code: 'notes',
    );
    expect(field.effectiveDefault, '');
  });

  test('ScoutFieldType.fromString recognizes document', () {
    expect(ScoutFieldType.fromString('document'), ScoutFieldType.document);
    expect(ScoutFieldType.fromString('file'), ScoutFieldType.document);
  });

  test('a document field round-trips its type through toJson/fromJson', () {
    const field = ScoutConfigField(
      title: 'Field map',
      type: ScoutFieldType.document,
      code: 'fieldMap',
    );
    final decoded = ScoutConfigField.fromJson(field.toJson());
    expect(decoded.type, ScoutFieldType.document);
    expect(field.toJson()['type'], 'document');
  });

  test('a document field defaults to an empty string, meaning unattached', () {
    const field = ScoutConfigField(
      title: 'Field map',
      type: ScoutFieldType.document,
      code: 'fieldMap',
    );
    expect(field.effectiveDefault, '');
  });

  test('a document field stores the Worker key as an ordinary field value', () {
    const field = ScoutConfigField(
      title: 'Field map',
      type: ScoutFieldType.document,
      code: 'fieldMap',
    );
    final config = ScoutConfig(
      title: 'Pit',
      sections: [
        ScoutConfigSection(name: 'General', fields: [field]),
      ],
    );
    final decoded = ScoutConfig.fromJson(config.toJson());
    final key = 'a1b2c3d4-e5f6-7890-abcd-ef0123456789.pdf';
    final values = <String, dynamic>{'fieldMap': key};
    expect(decoded.allFields.single.serializeValue(values['fieldMap']), key);
  });

  test('a field with no visibleWhenCode is always visible', () {
    const field = ScoutConfigField(
      title: 'Notes',
      type: ScoutFieldType.text,
      code: 'notes',
    );
    expect(field.isVisible(const {}), isTrue);
  });

  test(
    'a field with a visibleWhenCode hides unless the other field matches',
    () {
      const field = ScoutConfigField(
        title: 'Drive train (other)',
        type: ScoutFieldType.text,
        code: 'drivetrainOther',
        visibleWhenCode: 'drivetrainType',
        visibleWhenValue: 'other',
      );
      expect(field.isVisible(const {'drivetrainType': 'tank'}), isFalse);
      expect(field.isVisible(const {}), isFalse);
      expect(field.isVisible(const {'drivetrainType': 'other'}), isTrue);
    },
  );

  test('visibleWhenCode and referenceImageAsset round-trip through toJson/fromJson', () {
    const field = ScoutConfigField(
      title: 'Drive train (other)',
      type: ScoutFieldType.text,
      code: 'drivetrainOther',
      visibleWhenCode: 'drivetrainType',
      visibleWhenValue: 'other',
      referenceImageAsset: 'assets/fields/wpilib/2026-rebuilt.png',
    );
    final decoded = ScoutConfigField.fromJson(field.toJson());
    expect(decoded.visibleWhenCode, 'drivetrainType');
    expect(decoded.visibleWhenValue, 'other');
    expect(
      decoded.referenceImageAsset,
      'assets/fields/wpilib/2026-rebuilt.png',
    );
  });

  test('visibleWhenValue round-trips even with an empty visibleWhenCode', () {
    const field = ScoutConfigField(
      title: 'Notes',
      type: ScoutFieldType.text,
      code: 'notes',
      visibleWhenValue: 'other',
    );
    final decoded = ScoutConfigField.fromJson(field.toJson());
    expect(decoded.visibleWhenCode, '');
    expect(decoded.visibleWhenValue, 'other');
  });

  test(
    'visibleWhenCode and referenceImageAsset are absent from toJson when unset',
    () {
      const field = ScoutConfigField(
        title: 'Notes',
        type: ScoutFieldType.text,
        code: 'notes',
      );
      final json = field.toJson();
      expect(json.containsKey('visibleWhenCode'), isFalse);
      expect(json.containsKey('visibleWhenValue'), isFalse);
      expect(json.containsKey('referenceImageAsset'), isFalse);
    },
  );

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

  group('storedCounterValue', () {
    test('reads the int a counter writes', () {
      expect(storedCounterValue(47), 47);
      expect(storedCounterValue(0), 0);
    });

    test('parses the string a `number` field left behind (#1699)', () {
      expect(storedCounterValue('47'), 47);
      expect(storedCounterValue(' 47 '), 47);
    });

    test('rounds a double, which is what the web SDK hands back', () {
      expect(storedCounterValue(47.0), 47);
      expect(storedCounterValue(46.6), 47);
    });

    test('is null for nothing readable as a count, so a caller can tell a '
        'fallback from a real zero', () {
      expect(storedCounterValue(null), isNull);
      expect(storedCounterValue(''), isNull);
      expect(storedCounterValue('many'), isNull);
      expect(storedCounterValue(true), isNull);
      expect(storedCounterValue(<int>[1, 2]), isNull);
    });

    test('is null for a value that cannot be rounded, which would throw', () {
      expect(storedCounterValue('NaN'), isNull);
      expect(storedCounterValue('Infinity'), isNull);
      expect(storedCounterValue('-Infinity'), isNull);
      expect(storedCounterValue(double.nan), isNull);
      expect(storedCounterValue(double.infinity), isNull);
    });
  });
}
