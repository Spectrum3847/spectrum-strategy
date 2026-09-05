import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/widgets/match_schedule_row.dart';

StatboticsMatch _match() => StatboticsMatch(
  key: '2026txdri1_qm1',
  event: '2026txdri1',
  matchNumber: 1,
  compLevel: 'qm',
  redTeams: const <int>[254],
  blueTeams: const <int>[3847],
);

TbaScheduleMatch _tbaMatch({
  List<Map<String, dynamic>> videos = const <Map<String, dynamic>>[],
  Map<String, dynamic>? breakdown,
  bool played = true,
}) => TbaScheduleMatch.fromJson(<String, dynamic>{
  'key': '2026txdri1_qm1',
  'comp_level': 'qm',
  'match_number': 1,
  if (played) 'winning_alliance': 'blue',
  if (played) 'actual_time': 1786000000,
  'alliances': <String, dynamic>{
    'red': <String, dynamic>{
      'team_keys': <dynamic>['frc254'],
      'score': played ? 61 : -1,
    },
    'blue': <String, dynamic>{
      'team_keys': <dynamic>['frc3847'],
      'score': played ? 78 : -1,
    },
  },
  'videos': videos,
  'score_breakdown': ?breakdown,
});

void main() {
  Future<void> pump(
    WidgetTester tester, {
    TbaScheduleMatch? tbaMatch,
    bool showResult = false,
    bool showVideo = false,
    bool showRankingPoints = false,
    TbaMatchPrediction? prediction,
    bool showPrediction = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatchScheduleRow(
            match: _match(),
            nicknames: const <int, String>{},
            tbaMatch: tbaMatch,
            showResult: showResult,
            showVideo: showVideo,
            showRankingPoints: showRankingPoints,
            prediction: prediction,
            showPrediction: showPrediction,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('sections stay off unless turned on', () {
    testWidgets('a payload with every section off shows no extras', (
      tester,
    ) async {
      await pump(
        tester,
        tbaMatch: _tbaMatch(
          videos: const [
            {'type': 'youtube', 'key': 'abc123'},
          ],
          breakdown: const {
            'red': {'rp': 1},
            'blue': {'rp': 4},
          },
        ),
      );

      expect(find.text('61'), findsNothing);
      expect(find.text('78'), findsNothing);
      expect(find.text('4RP'), findsNothing);
      expect(find.text('Video'), findsNothing);
      expect(find.textContaining('Played'), findsNothing);
    });

    testWidgets('results show scores and the time, not RP or video', (
      tester,
    ) async {
      await pump(
        tester,
        showResult: true,
        tbaMatch: _tbaMatch(
          videos: const [
            {'type': 'youtube', 'key': 'abc123'},
          ],
          breakdown: const {
            'blue': {'rp': 4},
          },
        ),
      );

      expect(find.text('61'), findsOneWidget);
      expect(find.text('78'), findsOneWidget);
      expect(find.textContaining('Played'), findsOneWidget);
      expect(find.text('4RP'), findsNothing);
      expect(find.text('Video'), findsNothing);
    });

    testWidgets('ranking points render without the scores', (tester) async {
      await pump(
        tester,
        showRankingPoints: true,
        tbaMatch: _tbaMatch(
          breakdown: const {
            'red': {'rp': 1},
            'blue': {'rp': 4},
          },
        ),
      );

      expect(find.text('1RP'), findsOneWidget);
      expect(find.text('4RP'), findsOneWidget);
      expect(find.text('61'), findsNothing);
    });
  });

  group('the video link has three outcomes', () {
    testWidgets('a YouTube video is linked', (tester) async {
      await pump(
        tester,
        showVideo: true,
        tbaMatch: _tbaMatch(
          videos: const [
            {'type': 'youtube', 'key': 'abc123'},
          ],
        ),
      );

      expect(find.text('Video'), findsOneWidget);
    });

    testWidgets('a non-YouTube video still gets a link', (tester) async {
      await pump(
        tester,
        showVideo: true,
        tbaMatch: _tbaMatch(
          videos: const [
            {'type': 'tba', 'key': 'something'},
          ],
        ),
      );

      expect(find.text('Video'), findsOneWidget);
    });

    testWidgets('no videos at all means no button', (tester) async {
      await pump(tester, showVideo: true, tbaMatch: _tbaMatch(played: false));

      expect(find.text('Video'), findsNothing);
    });

    testWidgets('no TBA payload at all means no button', (tester) async {
      await pump(tester, showVideo: true);

      expect(find.text('Video'), findsNothing);
    });
  });

  group('an unplayed match', () {
    testWidgets('shows no score, because TBA sends -1 for one', (tester) async {
      await pump(tester, showResult: true, tbaMatch: _tbaMatch(played: false));

      expect(find.text('-1'), findsNothing);
      expect(find.text('61'), findsNothing);
      expect(find.textContaining('Played'), findsNothing);
    });
  });

  group('predicted scores', () {
    const prediction = TbaMatchPrediction(
      matchKey: '2026txdri1_qm1',
      redScore: 109.3,
      blueScore: 111.1,
      winningAlliance: 'blue',
      probability: 0.515,
    );

    testWidgets('an unplayed match shows both predictions and the call', (
      tester,
    ) async {
      await pump(
        tester,
        tbaMatch: _tbaMatch(played: false),
        prediction: prediction,
        showPrediction: true,
      );

      expect(find.text('~109'), findsOneWidget);
      expect(find.text('~111'), findsOneWidget);

      expect(find.text('TBA predicts Blue, 52%'), findsOneWidget);
    });

    testWidgets('a played match shows the result, not the guess', (
      tester,
    ) async {
      await pump(
        tester,
        tbaMatch: _tbaMatch(),
        showResult: true,
        prediction: prediction,
        showPrediction: true,
      );

      expect(find.text('61'), findsOneWidget);
      expect(find.text('78'), findsOneWidget);
      expect(find.text('~109'), findsNothing);
      expect(find.textContaining('TBA predicts'), findsNothing);
    });

    testWidgets('the section being off hides it', (tester) async {
      await pump(
        tester,
        tbaMatch: _tbaMatch(played: false),
        prediction: prediction,
      );

      expect(find.text('~109'), findsNothing);
      expect(find.textContaining('TBA predicts'), findsNothing);
    });

    testWidgets('an event TBA has no prediction for shows nothing', (
      tester,
    ) async {
      await pump(
        tester,
        tbaMatch: _tbaMatch(played: false),
        showPrediction: true,
      );

      expect(find.textContaining('~'), findsNothing);
      expect(find.textContaining('TBA predicts'), findsNothing);
    });
  });
}
