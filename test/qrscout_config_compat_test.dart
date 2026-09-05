import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';

Map<String, dynamic> _loadUpstreamConfig() {
  final file = File('test/data/qrscout_2026_config.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  late Map<String, dynamic> raw;
  late ScoutConfig config;

  setUpAll(() {
    raw = _loadUpstreamConfig();
    config = ScoutConfig.fromJson(raw);
  });

  test('the whole upstream config parses', () {
    expect(config.sections, hasLength(5));
    expect(config.allFields, hasLength(30));
    expect(config.title, isNotEmpty);
  });

  test('no field type in it is unrecognised', () {
    expect(
      config.unsupportedTypesSplit.unrecognised,
      isEmpty,
      reason:
          'QRScout added a field type this app does not know about. Add it to '
          'ScoutFieldType and render it, or record it in '
          'ScoutConfig.knownUnsupportedTypes with the reason.',
    );
  });

  test('nothing in it degrades to a text box', () {
    expect(
      config.unsupportedFieldTypes,
      isEmpty,
      reason:
          'a field in the upstream config now falls back to free text: '
          '${config.unsupportedFieldTypes}',
    );
  });

  test('every field keeps the type the file asked for', () {
    final sections = raw['sections'] as List<dynamic>;
    var checked = 0;
    for (var s = 0; s < sections.length; s++) {
      final fields =
          (sections[s] as Map<String, dynamic>)['fields'] as List<dynamic>;
      for (var f = 0; f < fields.length; f++) {
        final sourceType =
            (fields[f] as Map<String, dynamic>)['type'] as String;
        final parsed = config.sections[s].fields[f];
        expect(
          parsed.type,
          ScoutFieldType.fromString(sourceType),
          reason: 'field ${parsed.code} asked for $sourceType',
        );
        if (sourceType != 'text') {
          expect(
            parsed.type,
            isNot(ScoutFieldType.text),
            reason: '${parsed.code} silently became a text box',
          );
        }
        checked++;
      }
    }
    expect(checked, 30);
  });

  test('the types present are the ones this app renders', () {
    final present = <String>{
      for (final dynamic section in raw['sections'] as List<dynamic>)
        for (final dynamic field
            in (section as Map<String, dynamic>)['fields'] as List<dynamic>)
          (field as Map<String, dynamic>)['type'] as String,
    };

    expect(present, <String>{
      'select',
      'boolean',
      'checkbox-select',
      'multi-counter',
      'range',
      'text',
      'TBA-match-number',
      'TBA-team-and-robot',
      'action-tracker',
    });
  });

  test('a multi-counter with no buttons key still renders a step', () {
    final multiCounters = config.allFields
        .where((f) => f.type == ScoutFieldType.multiCounter)
        .toList(growable: false);
    expect(multiCounters, isNotEmpty);
    for (final field in multiCounters) {
      expect(field.buttons, anyOf(isNull, isEmpty));
    }
  });

  test('the config survives a round trip through this app', () {
    final again = ScoutConfig.fromJson(
      jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
    );
    expect(
      again.allFields.map((f) => f.code),
      config.allFields.map((f) => f.code),
    );
    expect(
      again.allFields.map((f) => f.type),
      config.allFields.map((f) => f.type),
    );
    expect(again.delimiter, config.delimiter);
    expect(again.unsupportedFieldTypes, config.unsupportedFieldTypes);
  });

  group("the team's own config", () {
    late ScoutConfig teamConfig;

    setUpAll(() {
      teamConfig = ScoutConfig.fromJson(
        jsonDecode(
          File('test/data/spectrum_2026_config.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      );
    });

    test('it parses, and every field type in it renders', () {
      expect(teamConfig.sections, hasLength(5));
      expect(teamConfig.allFields, hasLength(18));
      expect(teamConfig.unsupportedFieldTypes, isEmpty);
    });

    test('it uses neither timer nor image', () {
      final present = <String>{
        for (final field in teamConfig.allFields) field.rawType,
      };
      expect(present, <String>{
        'text',
        'number',
        'select',
        'multi-counter',
        'range',
        'boolean',
      });
    });
  });
}
