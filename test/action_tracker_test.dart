import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/action_tracker.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';

void main() {
  const actions = <TrackedAction>[
    TrackedAction(code: 'fuel', label: 'Fuel'),
    TrackedAction(code: 'miss', label: 'Miss'),
  ];

  group('derived field names', () {
    test('match QRScout exactly', () {
      const log = ActionTrackerLog.empty('auto');
      expect(log.countFieldFor('fuel'), 'auto_fuel_count');
      expect(log.timesFieldFor('fuel'), 'auto_fuel_times');
    });

    test('every action gets both entries even when it never fired', () {
      const log = ActionTrackerLog.empty('auto');

      expect(log.toFieldValues(actions), <String, dynamic>{
        'auto_fuel_count': 0,
        'auto_fuel_times': '',
        'auto_miss_count': 0,
        'auto_miss_times': '',
      });
    });
  });

  group('tap mode', () {
    test('records counts and comma-joined times', () {
      var log = const ActionTrackerLog.empty('auto');
      log = log.add(const ActionTrackerEvent(actionCode: 'fuel', at: 3.4));
      log = log.add(const ActionTrackerEvent(actionCode: 'miss', at: 8.0));
      log = log.add(const ActionTrackerEvent(actionCode: 'fuel', at: 12.15));

      final values = log.toFieldValues(actions);
      expect(values['auto_fuel_count'], 2);

      expect(values['auto_fuel_times'], '3.4,12.2');
      expect(values['auto_miss_count'], 1);

      expect(values['auto_miss_times'], '8');
    });
  });

  group('hold mode', () {
    test('records start-end spans', () {
      var log = const ActionTrackerLog.empty('teleop');
      log = log.add(
        const ActionTrackerEvent(actionCode: 'fuel', at: 3.4, until: 5.0),
      );
      log = log.add(
        const ActionTrackerEvent(actionCode: 'fuel', at: 12.1, until: 13.4),
      );

      expect(
        log.toFieldValues(actions)['teleop_fuel_times'],
        '3.4-5,12.1-13.4',
      );
    });
  });

  group('formatSeconds', () {
    test('drops a trailing .0 and rounds to one place', () {
      expect(ActionTrackerLog.formatSeconds(3), '3');
      expect(ActionTrackerLog.formatSeconds(3.0), '3');
      expect(ActionTrackerLog.formatSeconds(3.4), '3.4');
      expect(ActionTrackerLog.formatSeconds(3.44), '3.4');
      expect(ActionTrackerLog.formatSeconds(3.46), '3.5');
      expect(ActionTrackerLog.formatSeconds(0), '0');
      expect(ActionTrackerLog.formatSeconds(60.4), '60.4');
      expect(ActionTrackerLog.formatSeconds(125.04), '125');
    });

    test('an exact half is left to the platform, deliberately untested', () {
      final formatted = ActionTrackerLog.formatSeconds(13.25);
      expect(formatted, anyOf('13.2', '13.3'));
    });
  });

  group('undo and clear', () {
    test('undo drops only the most recent event', () {
      var log = const ActionTrackerLog.empty('auto');
      log = log.add(const ActionTrackerEvent(actionCode: 'fuel', at: 1));
      log = log.add(const ActionTrackerEvent(actionCode: 'miss', at: 2));

      log = log.undo();

      expect(log.events.single.actionCode, 'fuel');
    });

    test('undo on an empty log is a no-op, not an error', () {
      const log = ActionTrackerLog.empty('auto');
      expect(log.undo().isEmpty, isTrue);
    });

    test('clear empties everything', () {
      var log = const ActionTrackerLog.empty('auto');
      log = log.add(const ActionTrackerEvent(actionCode: 'fuel', at: 1));
      expect(log.clear().isEmpty, isTrue);
    });
  });

  group('config parsing', () {
    Map<String, dynamic> trackerJson(Map<String, dynamic> extra) =>
        <String, dynamic>{
          'title': 'Auto actions',
          'type': 'action-tracker',
          'code': 'auto',
          'formResetBehavior': 'reset',
          ...extra,
        };

    test('reads actions, mode and durations', () {
      final field = ScoutConfigField.fromJson(
        trackerJson(<String, dynamic>{
          'mode': 'tap',
          'timerDuration': 15,
          'autoStopSeconds': 20,
          'actions': <Map<String, dynamic>>[
            <String, dynamic>{'code': 'fuel', 'label': 'Fuel', 'icon': 'fuel'},
            <String, dynamic>{'code': 'miss', 'label': 'Miss'},
          ],
        }),
      );

      expect(field.type, ScoutFieldType.actionTracker);
      expect(field.trackerMode, ActionTrackerMode.tap);
      expect(field.timerDuration, 15);
      expect(field.autoStopSeconds, 20);
      expect(field.actions.map((a) => a.code), <String>['fuel', 'miss']);
      expect(field.actions.first.icon, 'fuel');

      expect(field.typeIsUnsupported, isFalse);
    });

    test('mode defaults to hold, as QRScout does', () {
      final field = ScoutConfigField.fromJson(
        trackerJson(<String, dynamic>{
          'actions': <Map<String, dynamic>>[
            <String, dynamic>{'code': 'fuel', 'label': 'Fuel'},
          ],
        }),
      );

      expect(field.trackerMode, ActionTrackerMode.hold);
    });

    test('an action with no label falls back to its code', () {
      final field = ScoutConfigField.fromJson(
        trackerJson(<String, dynamic>{
          'actions': <Map<String, dynamic>>[
            <String, dynamic>{'code': 'fuel'},
          ],
        }),
      );

      expect(field.actions.single.label, 'fuel');
    });

    test('the field itself defaults to no value', () {
      final field = ScoutConfigField.fromJson(
        trackerJson(<String, dynamic>{
          'actions': <Map<String, dynamic>>[
            <String, dynamic>{'code': 'fuel', 'label': 'Fuel'},
          ],
        }),
      );

      expect(field.effectiveDefault, isNull);
    });

    test('a round trip keeps the actions and the mode', () {
      final field = ScoutConfigField.fromJson(
        trackerJson(<String, dynamic>{
          'mode': 'tap',
          'actions': <Map<String, dynamic>>[
            <String, dynamic>{'code': 'fuel', 'label': 'Fuel', 'icon': 'fuel'},
          ],
        }),
      );

      final reloaded = ScoutConfigField.fromJson(
        jsonDecode(jsonEncode(field.toJson())) as Map<String, dynamic>,
      );

      expect(reloaded.type, ScoutFieldType.actionTracker);
      expect(reloaded.trackerMode, ActionTrackerMode.tap);
      expect(reloaded.actions.single.code, 'fuel');
      expect(reloaded.actions.single.icon, 'fuel');
    });
  });

  group('tab-delimited payload columns', () {
    ScoutConfig trackerConfig() => ScoutConfig.fromJson(
      jsonDecode(
        jsonEncode(<String, dynamic>{
          'title': 'T',
          'page_title': '',
          'delimiter': '\t',
          'sections': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'Auto',
              'fields': <Map<String, dynamic>>[
                <String, dynamic>{
                  'title': 'Scouter',
                  'type': 'text',
                  'code': 'scouter',
                  'formResetBehavior': 'preserve',
                },
                <String, dynamic>{
                  'title': 'Actions',
                  'type': 'action-tracker',
                  'code': 'auto',
                  'formResetBehavior': 'reset',
                  'mode': 'tap',
                  'actions': <Map<String, dynamic>>[
                    <String, dynamic>{'code': 'fuel', 'label': 'Fuel'},
                    <String, dynamic>{'code': 'miss', 'label': 'Miss'},
                  ],
                },
                <String, dynamic>{
                  'title': 'Notes',
                  'type': 'text',
                  'code': 'notes',
                  'formResetBehavior': 'reset',
                },
              ],
            },
          ],
        }),
      ) as Map<String, dynamic>,
    );

    test('a tracker expands to two columns per action and none of its own', () {
      final codes = trackerConfig().payloadColumns.map((c) => c.code).toList();

      expect(codes, <String>[
        'scouter',
        'auto_fuel_count',
        'auto_fuel_times',
        'auto_miss_count',
        'auto_miss_times',
        'notes',
      ]);

      expect(codes, isNot(contains('auto')));
    });

    test('encodeValues writes the derived values, not an empty column', () {
      final config = trackerConfig();
      final encoded = config.encodeValues(<String, dynamic>{
        'scouter': 'Sam',
        'auto_fuel_count': 2,
        'auto_fuel_times': '3.4,12.1',
        'auto_miss_count': 0,
        'auto_miss_times': '',
        'notes': 'Good',
      });

      expect(encoded.split('\t'), <String>[
        'Sam',
        '2',
        '3.4,12.1',
        '0',
        '',
        'Good',
      ]);
    });

    test('a count with no value encodes as 0, matching QRScout', () {
      final encoded = trackerConfig().encodeValues(<String, dynamic>{
        'scouter': 'Sam',
      });

      expect(encoded.split('\t'), <String>['Sam', '0', '', '0', '', '']);
    });

    test('decodeValues round-trips the derived columns', () {
      final config = trackerConfig();
      final decoded = config.decodeValues('Sam\t2\t3.4,12.1\t0\t\tGood');

      expect(decoded['auto_fuel_count'], 2);
      expect(decoded['auto_fuel_times'], '3.4,12.1');
      expect(decoded['auto_miss_count'], 0);
      expect(decoded['notes'], 'Good');

      expect(decoded.containsKey('auto'), isFalse);
    });

    test('a full round trip preserves every column', () {
      final config = trackerConfig();
      final values = <String, dynamic>{
        'scouter': 'Sam',
        'auto_fuel_count': 3,
        'auto_fuel_times': '1,2.5,9',
        'auto_miss_count': 1,
        'auto_miss_times': '4.2',
        'notes': 'Fine',
      };

      final decoded = config.decodeValues(config.encodeValues(values));

      expect(decoded['auto_fuel_times'], '1,2.5,9');
      expect(decoded['auto_miss_count'], 1);
      expect(decoded['scouter'], 'Sam');
    });
  });

  group('delimiter validation', () {
    ScoutConfig withDelimiter(String delimiter, String mode) =>
        ScoutConfig.fromJson(
          jsonDecode(
            jsonEncode(<String, dynamic>{
              'title': 'T',
              'page_title': '',
              'delimiter': delimiter,
              'sections': <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': 'Auto',
                  'fields': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'title': 'Actions',
                      'type': 'action-tracker',
                      'code': 'auto',
                      'formResetBehavior': 'reset',
                      'mode': mode,
                      'actions': <Map<String, dynamic>>[
                        <String, dynamic>{'code': 'fuel', 'label': 'Fuel'},
                      ],
                    },
                  ],
                },
              ],
            }),
          ) as Map<String, dynamic>,
        );

    test('a comma delimiter with a tracker is refused', () {
      expect(withDelimiter(',', 'tap').validationError, isNotNull);
    });

    test('a dash delimiter is refused only for hold mode', () {
      expect(withDelimiter('-', 'hold').validationError, isNotNull);
      expect(withDelimiter('-', 'tap').validationError, isNull);
    });

    test('a tab delimiter is fine either way', () {
      expect(withDelimiter('\t', 'hold').validationError, isNull);
      expect(withDelimiter('\t', 'tap').validationError, isNull);
    });

    test('a config with no tracker is never refused', () {
      final config = ScoutConfig.fromJson(
        jsonDecode(
          jsonEncode(<String, dynamic>{
            'title': 'T',
            'page_title': '',
            'delimiter': ',',
            'sections': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'Auto',
                'fields': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'title': 'Notes',
                    'type': 'text',
                    'code': 'n',
                    'formResetBehavior': 'reset',
                  },
                ],
              },
            ],
          }),
        ) as Map<String, dynamic>,
      );

      expect(config.validationError, isNull);
    });
  });

  test('a payload missing trailing cells still fills tracker defaults', () {
    final config = ScoutConfig.fromJson(
      jsonDecode(
        jsonEncode(<String, dynamic>{
          'title': 'T',
          'page_title': '',
          'delimiter': '\t',
          'sections': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'Auto',
              'fields': <Map<String, dynamic>>[
                <String, dynamic>{
                  'title': 'Scouter',
                  'type': 'text',
                  'code': 'scouter',
                  'formResetBehavior': 'preserve',
                },
                <String, dynamic>{
                  'title': 'Actions',
                  'type': 'action-tracker',
                  'code': 'auto',
                  'formResetBehavior': 'reset',
                  'mode': 'tap',
                  'actions': <Map<String, dynamic>>[
                    <String, dynamic>{'code': 'fuel', 'label': 'Fuel'},
                  ],
                },
              ],
            },
          ],
        }),
      ) as Map<String, dynamic>,
    );

    final decoded = config.decodeValues('Sam');

    expect(decoded['auto_fuel_count'], 0);
    expect(decoded['auto_fuel_times'], '');
  });
}
