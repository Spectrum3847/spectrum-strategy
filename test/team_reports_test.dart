import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_analysis.dart';

ScoutConfigField textField(String code, String title) =>
    ScoutConfigField(title: title, type: ScoutFieldType.text, code: code);

ScoutConfig configWith(List<ScoutConfigSection> sections) => ScoutConfig(
  title: 'T-Rex',
  pageTitle: '',
  delimiter: '\t',
  sections: sections,
);

ScoutEntry entry({
  required int team,
  required String matchId,
  required Map<String, dynamic> values,
  String author = 'Sam',
  DateTime? at,
  Map<String, dynamic>? strokes,
}) => ScoutEntry(
  matchId: matchId,
  teamNumber: team,
  fieldValues: values,
  authorDisplayName: author,
  updatedAt: at ?? DateTime.utc(2026, 8, 4),
  strokesByPhase: strokes,
);

void main() {
  final config = configWith(<ScoutConfigSection>[
    ScoutConfigSection(
      name: 'Autonomous',
      fields: <ScoutConfigField>[textField('autoNote', 'What it did in auto')],
    ),
    ScoutConfigSection(
      name: 'Driver skill',
      fields: <ScoutConfigField>[textField('driverNote', 'Driving')],
    ),
  ]);

  test('groups reports by config section, in config order', () {
    final groups = ScoutingAnalysis.reportsForTeam(254, [
      entry(
        team: 254,
        matchId: 'q1',
        values: <String, dynamic>{
          'autoNote': 'Three piece auto',
          'driverNote': 'Very smooth',
        },
      ),
    ], config);

    expect(groups.map((g) => g.groupName), <String>[
      'Autonomous',
      'Driver skill',
    ]);
    expect(groups.first.reports.single.text, 'Three piece auto');
    expect(groups.first.reports.single.fieldTitle, 'What it did in auto');
  });

  test('a different season\'s groups need no code change', () {
    final groups = ScoutingAnalysis.reportsForTeam(
      254,
      [
        entry(
          team: 254,
          matchId: 'q1',
          values: <String, dynamic>{'fuel': 'Scored from the outpost'},
        ),
      ],
      configWith(<ScoutConfigSection>[
        ScoutConfigSection(
          name: 'Fuel scoring',
          fields: <ScoutConfigField>[textField('fuel', 'Fuel')],
        ),
      ]),
    );

    expect(groups.single.groupName, 'Fuel scoring');
    expect(groups.single.reports.single.text, 'Scored from the outpost');
  });

  test('several scouters land in the same group, newest first', () {
    final groups = ScoutingAnalysis.reportsForTeam(254, [
      entry(
        team: 254,
        matchId: 'q1',
        author: 'Older',
        at: DateTime.utc(2026, 8, 1),
        values: <String, dynamic>{'autoNote': 'First look'},
      ),
      entry(
        team: 254,
        matchId: 'q7',
        author: 'Newer',
        at: DateTime.utc(2026, 8, 3),
        values: <String, dynamic>{'autoNote': 'Second look'},
      ),
    ], config);

    expect(groups.single.groupName, 'Autonomous');
    expect(groups.single.reports.map((r) => r.author), <String>[
      'Newer',
      'Older',
    ]);
  });

  test('an empty group is dropped, not rendered blank', () {
    final groups = ScoutingAnalysis.reportsForTeam(254, [
      entry(
        team: 254,
        matchId: 'q1',
        values: <String, dynamic>{'autoNote': 'Only auto', 'driverNote': '  '},
      ),
    ], config);

    expect(groups.map((g) => g.groupName), <String>['Autonomous']);
  });

  test('only free text contributes', () {
    final groups = ScoutingAnalysis.reportsForTeam(
      254,
      [
        entry(
          team: 254,
          matchId: 'q1',
          values: <String, dynamic>{'count': 12, 'climb': 'Successful'},
        ),
      ],
      configWith(<ScoutConfigSection>[
        ScoutConfigSection(
          name: 'Endgame',
          fields: <ScoutConfigField>[
            ScoutConfigField(
              title: 'Count',
              type: ScoutFieldType.counter,
              code: 'count',
            ),
            ScoutConfigField(
              title: 'Climb',
              type: ScoutFieldType.select,
              code: 'climb',
            ),
          ],
        ),
      ]),
    );

    expect(groups, isEmpty);
  });

  test('other teams and missing values are ignored', () {
    final groups = ScoutingAnalysis.reportsForTeam(254, [
      entry(
        team: 118,
        matchId: 'q1',
        values: <String, dynamic>{'autoNote': 'Not 254'},
      ),
      entry(team: 254, matchId: 'q2', values: <String, dynamic>{}),
    ], config);

    expect(groups, isEmpty);
  });

  test('a team with no entries at all returns nothing', () {
    expect(
      ScoutingAnalysis.reportsForTeam(9999, <ScoutEntry>[], config),
      isEmpty,
    );
  });

  test('a field with no title falls back to its code', () {
    final groups = ScoutingAnalysis.reportsForTeam(
      254,
      [
        entry(
          team: 254,
          matchId: 'q1',
          values: <String, dynamic>{'raw': 'Something'},
        ),
      ],
      configWith(<ScoutConfigSection>[
        ScoutConfigSection(
          name: 'Misc',
          fields: <ScoutConfigField>[
            ScoutConfigField(title: '', type: ScoutFieldType.text, code: 'raw'),
          ],
        ),
      ]),
    );

    expect(groups.single.reports.single.fieldTitle, 'raw');
  });

  test('a whitespace-only title also falls back to the code', () {
    final groups = ScoutingAnalysis.reportsForTeam(
      254,
      [
        entry(
          team: 254,
          matchId: 'q1',
          values: <String, dynamic>{'raw': 'Something'},
        ),
      ],
      configWith(<ScoutConfigSection>[
        ScoutConfigSection(
          name: 'Misc',
          fields: <ScoutConfigField>[
            ScoutConfigField(
              title: '   ',
              type: ScoutFieldType.text,
              code: 'raw',
            ),
          ],
        ),
      ]),
    );

    expect(groups.single.reports.single.fieldTitle, 'raw');
  });

  test('a padded title is trimmed rather than rendered with the padding', () {
    final groups = ScoutingAnalysis.reportsForTeam(
      254,
      [
        entry(
          team: 254,
          matchId: 'q1',
          values: <String, dynamic>{'raw': 'Something'},
        ),
      ],
      configWith(<ScoutConfigSection>[
        ScoutConfigSection(
          name: 'Misc',
          fields: <ScoutConfigField>[
            ScoutConfigField(
              title: '  Driving  ',
              type: ScoutFieldType.text,
              code: 'raw',
            ),
          ],
        ),
      ]),
    );

    expect(groups.single.reports.single.fieldTitle, 'Driving');
  });

  group('drawings', () {
    test('a report carries its entry drawing and its entry id', () {
      final groups = ScoutingAnalysis.reportsForTeam(254, [
        entry(
          team: 254,
          matchId: 'q1',
          values: <String, dynamic>{
            'autoNote': 'Three piece',
            'driverNote': 'Smooth',
          },
          strokes: <String, dynamic>{
            'auton': <Map<String, dynamic>>[
              <String, dynamic>{'points': []},
            ],
          },
        ),
      ], config);

      final auto = groups.first.reports.single;
      final driver = groups.last.reports.single;
      expect(auto.hasDrawing, isTrue);
      expect(auto.strokesByPhase!['auton'], isNotNull);

      expect(auto.entryId, driver.entryId);
    });

    test('no drawing means hasDrawing is false, not an empty map', () {
      final groups = ScoutingAnalysis.reportsForTeam(254, [
        entry(
          team: 254,
          matchId: 'q1',
          values: <String, dynamic>{'autoNote': 'No drawing'},
        ),
      ], config);

      expect(groups.single.reports.single.hasDrawing, isFalse);
    });

    test('an empty strokes map does not count as a drawing', () {
      final groups = ScoutingAnalysis.reportsForTeam(254, [
        entry(
          team: 254,
          matchId: 'q1',
          values: <String, dynamic>{'autoNote': 'Cleared it'},
          strokes: <String, dynamic>{},
        ),
      ], config);

      expect(groups.single.reports.single.hasDrawing, isFalse);
    });

    test('two entries each keep their own id', () {
      final groups = ScoutingAnalysis.reportsForTeam(254, [
        entry(
          team: 254,
          matchId: 'q1',
          values: <String, dynamic>{'autoNote': 'First'},
          strokes: <String, dynamic>{
            'auton': <dynamic>[1],
          },
        ),
        entry(
          team: 254,
          matchId: 'q2',
          values: <String, dynamic>{'autoNote': 'Second'},
          strokes: <String, dynamic>{
            'auton': <dynamic>[1],
          },
        ),
      ], config);

      final ids = groups.single.reports.map((r) => r.entryId).toSet();
      expect(ids, hasLength(2));
    });
  });
}
