import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/models/cycle_log.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/services/assistant/scoring_trend_analysis.dart';
import 'package:spectrumstrategy/src/services/statbotics/team_history_service.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/ui/scoring_trend_card.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('the series', () {
    test('is empty for a team with no entries', () {
      expect(ScoringTrendAnalysis.series(3847, const <ScoutEntry>[]), isEmpty);
    });

    test('ignores entries for other teams', () {
      final series = ScoringTrendAnalysis.series(3847, [
        _entry(matchId: 'qm1', teamNumber: 254),
      ]);
      expect(series, isEmpty);
    });

    test('orders matches by play order, not by input order', () {
      final series = ScoringTrendAnalysis.series(3847, [
        _entry(matchId: 'qm12', teamNumber: 3847),
        _entry(matchId: 'qm2', teamNumber: 3847),
        _entry(matchId: 'qm1', teamNumber: 3847),
      ]);

      expect(series.map((p) => p.matchLabel).toList(), [
        'Match 1',
        'Match 2',
        'Match 12',
      ]);
    });

    test('playoff matches sort after qualification matches', () {
      final series = ScoringTrendAnalysis.series(3847, [
        _entry(matchId: 'f1', teamNumber: 3847),
        _entry(matchId: 'sf2m1', teamNumber: 3847),
        _entry(matchId: 'qm3', teamNumber: 3847),
      ]);

      expect(series.map((p) => p.matchLabel).toList(), [
        'Match 3',
        'Semifinal 1',
        'Final 1',
      ]);
    });

    test('an entry with one match', () {
      final series = ScoringTrendAnalysis.series(3847, [
        _entry(
          matchId: 'qm1',
          teamNumber: 3847,
          byPhase: {
            StrategyPhase.auton: const ScoutPhaseData(score: 10),
            StrategyPhase.teleop: const ScoutPhaseData(score: 20, penalties: 1),
            StrategyPhase.endgame: const ScoutPhaseData(score: 5),
          },
        ),
      ]);

      expect(series, hasLength(1));
      expect(series.single.totalScore, 35);
      expect(series.single.autonScore, 10);
      expect(series.single.teleopScore, 20);
      expect(series.single.endgameScore, 5);
      expect(series.single.penalties, 1);
    });

    test('a phase never recorded reads as zero, not missing', () {
      final series = ScoringTrendAnalysis.series(3847, [
        _entry(
          matchId: 'qm1',
          teamNumber: 3847,
          byPhase: {StrategyPhase.auton: const ScoutPhaseData(score: 10)},
        ),
      ]);

      expect(series.single.teleopScore, 0);
      expect(series.single.endgameScore, 0);
    });

    test('carries the scouted alliance', () {
      final series = ScoringTrendAnalysis.series(3847, [
        _entry(matchId: 'qm1', teamNumber: 3847, alliance: 'Blue'),
      ]);

      expect(series.single.alliance, 'Blue');
    });

    test('entries with no parseable match keep a stable relative order', () {
      final series = ScoringTrendAnalysis.series(3847, [
        _entry(
          matchId: 'not-a-match',
          teamNumber: 3847,
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
        _entry(
          matchId: 'also-not-a-match',
          teamNumber: 3847,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        _entry(matchId: 'qm1', teamNumber: 3847),
      ]);

      expect(series.map((p) => p.matchLabel).toList(), [
        'Match 1',
        'also-not-a-match',
        'not-a-match',
      ]);
    });
  });

  group('the request', () {
    test('is not built when there are too few matches', () {
      expect(
        ScoringTrendAnalysis.request(
          teamNumber: 3847,
          eventKey: '2026txhou',
          series: _series(ScoringTrendAnalysis.minimumMatches - 1),
        ),
        isNull,
      );
    });

    test('is built once there are enough matches', () {
      final request = ScoringTrendAnalysis.request(
        teamNumber: 3847,
        eventKey: '2026txhou',
        series: _series(ScoringTrendAnalysis.minimumMatches),
      );

      expect(request, isNotNull);
      expect(request!.cacheKey, 'scoring-trend:2026txhou:3847');
      expect(request.coverage, ScoringTrendAnalysis.minimumMatches);
    });

    test('the same team at two events does not share a summary', () {
      expect(
        ScoringTrendAnalysis.cacheKeyFor(
          teamNumber: 3847,
          eventKey: '2026txhou',
        ),
        isNot(
          ScoringTrendAnalysis.cacheKeyFor(
            teamNumber: 3847,
            eventKey: '2026txdri',
          ),
        ),
      );
    });

    test('carries every match into the prompt', () {
      final request = ScoringTrendAnalysis.request(
        teamNumber: 3847,
        eventKey: '2026txhou',
        series: const [
          MatchScorePoint(
            matchLabel: 'Match 1',
            totalScore: 35,
            autonScore: 10,
            teleopScore: 20,
            endgameScore: 5,
            penalties: 1,
            alliance: 'Red',
          ),
          MatchScorePoint(
            matchLabel: 'Match 2',
            totalScore: 42,
            autonScore: 12,
            teleopScore: 24,
            endgameScore: 6,
            penalties: 0,
            alliance: 'Blue',
          ),
          MatchScorePoint(
            matchLabel: 'Match 3',
            totalScore: 40,
            autonScore: 11,
            teleopScore: 23,
            endgameScore: 6,
            penalties: 0,
            alliance: 'Blue',
          ),
        ],
      )!;

      expect(request.prompt, contains('team 3847'));
      expect(
        request.prompt,
        contains('- Match 1: 35.0 / 10.0 / 20.0 / 5.0 / 1 pen / Red'),
      );
      expect(
        request.prompt,
        contains('- Match 2: 42.0 / 12.0 / 24.0 / 6.0 / 0 pen / Blue'),
      );
    });

    test('says plainly when there is no season history', () {
      final request = ScoringTrendAnalysis.request(
        teamNumber: 3847,
        eventKey: '2026txhou',
        series: _series(ScoringTrendAnalysis.minimumMatches),
      )!;

      expect(
        request.prompt,
        contains('No season-by-season history is available for this team'),
      );
      expect(request.prompt, isNot(contains('Season history (EPA')));
    });

    test('carries each season into the prompt on its own line', () {
      final request = ScoringTrendAnalysis.request(
        teamNumber: 3847,
        eventKey: '2026txhou',
        series: _series(ScoringTrendAnalysis.minimumMatches),
        seasons: [
          _season(year: 2026, unitless: 1800, norm: 1720, rank: 40, wins: 30),
          _season(year: 2025, unitless: 1650, norm: 1600, rank: 210, wins: 22),
        ],
      )!;

      expect(request.prompt, contains('Season history (EPA, newest first):'));
      expect(request.prompt, contains('- 2026: unitless EPA 1800.0'));
      expect(request.prompt, contains('world rank 40 of 3600'));
      expect(request.prompt, contains('record 30-4-1'));
      expect(request.prompt, contains('- 2025: unitless EPA 1650.0'));
      expect(request.prompt, contains('world rank 210 of 3600'));
    });

    test('tells the model the two tables are in different units', () {
      final request = ScoringTrendAnalysis.request(
        teamNumber: 3847,
        eventKey: '2026txhou',
        series: _series(ScoringTrendAnalysis.minimumMatches),
        seasons: [_season(year: 2026, totalPoints: 88.5)],
      )!;

      expect(request.system, contains('different units'));
      expect(request.system, contains('unitless scale'));
      expect(request.prompt, contains('in this event\'s scouting points'));
      expect(
        request.prompt,
        contains('never on EPA points, which mean different things'),
      );
      expect(request.prompt, contains('not comparable across seasons'));
    });

    test('a season with no EPA breakdown still produces a line', () {
      final request = ScoringTrendAnalysis.request(
        teamNumber: 3847,
        eventKey: '2026txhou',
        series: _series(ScoringTrendAnalysis.minimumMatches),
        seasons: [
          StatboticsTeamYear(
            team: 3847,
            year: 2003,
            wins: 4,
            losses: 6,
            ties: 0,
            epa: StatboticsEpa.empty,
          ),
        ],
      )!;

      expect(request.prompt, contains('- 2003: record 4-6-0'));
      expect(request.prompt, isNot(contains('phase split')));
    });

    test('the seasons covered are part of the cache key', () {
      final withoutHistory = ScoringTrendAnalysis.cacheKeyFor(
        teamNumber: 3847,
        eventKey: '2026txhou',
      );
      final withHistory = ScoringTrendAnalysis.cacheKeyFor(
        teamNumber: 3847,
        eventKey: '2026txhou',
        seasons: [_season(year: 2026), _season(year: 2025)],
      );
      final withNewerHistory = ScoringTrendAnalysis.cacheKeyFor(
        teamNumber: 3847,
        eventKey: '2026txhou',
        seasons: [_season(year: 2027), _season(year: 2026)],
      );

      expect(withoutHistory, 'scoring-trend:2026txhou:3847');
      expect(withHistory, 'scoring-trend:2026txhou:3847:2025-2026');
      expect(withHistory, isNot(withNewerHistory));

      expect(
        ScoringTrendAnalysis.cacheKeyFor(
          teamNumber: 3847,
          eventKey: '2026txhou',
          seasons: [_season(year: 2025), _season(year: 2026)],
        ),
        withHistory,
      );
    });
  });

  group('cycle time summary', () {
    test('is null below the floor of filmed matches', () {
      final logs = [_cycleLog(matchKey: 'qm1'), _cycleLog(matchKey: 'qm2')];
      expect(
        logs.length,
        lessThan(ScoringTrendAnalysis.minimumCycleLogMatches),
      );

      expect(ScoringTrendAnalysis.cycleSummary(logs), isNull);
    });

    test('is null when logs exist but nothing was ever marked', () {
      final logs = [
        for (var i = 1; i <= ScoringTrendAnalysis.minimumCycleLogMatches; i++)
          CycleLog(matchKey: 'qm$i', team: 3847),
      ];

      expect(ScoringTrendAnalysis.cycleSummary(logs), isNull);
    });

    test('summarizes once at the floor of filmed matches', () {
      final logs = [
        _cycleLog(matchKey: 'qm1', cycleCount: 2, cycleMs: 3000),
        _cycleLog(matchKey: 'qm2', cycleCount: 2, cycleMs: 5000),
        _cycleLog(matchKey: 'qm3', cycleCount: 1, cycleMs: 4000),
      ];

      final summary = ScoringTrendAnalysis.cycleSummary(logs)!;

      expect(summary.matchesCovered, 3);
      expect(summary.cycleCount, 5);
      expect(summary.meanMs, (3000 + 3000 + 5000 + 5000 + 4000) / 5);
    });

    test('counts distinct matches, not distinct logs', () {
      final logs = [
        _cycleLog(matchKey: 'qm1', cycleCount: 1),
        _cycleLog(matchKey: 'qm1', cycleCount: 1),
        _cycleLog(matchKey: 'qm2', cycleCount: 1),
      ];

      expect(ScoringTrendAnalysis.cycleSummary(logs), isNull);
    });
  });

  group('the request with cycle logs', () {
    test('carries the cycle table and its coverage caveat into the prompt', () {
      final request = ScoringTrendAnalysis.request(
        teamNumber: 3847,
        eventKey: '2026txhou',
        series: _series(10),
        cycleLogs: [
          _cycleLog(matchKey: 'qm1', cycleCount: 2, cycleMs: 4000),
          _cycleLog(matchKey: 'qm2', cycleCount: 2, cycleMs: 4000),
          _cycleLog(matchKey: 'qm3', cycleCount: 2, cycleMs: 4000),
        ],
        totalMatches: 10,
      )!;

      expect(request.prompt, contains('Cycle time table'));
      expect(request.prompt, contains('3 of 10 matches'));
      expect(request.prompt, contains('mean cycle: 4.0s'));
      expect(request.prompt, contains('filmed matches: 3 of 10'));
      expect(request.prompt, contains('cycles logged: 6'));
      expect(request.system, contains('never describe it as'));
    });

    test('leaves out the cycle table below the floor', () {
      final request = ScoringTrendAnalysis.request(
        teamNumber: 3847,
        eventKey: '2026txhou',
        series: _series(10),
        cycleLogs: [
          _cycleLog(matchKey: 'qm1'),
          _cycleLog(matchKey: 'qm2'),
        ],
        totalMatches: 10,
      )!;

      expect(request.prompt, isNot(contains('Cycle time table')));
    });

    test('the cycle summary is part of the cache key', () {
      final withoutCycles = ScoringTrendAnalysis.cacheKeyFor(
        teamNumber: 3847,
        eventKey: '2026txhou',
      );
      final withCycles = ScoringTrendAnalysis.cacheKeyFor(
        teamNumber: 3847,
        eventKey: '2026txhou',
        cycles: ScoringTrendAnalysis.cycleSummary([
          _cycleLog(matchKey: 'qm1', cycleCount: 1),
          _cycleLog(matchKey: 'qm2', cycleCount: 1),
          _cycleLog(matchKey: 'qm3', cycleCount: 1),
        ]),
      );

      expect(withCycles, isNot(withoutCycles));
    });
  });

  group('the card', () {
    testWidgets('shows the chart without an assistant, but no AI parts', (
      tester,
    ) async {
      await _pump(tester, assistant: null, series: _series(6));

      expect(find.text('Scoring trend'), findsOneWidget);
      expect(find.text('Peak 26 pts'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Explain the trend'), findsNothing);
    });

    testWidgets(
      'renders nothing when there are too few matches and no history',
      (tester) async {
        await _pump(
          tester,
          assistant: _service(_FakeBackend()),
          series: _series(ScoringTrendAnalysis.minimumMatches - 1),
        );

        expect(find.text('Scoring trend'), findsNothing);
      },
    );

    testWidgets(
      'shows the chart when no backend is configured, but no AI parts',
      (tester) async {
        await _pump(
          tester,
          assistant: _service(_FakeBackend(available: false)),
          series: _series(6),
        );

        expect(find.text('Scoring trend'), findsOneWidget);
        expect(find.text('Peak 26 pts'), findsOneWidget);
        expect(find.text('Explain the trend'), findsNothing);
      },
    );

    testWidgets('generates on render, with no button to press', (tester) async {
      final backend = _FakeBackend();
      await _pump(tester, assistant: _service(backend), series: _series(6));

      expect(find.text('Explain the trend'), findsNothing);
      expect(backend.calls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('generates on render, then shows its provenance', (
      tester,
    ) async {
      final backend = _FakeBackend();
      await _pump(tester, assistant: _service(backend), series: _series(6));

      expect(backend.calls, 1);
      expect(find.textContaining('rose after match'), findsOneWidget);
      expect(find.textContaining('Written from 6 matches'), findsOneWidget);
      expect(find.textContaining('fake-model'), findsOneWidget);
    });

    testWidgets('a cached summary shows without touching the backend', (
      tester,
    ) async {
      final backend = _FakeBackend();
      final service = _service(backend);
      await service.generate(
        ScoringTrendAnalysis.request(
          teamNumber: 3847,
          eventKey: '2026txhou',
          series: _series(6),
        )!,
      );

      await _pump(tester, assistant: service, series: _series(6));

      expect(find.textContaining('rose after match'), findsOneWidget);
      expect(find.text('Explain the trend'), findsNothing);
      expect(backend.calls, 1);
    });

    testWidgets('says so when the summary is older than the matches', (
      tester,
    ) async {
      final service = _service(_FakeBackend());
      await service.generate(
        ScoringTrendAnalysis.request(
          teamNumber: 3847,
          eventKey: '2026txhou',
          series: _series(6),
        )!,
      );

      await _pump(tester, assistant: service, series: _series(10));

      expect(find.textContaining('from 6 of 10 matches'), findsOneWidget);
    });

    testWidgets('a failure is a message, not a broken screen', (tester) async {
      final service = _service(_FakeBackend(failWith: 'the router is down'));
      await _pump(tester, assistant: service, series: _series(6));

      await tester.tap(find.text('Explain the trend'));
      await tester.pumpAndSettle();

      expect(find.textContaining('the router is down'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a scouter without canPublish does not auto-generate and sees no '
      'button',
      (tester) async {
        final backend = _FakeBackend();
        await _pump(
          tester,
          assistant: _service(backend),
          series: _series(6),
          canPublish: false,
        );

        expect(backend.calls, 0);
        expect(find.text('Explain the trend'), findsNothing);
        expect(
          find.textContaining('A strategy lead can write one'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a scouter without canPublish still reads a published explanation, '
      'with no regenerate button',
      (tester) async {
        final backend = _FakeBackend();
        final service = _service(backend);
        await service.generate(
          ScoringTrendAnalysis.request(
            teamNumber: 3847,
            eventKey: '2026txhou',
            series: _series(6),
          )!,
        );

        await _pump(
          tester,
          assistant: service,
          series: _series(6),
          canPublish: false,
        );

        expect(find.textContaining('rose after match'), findsOneWidget);
        expect(find.byIcon(Icons.refresh), findsNothing);
        expect(backend.calls, 1);
      },
    );

    testWidgets('the chart draws bars with real width', (tester) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend()),
        series: _series(6),
      );

      final bars = find.descendant(
        of: find.byType(ScoringTrendCard),
        matching: find.byType(DecoratedBox),
      );
      final widths = tester
          .widgetList<DecoratedBox>(bars)
          .map((box) => tester.getSize(find.byWidget(box)).width)
          .where((width) => width > 0)
          .toList();

      expect(widths, isNotEmpty, reason: 'every bar laid out zero-width');
      expect(widths.every((w) => w >= 8), isTrue, reason: 'bars are hairlines');
    });

    testWidgets('the chart labels its peak so the bars have a scale', (
      tester,
    ) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend()),
        series: _series(6),
      );

      expect(find.text('Peak 26 pts'), findsOneWidget);
    });

    testWidgets('says so when the team has no season history', (tester) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend()),
        series: _series(6),
      );

      expect(find.text('No season history for this team.'), findsOneWidget);
      expect(find.text('Recent seasons'), findsNothing);
    });

    testWidgets('shows the recent seasons when history is available', (
      tester,
    ) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend()),
        series: _series(6),
        history: _history({
          3847: [
            _season(year: 2026, norm: 1720, rank: 40, wins: 30),
            _season(year: 2025, norm: 1600, rank: 210, wins: 22),
          ],
        }),
      );

      expect(find.text('Recent seasons'), findsOneWidget);
      expect(find.text('No season history for this team.'), findsNothing);
      expect(find.textContaining('2026'), findsWidgets);
      expect(find.textContaining('normalized EPA 1720'), findsOneWidget);
      expect(find.textContaining('rank 40 of 3600'), findsOneWidget);
      expect(find.textContaining('normalized EPA 1600'), findsOneWidget);
    });

    testWidgets('labels both halves so neither is read in the other\'s '
        'units', (tester) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend()),
        series: _series(6),
        history: _history({
          3847: [_season(year: 2026, norm: 1720)],
        }),
      );

      expect(find.textContaining('in scouting points'), findsOneWidget);
      expect(
        find.textContaining('seasons compare on the normalized scale'),
        findsOneWidget,
      );
    });

    testWidgets('the season half survives 200% text', (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: ScoringTrendCard(
                  assistant: _service(_FakeBackend()),
                  teamNumber: 3847,
                  eventKey: '2026txhou',
                  series: _series(6),
                  history: _history({
                    3847: [
                      _season(year: 2026, norm: 1720, rank: 40, wins: 30),
                      _season(year: 2025, norm: 1600, rank: 210, wins: 22),
                    ],
                  }),
                  cycleLogs: [
                    _cycleLog(matchKey: 'qm1', cycleCount: 2, cycleMs: 4000),
                    _cycleLog(matchKey: 'qm2', cycleCount: 2, cycleMs: 4000),
                    _cycleLog(matchKey: 'qm3', cycleCount: 2, cycleMs: 4000),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recent seasons'), findsOneWidget);
      expect(find.text('Cycle time (filmed matches)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a summary written before history loaded is not reused', (
      tester,
    ) async {
      final backend = _FakeBackend();
      final service = _service(backend);
      await service.generate(
        ScoringTrendAnalysis.request(
          teamNumber: 3847,
          eventKey: '2026txhou',
          series: _series(6),
        )!,
      );

      await _pump(
        tester,
        assistant: service,
        series: _series(6),
        history: _history({
          3847: [_season(year: 2026)],
        }),
      );

      expect(find.textContaining('rose after match'), findsOneWidget);
      expect(backend.calls, 2);
    });

    testWidgets('the cycle section appears once at its floor of matches', (
      tester,
    ) async {
      await _pump(
        tester,
        assistant: null,
        series: _series(6),
        cycleLogs: [
          _cycleLog(matchKey: 'qm1', cycleCount: 2, cycleMs: 4000),
          _cycleLog(matchKey: 'qm2', cycleCount: 2, cycleMs: 4000),
          _cycleLog(matchKey: 'qm3', cycleCount: 2, cycleMs: 4000),
        ],
      );

      expect(find.text('Cycle time (filmed matches)'), findsOneWidget);
      expect(find.textContaining('4.0s avg'), findsOneWidget);
      expect(find.textContaining('From 3 of 6 matches'), findsOneWidget);
    });

    testWidgets('the cycle section is left out below its floor', (
      tester,
    ) async {
      await _pump(
        tester,
        assistant: null,
        series: _series(6),
        cycleLogs: [
          _cycleLog(matchKey: 'qm1'),
          _cycleLog(matchKey: 'qm2'),
        ],
      );

      expect(find.text('Cycle time (filmed matches)'), findsNothing);
    });

    testWidgets(
      'cycle data alone is enough to show the card with no matches or '
      'season history',
      (tester) async {
        await _pump(
          tester,
          assistant: null,
          series: const <MatchScorePoint>[],
          cycleLogs: [
            _cycleLog(matchKey: 'qm1'),
            _cycleLog(matchKey: 'qm2'),
            _cycleLog(matchKey: 'qm3'),
          ],
        );

        expect(find.text('Scoring trend'), findsOneWidget);
        expect(find.text('Cycle time (filmed matches)'), findsOneWidget);
      },
    );

    testWidgets('a history service that answers nothing is not an error', (
      tester,
    ) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend()),
        series: _series(6),
        history: _history(const <int, List<StatboticsTeamYear>>{}),
      );

      expect(find.text('Scoring trend'), findsOneWidget);
      expect(find.text('No season history for this team.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

TeamHistoryService _history(Map<int, List<StatboticsTeamYear>> seasons) =>
    TeamHistoryService(client: _FakeStatboticsClient(seasons));

StatboticsTeamYear _season({
  required int year,
  double? unitless,
  double? norm,
  int? rank,
  int wins = 10,
  double? totalPoints,
}) => StatboticsTeamYear(
  team: 3847,
  year: year,
  wins: wins,
  losses: 4,
  ties: 1,
  epaRank: rank,
  epaRankTeamCount: rank == null ? null : 3600,
  epa: StatboticsEpa(totalPoints: totalPoints, unitless: unitless, norm: norm),
);

Future<void> _pump(
  WidgetTester tester, {
  required AssistantService? assistant,
  required List<MatchScorePoint> series,
  TeamHistoryService? history,
  List<CycleLog> cycleLogs = const <CycleLog>[],
  bool canPublish = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScoringTrendCard(
            assistant: assistant,
            teamNumber: 3847,
            eventKey: '2026txhou',
            series: series,
            history: history,
            cycleLogs: cycleLogs,
            canPublish: canPublish,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

CycleLog _cycleLog({
  required String matchKey,
  int cycleCount = 1,
  int cycleMs = 4000,
}) {
  final events = <CycleEvent>[];
  var offset = 0;
  for (var i = 0; i < cycleCount; i++) {
    events.add(
      CycleEvent(
        kind: CycleEventKind.intake,
        offsetMs: offset,
        phase: StrategyPhase.teleop,
      ),
    );
    offset += cycleMs;
    events.add(
      CycleEvent(
        kind: CycleEventKind.score,
        offsetMs: offset,
        phase: StrategyPhase.teleop,
      ),
    );
    offset += 1000;
  }
  return CycleLog(matchKey: matchKey, team: 3847, events: events);
}

class _FakeStatboticsClient extends StatboticsClient {
  _FakeStatboticsClient(this._seasons);

  final Map<int, List<StatboticsTeamYear>> _seasons;

  @override
  Future<List<StatboticsTeamYear>> getTeamYears(int team) async =>
      _seasons[team] ?? const <StatboticsTeamYear>[];
}

AssistantService _service(_FakeBackend backend) => AssistantService(
  backends: [backend],
  cache: AssistantCache(),
  minimumGap: Duration.zero,
);

ScoutEntry _entry({
  required String matchId,
  required int teamNumber,
  String alliance = 'Red',
  DateTime? updatedAt,
  Map<StrategyPhase, ScoutPhaseData>? byPhase,
}) {
  return ScoutEntry(
    matchId: matchId,
    teamNumber: teamNumber,
    alliance: alliance,
    updatedAt: updatedAt,
    byPhase: byPhase,
  );
}

List<MatchScorePoint> _series(int count) => [
  for (var i = 1; i <= count; i++)
    MatchScorePoint(
      matchLabel: 'Match $i',
      totalScore: 20 + i.toDouble(),
      autonScore: 5,
      teleopScore: 12 + i.toDouble(),
      endgameScore: 3,
      penalties: 0,
      alliance: i.isEven ? 'Blue' : 'Red',
    ),
];

class _FakeBackend implements AssistantBackend {
  _FakeBackend({this.available = true, this.failWith});

  final bool available;
  final String? failWith;
  int calls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    calls++;
    final reason = failWith;
    if (reason != null) {
      throw AssistantUnavailable(reason);
    }
    return AssistantSummary(
      text: 'The total rose after match 4 once auton stopped stalling.',
      generatedAt: DateTime.now().toUtc(),
      model: 'fake-model',
      source: AssistantSource.openRouter,
    );
  }
}
