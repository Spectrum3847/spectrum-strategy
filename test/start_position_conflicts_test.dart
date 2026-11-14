import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/start_position_conflicts.dart';

ScoutEntry _entry(int team, Object? start) => ScoutEntry(
  matchId: 'qm1',
  teamNumber: team,
  fieldValues: <String, dynamic>{StartPositionConflicts.startingCode: ?start},
);

List<ScoutEntry> _entries(int team, Map<String, int> counts) => <ScoutEntry>[
  for (final MapEntry(key: spot, value: n) in counts.entries)
    for (var i = 0; i < n; i++) _entry(team, spot),
];

void main() {
  group('usualStarts', () {
    test('needs two entries and a position held by more than half', () {
      final usual = StartPositionConflicts.usualStarts(
        <ScoutEntry>[
          ..._entries(1, <String, int>{'Center': 1}),
          ..._entries(2, <String, int>{'Center': 4, 'Left': 1}),
          ..._entries(3, <String, int>{'Center': 2, 'Left': 2}),
          ..._entries(4, <String, int>{'Center': 2}),
        ],
        <int>[1, 2, 3, 4],
      );

      expect(usual.keys, unorderedEquals(<int>[2, 4]));
      expect(usual[2]!.position, 'Center');
      expect(usual[2]!.count, 4);
      expect(usual[2]!.total, 5);
    });

    test('ignores teams not asked for, blank starts and no shows', () {
      final usual = StartPositionConflicts.usualStarts(
        <ScoutEntry>[
          ..._entries(1, <String, int>{'Center': 2}),
          ..._entries(2, <String, int>{'No Show': 3, 'Left': 2}),
          _entry(2, ''),
          _entry(2, null),
          ..._entries(9, <String, int>{'Center': 3}),
        ],
        <int>[1, 2],
      );

      expect(usual.keys, unorderedEquals(<int>[1, 2]));
      expect(usual[2]!.position, 'Left');
      expect(usual[2]!.total, 2);
    });
  });

  group('conflicts', () {
    Map<int, UsualStart> usual(Map<int, (String, int, int)> by) => {
      for (final e in by.entries)
        e.key: UsualStart(
          team: e.key,
          position: e.value.$1,
          count: e.value.$2,
          total: e.value.$3,
        ),
    };

    test('names two robots sharing a usual start', () {
      final found = StartPositionConflicts.conflicts(
        <int>[3847, 254, 118],
        usual(<int, (String, int, int)>{
          3847: ('Center', 4, 5),
          254: ('Center', 3, 4),
          118: ('Left', 2, 2),
        }),
      );

      expect(found, hasLength(1));
      expect(found.single.position, 'Center');
      expect(
        found.single.message,
        '3847 and 254 both usually start Center (4/5, 3/4)',
      );
    });

    test('three on one spot read as a list', () {
      final found = StartPositionConflicts.conflicts(
        <int>[1, 2, 3],
        usual(<int, (String, int, int)>{
          1: ('Center', 2, 2),
          2: ('Center', 2, 2),
          3: ('Center', 2, 3),
        }),
      );

      expect(
        found.single.message,
        '1, 2 and 3 all usually start Center (2/2, 2/2, 2/3)',
      );
    });

    test('different spots, or robots with no usual start, are fine', () {
      final found = StartPositionConflicts.conflicts(
        <int>[1, 2, 3],
        usual(<int, (String, int, int)>{
          1: ('Center', 2, 2),
          2: ('Left', 2, 2),
        }),
      );

      expect(found, isEmpty);
    });
  });
}
