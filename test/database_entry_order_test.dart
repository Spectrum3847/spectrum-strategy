import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';

ScoutEntry entry(String matchId, int teamNumber, {int arrival = 0}) =>
    ScoutEntry(
      matchId: matchId,
      teamNumber: teamNumber,
      createdAt: DateTime.utc(2026, 8, 5).add(Duration(minutes: arrival)),
    );

void main() {
  test('matchNumberOf extracts the numeric portion of a match id', () {
    expect(matchNumberOf('12'), 12);
    expect(matchNumberOf('Q12'), 12);
    expect(matchNumberOf('qm7'), 7);
    expect(matchNumberOf('practice'), isNull);
    expect(matchNumberOf(''), isNull);
  });

  test('the default order groups a match in arrival order', () {
    final entries = <ScoutEntry>[
      entry('11', 3847, arrival: 3),
      entry('12', 9999, arrival: 5),
      entry('11', 254, arrival: 1),
      entry('12', 118, arrival: 4),
      entry('11', 1678, arrival: 2),
    ]..sort(compareEntriesByMatch);

    expect(
      entries.map((e) => '${e.matchId}:${e.teamNumber}').toList(),
      <String>['11:254', '11:1678', '11:3847', '12:118', '12:9999'],
    );
  });

  test('the default order puts match 1 first', () {
    final entries = <ScoutEntry>[entry('2', 1), entry('10', 1), entry('9', 1)]
      ..sort(compareEntriesByMatch);

    expect(entries.map((e) => e.matchId).toList(), <String>['2', '9', '10']);
  });

  test('newestFirst reverses both the match and the arrival order', () {
    final entries =
        <ScoutEntry>[
          entry('11', 3847, arrival: 3),
          entry('12', 9999, arrival: 5),
          entry('11', 254, arrival: 1),
          entry('12', 118, arrival: 4),
        ]..sort(
          (ScoutEntry a, ScoutEntry b) =>
              compareEntriesByMatch(a, b, EntryOrder.newestFirst),
        );

    expect(
      entries.map((e) => '${e.matchId}:${e.teamNumber}').toList(),
      <String>['12:9999', '12:118', '11:3847', '11:254'],
    );
  });

  test('entries that arrived at the same instant fall back to team number', () {
    final entries = <ScoutEntry>[
      entry('7', 3847),
      entry('7', 118),
      entry('7', 254),
    ]..sort(compareEntriesByMatch);

    expect(entries.map((e) => e.teamNumber).toList(), <int>[118, 254, 3847]);
  });

  test('submitted order ignores the match and follows arrival', () {
    final entries =
        <ScoutEntry>[
          entry('7', 3847, arrival: 30),
          entry('3', 254, arrival: 40),
          entry('7', 118, arrival: 20),
        ]..sort(
          (ScoutEntry a, ScoutEntry b) =>
              compareEntriesByMatch(a, b, EntryOrder.submitted),
        );

    expect(
      entries.map((e) => '${e.matchId}:${e.teamNumber}').toList(),
      <String>['7:118', '7:3847', '3:254'],
    );
  });

  test('the same late entry sorts back into its match in the default', () {
    final entries = <ScoutEntry>[
      entry('7', 3847, arrival: 30),
      entry('3', 254, arrival: 40),
      entry('7', 118, arrival: 20),
    ]..sort(compareEntriesByMatch);

    expect(
      entries.map((e) => '${e.matchId}:${e.teamNumber}').toList(),
      <String>['3:254', '7:118', '7:3847'],
    );
  });

  test('submitted order falls back to team number at the same instant', () {
    final entries =
        <ScoutEntry>[entry('7', 3847), entry('9', 118), entry('2', 254)]..sort(
          (ScoutEntry a, ScoutEntry b) =>
              compareEntriesByMatch(a, b, EntryOrder.submitted),
        );

    expect(entries.map((e) => e.teamNumber).toList(), <int>[118, 254, 3847]);
  });

  test('every order has a label of its own', () {
    final labels = EntryOrder.values.map(entryOrderLabel).toList();

    expect(labels.toSet(), hasLength(EntryOrder.values.length));
    expect(labels, contains('Submitted first'));
  });

  test('a non-numeric match id sorts last', () {
    final entries = <ScoutEntry>[
      entry('practice', 1),
      entry('3', 1),
      entry('finals', 1),
    ]..sort(compareEntriesByMatch);

    expect(entries.map((e) => e.matchId).toList(), <String>[
      '3',
      'finals',
      'practice',
    ]);
  });

  test('distinct ids with equal numbers stay apart', () {
    final entries = <ScoutEntry>[
      entry('Q12', 5, arrival: 2),
      entry('P12', 9, arrival: 3),
      entry('Q12', 1, arrival: 1),
    ]..sort(compareEntriesByMatch);

    expect(
      entries.map((e) => '${e.matchId}:${e.teamNumber}').toList(),
      <String>['Q12:1', 'Q12:5', 'P12:9'],
    );
  });
}
