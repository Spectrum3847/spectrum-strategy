import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/services/scouting_coverage.dart';
import 'package:spectrumstrategy/src/widgets/scouting_coverage_view.dart';

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

  ScoutEntry entry(int team, int matchNumber) => ScoutEntry(
    matchId: 'session-$matchNumber',
    teamNumber: team,
    authorDisplayName: 'Sam',
    fieldValues: <String, dynamic>{'matchNumber': matchNumber},
  );

  final schedule = <StatboticsMatch>[
    qual(1, [254, 118, 2056], [971, 1323, 33]),
    qual(2, [3847, 118, 1323], [971, 2056, 33]),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required ScoutingCoverage coverage,
    bool hasEvent = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ScoutingCoverageView(coverage: coverage, hasEvent: hasEvent),
      ),
    ),
  );

  testWidgets('with no event selected it says to pick one', (tester) async {
    await pump(
      tester,
      coverage: const ScoutingCoverage.empty(),
      hasEvent: false,
    );

    expect(find.textContaining('Pick an event'), findsOneWidget);
  });

  testWidgets('an event with no schedule reads as not published yet', (
    tester,
  ) async {
    await pump(tester, coverage: const ScoutingCoverage.empty());

    expect(find.textContaining('schedule publishes'), findsOneWidget);
    expect(find.textContaining('Pick an event'), findsNothing);
  });

  testWidgets('full coverage is stated, not shown as an empty list', (
    tester,
  ) async {
    final coverage = ScoutingCoverage.build(
      schedule: schedule,
      entries: <ScoutEntry>[
        for (final match in schedule)
          for (final team in [...match.redTeams, ...match.blueTeams])
            entry(team, match.matchNumber),
      ],
    );

    await pump(tester, coverage: coverage);

    expect(find.textContaining('Every qualification slot'), findsOneWidget);
  });

  testWidgets('only the unscouted teams are listed, worst match first', (
    tester,
  ) async {
    final coverage = ScoutingCoverage.build(
      schedule: schedule,
      entries: <ScoutEntry>[
        for (final t in <int>[254, 118, 2056, 971, 1323]) entry(t, 1),
        for (final t in <int>[3847, 118, 1323]) entry(t, 2),
      ],
    );

    await pump(tester, coverage: coverage);

    expect(
      find.text('4 of 12 slots unscouted, across 2 matches.'),
      findsOneWidget,
    );

    expect(find.text('33'), findsNWidgets(2));
    expect(find.text('971'), findsOneWidget);
    expect(find.text('254'), findsNothing);

    final q2 = tester.getTopLeft(find.text('Q2')).dy;
    final q1 = tester.getTopLeft(find.text('Q1')).dy;
    expect(q2, lessThan(q1));
  });
}
