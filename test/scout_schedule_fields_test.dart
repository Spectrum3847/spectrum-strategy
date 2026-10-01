import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_schedule.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_form_fields.dart';

void main() {
  StatboticsMatch qual(int number, List<int> red, List<int> blue) =>
      StatboticsMatch(
        key: '2026test_qm$number',
        event: '2026test',
        matchNumber: number,
        compLevel: 'qm',
        redTeams: red,
        blueTeams: blue,
      );

  final schedule = ScoutSchedule.fromMatches(<StatboticsMatch>[
    qual(1, [254, 118, 2056], [971, 1323, 33]),
    qual(2, [3847, 118, 1323], [971, 2056, 33]),
    StatboticsMatch(
      key: '2026test_sf1m1',
      event: '2026test',
      matchNumber: 1,
      compLevel: 'sf',
      redTeams: [1, 2, 3],
      blueTeams: [4, 5, 6],
    ),
  ]);

  String configJson(String type, String code) => jsonEncode(<String, dynamic>{
    'title': 'Scout',
    'delimiter': '\t',
    'sections': <dynamic>[
      <String, dynamic>{
        'name': 'Prematch',
        'fields': <dynamic>[
          <String, dynamic>{
            'title': code,
            'type': type,
            'code': code,
            'required': false,
            'formResetBehavior': 'reset',
          },
        ],
      },
    ],
  });

  ScoutConfig config(String type, String code) => ScoutConfig.fromJson(
    jsonDecode(configJson(type, code)) as Map<String, dynamic>,
  );

  group('ScoutSchedule', () {
    test('covers the qualification matches only', () {
      expect(schedule.matchNumbers, <int>[1, 2]);
    });

    test('positions run R1..R3 then B1..B3 in schedule order', () {
      final robots = schedule.robotsFor(1);

      expect(robots.map((r) => r.position), <String>[
        'R1',
        'R2',
        'R3',
        'B1',
        'B2',
        'B3',
      ]);
      expect(robots.first.team, 254);
      expect(robots.first.label, 'Team 254 (Red 1)');
      expect(robots.last.team, 33);
    });

    test('a station resolves in either spelling', () {
      expect(schedule.robotForStation(1, 'B2')?.team, 1323);
      expect(schedule.robotForStation(1, 'Blue 2')?.team, 1323);
      expect(schedule.robotForStation(2, 'Red 1')?.team, 3847);

      expect(schedule.robotForStation(2, 'B2')?.team, 2056);
    });

    test('an unknown station or match resolves to nothing', () {
      expect(schedule.robotForStation(1, ''), isNull);
      expect(schedule.robotForStation(1, 'Red'), isNull);

      expect(schedule.robotForStation(1, 'Blue 12'), isNull);
      expect(schedule.robotForStation(1, 'R4'), isNull);
      expect(schedule.robotForStation(1, 'Robot 1'), isNull);
      expect(schedule.robotForStation(99, 'R1'), isNull);
      expect(schedule.robotForStation(null, 'R1'), isNull);
    });

    test('an empty schedule is empty rather than throwing', () {
      const empty = ScoutSchedule.empty();

      expect(empty.isEmpty, isTrue);
      expect(empty.matchNumbers, isEmpty);
      expect(empty.robotsFor(1), isEmpty);
    });
  });

  group('TBA-match-number', () {
    test('behaves like a number on the wire', () {
      final c = config('TBA-match-number', 'matchNumber');

      expect(c.encodeValues(<String, dynamic>{'matchNumber': 12}), '12');
      expect(c.decodeValues('12')['matchNumber'], 12);
    });

    test('defaults to zero, not null', () {
      expect(
        config('TBA-match-number', 'm').allFields.single.effectiveDefault,
        0,
      );
    });
  });

  group('TBA-team-and-robot', () {
    final c = config('TBA-team-and-robot', 'robotTeam');

    test('serialises to the team number alone', () {
      final encoded = c.encodeValues(<String, dynamic>{
        'robotTeam': <String, dynamic>{
          'teamNumber': 254,
          'robotPosition': 'R1',
        },
      });

      expect(encoded, '254');
    });

    test('decodes back into the map shape with no station', () {
      final decoded = c.decodeValues('254')['robotTeam'];

      expect(decoded, <String, dynamic>{
        'teamNumber': 254,
        'robotPosition': '',
      });
    });

    test('an empty cell decodes to nothing rather than team zero', () {
      expect(c.decodeValues('')['robotTeam'], isNull);
    });

    test('defaults to nothing selected', () {
      expect(c.allFields.single.effectiveDefault, isNull);
    });
  });

  group('the form renders them against the schedule', () {
    Future<Map<String, dynamic>> pumpField(
      WidgetTester tester, {
      required ScoutConfig config,
      required ScoutSchedule schedule,
      Map<String, dynamic> values = const <String, dynamic>{},
    }) async {
      final live = <String, dynamic>{...values};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoutFormSection(
              section: config.sections.single,
              keyPrefix: 'scout-field',
              values: live,
              textControllers: <String, TextEditingController>{},
              onFieldChanged: (code, value) => live[code] = value,
              schedule: schedule,
            ),
          ),
        ),
      );
      return live;
    }

    testWidgets('a match number is a picker when the schedule is loaded', (
      tester,
    ) async {
      final live = await pumpField(
        tester,
        config: config('TBA-match-number', 'matchNumber'),
        schedule: schedule,
      );

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Match 2').last);
      await tester.pumpAndSettle();

      expect(live['matchNumber'], 2);
    });

    testWidgets('and a typed box when it is not', (tester) async {
      await pumpField(
        tester,
        config: config('TBA-match-number', 'matchNumber'),
        schedule: const ScoutSchedule.empty(),
      );

      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a robot picker offers the six teams in the chosen match', (
      tester,
    ) async {
      final live = await pumpField(
        tester,
        config: config('TBA-team-and-robot', 'robotTeam'),
        schedule: schedule,
        values: <String, dynamic>{'matchNumber': 2},
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Team 3847 (Red 1)'), findsWidgets);
      await tester.tap(find.text('Team 971 (Blue 1)').last);
      await tester.pumpAndSettle();

      expect(live['robotTeam'], <String, dynamic>{
        'teamNumber': 971,
        'robotPosition': 'B1',
      });
    });

    testWidgets('with no match chosen it falls back to typing a team', (
      tester,
    ) async {
      final live = await pumpField(
        tester,
        config: config('TBA-team-and-robot', 'robotTeam'),
        schedule: schedule,
      );

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.enterText(find.byType(TextFormField), '4499');

      expect(live['robotTeam'], <String, dynamic>{
        'teamNumber': 4499,
        'robotPosition': '',
      });
    });
  });
}
