import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/models/match_preview.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/team_analysis.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_analysis.dart';
import 'package:spectrumstrategy/src/ui/match_preview_screen.dart';

StatboticsMatch _match() => StatboticsMatch(
  key: '2026txdri1_qm34',
  event: '2026txdri1',
  matchNumber: 34,
  compLevel: 'qm',
  redTeams: const <int>[3847, 254, 1323],
  blueTeams: const <int>[118, 971, 2056],
);

StatboticsTeamEvent _teamEvent(int team, double total) => StatboticsTeamEvent(
  team: team,
  event: '2026txdri1',
  eventName: 'Test Event',
  year: 2026,
  wins: 0,
  losses: 0,
  ties: 0,
  epa: StatboticsEpa(
    totalPoints: total,
    autoPoints: total / 4,
    teleopPoints: total / 2,
  ),
);

MatchPreview _preview({bool withEpa = true, bool withScouting = true}) {
  return MatchPreview.fromMatch(
    _match(),
    nicknames: const <int, String>{3847: 'Spectrum', 118: 'Robonauts'},
    teamEvents: withEpa
        ? <int, StatboticsTeamEvent>{
            3847: _teamEvent(3847, 54.0),
            254: _teamEvent(254, 61.0),
            1323: _teamEvent(1323, 27.5),
            118: _teamEvent(118, 48.0),
            971: _teamEvent(971, 39.5),
          }
        : const <int, StatboticsTeamEvent>{},
    analyses: withScouting
        ? ScoutingAnalysis.aggregateByTeam(<ScoutEntry>[
            ScoutEntry(matchId: 'qm1', teamNumber: 3847),
            ScoutEntry(matchId: 'qm2', teamNumber: 3847),
            ScoutEntry(matchId: 'qm1', teamNumber: 254),
          ])
        : const <int, TeamAnalysis>{},
  );
}

void main() {
  group('MatchPreview.fromMatch', () {
    test('keeps all six robots, on the right alliances', () {
      final preview = _preview();

      expect(preview.red.map((t) => t.teamNumber), <int>[3847, 254, 1323]);
      expect(preview.blue.map((t) => t.teamNumber), <int>[118, 971, 2056]);
      expect(preview.red.every((t) => t.isRed), isTrue);
      expect(preview.blue.every((t) => t.isRed), isFalse);
    });

    test('labels the match the way the schedule does', () {
      expect(_preview().matchLabel, 'Qual 34');
    });

    test('sums the EPA it has and ignores the robots without it', () {
      final preview = _preview();

      expect(preview.redEpa, closeTo(54.0 + 61.0 + 27.5, 0.001));

      expect(preview.blueEpa, closeTo(48.0 + 39.5, 0.001));
    });

    test('an alliance with no EPA at all is null, not zero', () {
      final preview = _preview(withEpa: false);

      expect(preview.redEpa, isNull);
      expect(preview.blueEpa, isNull);
    });

    test('names the robots nobody has scouted', () {
      final preview = _preview();

      expect(preview.unscouted.map((t) => t.teamNumber), <int>[
        1323,
        118,
        971,
        2056,
      ]);
      expect(preview.red.first.isScouted, isTrue);
      expect(preview.red.first.matchesScouted, 2);
    });
  });

  testWidgets('shows both alliances and their EPA', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: MatchPreviewScreen(preview: _preview())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Red'), findsOneWidget);
    expect(find.text('Blue'), findsOneWidget);
    expect(find.text('EPA 142.5'), findsOneWidget);
    expect(find.text('3847'), findsOneWidget);
    expect(find.text('Spectrum'), findsOneWidget);

    expect(find.textContaining('Scouted 2x'), findsOneWidget);
    expect(find.text('Not scouted'), findsNWidgets(4));
    expect(find.textContaining('Not scouted yet: 1323'), findsOneWidget);
  });

  testWidgets('stays side by side at a phone width', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: MatchPreviewScreen(preview: _preview())),
    );
    await tester.pumpAndSettle();

    final red = tester.getTopLeft(find.text('Red'));
    final blue = tester.getTopLeft(find.text('Blue'));
    expect(blue.dy, red.dy);
    expect(blue.dx, greaterThan(red.dx));
  });

  testWidgets('the screen says what it is for', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: MatchPreviewScreen(preview: _preview())),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('For the strategy call before this match plays'),
      findsOneWidget,
    );
  });
}
