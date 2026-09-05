import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/services/assistant/team_brief.dart';
import 'package:spectrumstrategy/src/services/statbotics/team_history_service.dart';
import 'package:spectrumstrategy/src/ui/team_brief_card.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('the request', () {
    test('is not built from a single event', () {
      expect(
        TeamBrief.request(
          teamNumber: 3847,
          inputs: TeamBriefInputs(events: [_event(2026, 'a')]),
        ),
        isNull,
      );
    });

    test('is not built from no history at all', () {
      expect(
        TeamBrief.request(teamNumber: 3847, inputs: const TeamBriefInputs()),
        isNull,
      );
    });

    test('is built once there are enough events', () {
      final request = TeamBrief.request(
        teamNumber: 3847,
        inputs: TeamBriefInputs(events: [_event(2026, 'a'), _event(2025, 'b')]),
      );

      expect(request, isNotNull);
      expect(request!.coverage, 2);
    });

    test('demands a citation per claim and forbids softening', () {
      final request = _request();

      expect(request.system, contains('Every sentence must name the event'));
      expect(request.system, contains('drop it rather than softening it'));
      expect(request.system, contains('a coach may repeat it out loud'));
    });

    test('forbids inferring driver skill or reliability from a rank', () {
      final request = _request();

      expect(request.system, contains('its drivers'));
      expect(
        request.system,
        contains('do not describe a team as unreliable, inconsistent or weak'),
      );
      expect(
        request.prompt,
        contains('claim about drivers, reliability or robot design'),
      );
    });

    test('says which direction a rank runs', () {
      final request = _request();

      expect(request.system, contains('A lower rank number is better'));
      expect(request.system, contains('never a concern'));
    });

    test('forbids upgrading an alliance role', () {
      expect(_request().system, contains('a first pick is not a captain'));
    });

    test('names the only things that count as a warning', () {
      final request = _request();

      expect(request.prompt, contains('a losing win-loss record at an event'));
      expect(
        request.prompt,
        contains('Nothing in these results stands out to flag.'),
      );
      expect(request.prompt, contains('Do not comment on your own reasoning'));
    });

    test('says a rank is a qualification rank, not a finish', () {
      expect(_request().prompt, contains('not where it placed overall'));
    });

    test('carries every event into the prompt with its key and rank', () {
      final request = TeamBrief.request(
        teamNumber: 3847,
        inputs: TeamBriefInputs(
          events: [
            _event(
              2026,
              '2026txhou',
              rank: 5,
              numTeams: 34,
              wins: 13,
              losses: 4,
              total: 135.6,
            ),
            _event(
              2025,
              '2025txbel',
              rank: 2,
              numTeams: 41,
              wins: 17,
              losses: 0,
            ),
          ],
        ),
      )!;

      expect(
        request.prompt,
        contains(
          '- 2026 2026txhou (Houston): qualification rank 5 of 34, '
          'record 13-4, EPA 135.6',
        ),
      );
      expect(
        request.prompt,
        contains(
          '- 2025 2025txbel (Houston): qualification rank 2 of 41, '
          'record 17-0',
        ),
      );
    });

    test('an event with no rank recorded says so rather than guessing', () {
      final request = TeamBrief.request(
        teamNumber: 3847,
        inputs: TeamBriefInputs(
          events: [
            _event(2026, 'a'),
            _event(2026, 'b', rank: null, numTeams: null),
          ],
        ),
      )!;

      expect(request.prompt, contains('no qualification rank recorded'));
    });

    test('separates a playoff result from a judged award', () {
      final request = TeamBrief.request(
        teamNumber: 3847,
        inputs: TeamBriefInputs(
          events: [_event(2026, 'a'), _event(2025, 'b')],
          awards: const [
            TeamAwardRow(
              name: 'District Event Winner',
              eventKey: '2026txhou',
              year: 2026,
              isWinOrFinalist: true,
            ),
            TeamAwardRow(
              name: 'Industrial Design Award',
              eventKey: '2026txhou',
              year: 2026,
              isWinOrFinalist: false,
            ),
          ],
        ),
      )!;

      expect(
        request.prompt,
        contains('- 2026 2026txhou: District Event Winner (playoff result)'),
      );
      expect(
        request.prompt,
        contains('- 2026 2026txhou: Industrial Design Award (judged award)'),
      );
    });

    test('no awards is stated as neutral, not as a weakness', () {
      final request = _request();

      expect(request.prompt, contains('Awards: none in these seasons'));
      expect(request.prompt, contains('That is not itself a weakness'));
    });

    test('seasons compare on the scales that survive a game change', () {
      final request = TeamBrief.request(
        teamNumber: 3847,
        inputs: TeamBriefInputs(
          seasons: [_season(2026, norm: 1679), _season(2025, norm: 1645)],
          events: [_event(2026, 'a'), _event(2025, 'b')],
        ),
      )!;

      expect(request.system, contains('never on EPA points'));
      expect(request.prompt, contains('- 2026: unitless EPA 1800.0'));
      expect(request.prompt, contains('normalized EPA 1679.0 (1500 is'));
      expect(request.prompt, contains('world rank 222 of 3724'));
    });

    test('a thin history asks for a short brief and says it is thin', () {
      final thin = TeamBrief.request(
        teamNumber: 3847,
        inputs: TeamBriefInputs(events: [_event(2026, 'a'), _event(2025, 'b')]),
      )!;

      expect(thin.prompt, contains('under 90 words'));
      expect(thin.prompt, contains('only 2 events on record'));
      expect(thin.prompt, contains('there are results, not tendencies'));
      expect(thin.minimumChars, 100);
    });

    test('a full history asks for the full brief with no thinness note', () {
      final full = TeamBrief.request(
        teamNumber: 3847,
        inputs: TeamBriefInputs(
          events: [
            for (var i = 0; i < TeamBrief.fullBriefEvents; i++)
              _event(2026, 'event$i'),
          ],
        ),
      )!;

      expect(full.prompt, contains('under 200 words'));
      expect(full.prompt, isNot(contains('which is thin')));
      expect(full.minimumChars, 200);
    });

    test('the word ceiling steps at fullBriefEvents', () {
      expect(TeamBrief.wordLimitFor(TeamBrief.fullBriefEvents - 1), 90);
      expect(TeamBrief.wordLimitFor(TeamBrief.fullBriefEvents), 200);
    });

    test('carries the alliance placement with the role spelled out', () {
      final request = TeamBrief.request(
        teamNumber: 3847,
        inputs: TeamBriefInputs(
          events: [_event(2026, '2026txhou'), _event(2025, '2025txbel')],
          alliances: const [
            TeamAlliancePlacement(
              eventKey: '2026txhou',
              allianceNumber: 1,
              pickIndex: 1,
              roundReached: 'f',
            ),
            TeamAlliancePlacement(
              eventKey: '2025txbel',
              allianceNumber: 8,
              pickIndex: 0,
              roundReached: 'qf',
            ),
          ],
        ),
      )!;

      expect(
        request.prompt,
        contains('Alliance selection (how the field read them):'),
      );
      expect(
        request.prompt,
        contains('- 2026txhou: alliance 1, first pick, reached the final'),
      );
      expect(
        request.prompt,
        contains(
          '- 2025txbel: alliance 8, alliance captain, reached the '
          'quarterfinal',
        ),
      );
    });

    test('no alliance data leaves the section out', () {
      expect(_request().prompt, isNot(contains('Alliance selection')));
    });

    test('an alliance with no recorded round says so', () {
      final request = TeamBrief.request(
        teamNumber: 3847,
        inputs: TeamBriefInputs(
          events: [_event(2026, 'a'), _event(2025, 'b')],
          alliances: const [
            TeamAlliancePlacement(
              eventKey: 'a',
              allianceNumber: 3,
              pickIndex: 2,
              roundReached: '',
            ),
          ],
        ),
      )!;

      expect(
        request.prompt,
        contains('- a: alliance 3, second pick, no playoff round recorded'),
      );
    });

    test('the pick index reads as a role', () {
      expect(_placement(0).role, 'alliance captain');
      expect(_placement(0).isCaptain, isTrue);
      expect(_placement(1).role, 'first pick');
      expect(_placement(2).role, 'second pick');
      expect(_placement(3).role, 'backup');
      expect(_placement(3).isCaptain, isFalse);
    });

    test('the events covered are part of the cache key', () {
      final two = TeamBrief.cacheKeyFor(
        teamNumber: 3847,
        inputs: TeamBriefInputs(events: [_event(2026, 'a'), _event(2025, 'b')]),
      );
      final three = TeamBrief.cacheKeyFor(
        teamNumber: 3847,
        inputs: TeamBriefInputs(
          events: [_event(2026, 'a'), _event(2025, 'b'), _event(2026, 'c')],
        ),
      );

      expect(two, 'team-brief:3847:a,b');
      expect(two, isNot(three));

      expect(
        TeamBrief.cacheKeyFor(
          teamNumber: 3847,
          inputs: TeamBriefInputs(
            events: [_event(2025, 'b'), _event(2026, 'a')],
          ),
        ),
        two,
      );
    });

    test('two teams do not share a brief', () {
      final inputs = TeamBriefInputs(
        events: [_event(2026, 'a'), _event(2025, 'b')],
      );

      expect(
        TeamBrief.cacheKeyFor(teamNumber: 3847, inputs: inputs),
        isNot(TeamBrief.cacheKeyFor(teamNumber: 254, inputs: inputs)),
      );
    });

    test('does not share a cache slot with the other features', () {
      expect(
        TeamBrief.cacheKeyFor(
          teamNumber: 3847,
          inputs: TeamBriefInputs(
            events: [_event(2026, 'a'), _event(2025, 'b')],
          ),
        ),
        startsWith('team-brief:'),
      );
    });
  });

  group('the inputs', () {
    test('report the seasons they cover, ascending', () {
      final inputs = TeamBriefInputs(
        seasons: [_season(2026), _season(2022)],
        events: [_event(2022, 'a'), _event(2026, 'b')],
      );

      expect(inputs.years, [2022, 2026]);
    });

    test('are empty only when every part is', () {
      expect(const TeamBriefInputs().isEmpty, isTrue);
      expect(TeamBriefInputs(events: [_event(2026, 'a')]).isEmpty, isFalse);
    });
  });

  group('the history service', () {
    test('drops an individual award so no prompt names a person', () async {
      final service = TeamHistoryService(
        client: _FakeStatbotics(
          {
            3847: [_season(2026)],
          },
          events: {
            3847: [_event(2026, 'a'), _event(2026, 'b')],
          },
        ),
        tbaClient: _FakeTba([
          _award('District Event Winner', 1, awardee: null),
          _award("Dean's List Finalist", 4, awardee: 'A Student'),
          _award('Volunteer of the Year', 5, awardee: 'A Volunteer'),
        ]),
      );

      final inputs = await service.briefInputsFor(3847);

      expect(inputs.awards.map((a) => a.name), ['District Event Winner']);
      expect(inputs.awards.single.isWinOrFinalist, isTrue);
    });

    test('no TBA client means no awards, not a failure', () async {
      final service = TeamHistoryService(
        client: _FakeStatbotics(
          {
            3847: [_season(2026)],
          },
          events: {
            3847: [_event(2026, 'a'), _event(2026, 'b')],
          },
        ),
      );

      final inputs = await service.briefInputsFor(3847);

      expect(inputs.awards, isEmpty);
      expect(inputs.events, hasLength(2));
    });

    test('a TBA failure leaves the awards out and keeps the rest', () async {
      final service = TeamHistoryService(
        client: _FakeStatbotics(
          {
            3847: [_season(2026)],
          },
          events: {
            3847: [_event(2026, 'a'), _event(2026, 'b')],
          },
        ),
        tbaClient: _FakeTba(const [], throws: true),
      );

      final inputs = await service.briefInputsFor(3847);

      expect(inputs.awards, isEmpty);
      expect(inputs.events, hasLength(2));
      expect(inputs.seasons, hasLength(1));
    });

    test(
      'the events fetched are the seasons Statbotics knows, not the clock',
      () async {
        final statbotics = _FakeStatbotics(
          {
            3847: [_season(2026), _season(2022)],
          },
          events: {
            3847: [_event(2026, 'a'), _event(2022, 'b')],
          },
        );
        final service = TeamHistoryService(client: statbotics);

        await service.briefInputsFor(3847);

        expect(statbotics.eventYearsAsked, [2026, 2022]);
      },
    );

    test('no seasons means no event or award requests at all', () async {
      final statbotics = _FakeStatbotics(const {});
      final tba = _FakeTba(const []);
      final service = TeamHistoryService(client: statbotics, tbaClient: tba);

      final inputs = await service.briefInputsFor(3847);

      expect(inputs.isEmpty, isTrue);
      expect(statbotics.eventYearsAsked, isEmpty);
      expect(tba.calls, 0);
    });

    test('the kill switch leaves the events out too', () async {
      final statbotics = _FakeStatbotics(
        {
          3847: [_season(2026)],
        },
        events: {
          3847: [_event(2026, 'a')],
        },
      );
      final service = TeamHistoryService(
        client: statbotics,
        statboticsEnabled: false,
      );

      final inputs = await service.briefInputsFor(3847);

      expect(inputs.isEmpty, isTrue);
      expect(statbotics.eventYearsAsked, isEmpty);
    });

    test(
      'a wider request refetches instead of reusing narrower rows',
      () async {
        final statbotics = _FakeStatbotics(
          {
            3847: [_season(2026), _season(2025), _season(2024)],
          },
          events: {
            3847: [_event(2026, 'a'), _event(2025, 'b'), _event(2024, 'c')],
          },
        );
        final service = TeamHistoryService(client: statbotics);

        final narrow = await service.briefInputsFor(3847);
        final wide = await service.briefInputsFor(3847, seasons: 3);

        expect(narrow.events.map((e) => e.event), ['a', 'b']);
        expect(wide.events.map((e) => e.event), ['a', 'b', 'c']);
        expect(statbotics.eventYearsAsked, [2026, 2025, 2026, 2025, 2024]);
      },
    );

    test('reads the alliance placement out of the pick order', () async {
      final tba = _FakeTba(
        const [],
        alliances: {
          'a': [
            ['frc118', 'frc3847', 'frc7691'],
            ['frc254', 'frc971'],
          ],
        },
      );
      final service = TeamHistoryService(
        client: _FakeStatbotics(
          {
            3847: [_season(2026)],
          },
          events: {
            3847: [_event(2026, 'a'), _event(2026, 'b')],
          },
        ),
        tbaClient: tba,
      );

      final inputs = await service.briefInputsFor(3847);

      expect(inputs.alliances, hasLength(1));
      final placement = inputs.alliances.single;
      expect(placement.eventKey, 'a');
      expect(placement.allianceNumber, 1);
      expect(placement.pickIndex, 1);
      expect(placement.role, 'first pick');
      expect(placement.isCaptain, isFalse);
    });

    test('a captain reads as pick index zero', () async {
      final service = TeamHistoryService(
        client: _FakeStatbotics(
          {
            3847: [_season(2026)],
          },
          events: {
            3847: [_event(2026, 'a'), _event(2026, 'b')],
          },
        ),
        tbaClient: _FakeTba(
          const [],
          alliances: {
            'a': [
              ['frc254'],
              ['frc3847', 'frc118'],
            ],
          },
        ),
      );

      final inputs = await service.briefInputsFor(3847);

      expect(inputs.alliances.single.allianceNumber, 2);
      expect(inputs.alliances.single.isCaptain, isTrue);
    });

    test('a TBA failure drops the alliances and keeps the rest', () async {
      final service = TeamHistoryService(
        client: _FakeStatbotics(
          {
            3847: [_season(2026)],
          },
          events: {
            3847: [_event(2026, 'a'), _event(2026, 'b')],
          },
        ),
        tbaClient: _FakeTba(const [], throws: true),
      );

      final inputs = await service.briefInputsFor(3847);

      expect(inputs.alliances, isEmpty);
      expect(inputs.events, hasLength(2));
    });

    test('no TBA client means no alliance rows', () async {
      final service = TeamHistoryService(
        client: _FakeStatbotics(
          {
            3847: [_season(2026)],
          },
          events: {
            3847: [_event(2026, 'a'), _event(2026, 'b')],
          },
        ),
      );

      expect((await service.briefInputsFor(3847)).alliances, isEmpty);
    });

    test('the cached award rows round-trip', () async {
      final statbotics = _FakeStatbotics(
        {
          3847: [_season(2026)],
        },
        events: {
          3847: [_event(2026, 'a'), _event(2026, 'b')],
        },
      );
      final tba = _FakeTba([_award('District Event Winner', 1)]);
      final now = DateTime.utc(2026, 9, 2, 12);
      await TeamHistoryService(
        client: statbotics,
        tbaClient: tba,
        now: () => now,
      ).briefInputsFor(3847);
      expect(tba.calls, 1);

      final restored = await TeamHistoryService(
        client: statbotics,
        tbaClient: tba,
        now: () => now.add(const Duration(hours: 1)),
      ).briefInputsFor(3847);

      expect(tba.calls, 1);
      final award = restored.awards.single;
      expect(award.name, 'District Event Winner');
      expect(award.eventKey, '2026txhou');
      expect(award.year, 2026);
      expect(award.isWinOrFinalist, isTrue);
    });
  });

  group('the card', () {
    testWidgets('renders nothing without an assistant', (tester) async {
      await _pump(tester, assistant: null, history: _history(events: 4));

      expect(find.text('Brief from previous events'), findsNothing);
    });

    testWidgets('renders nothing without a history service', (tester) async {
      await _pump(tester, assistant: _service(_FakeBackend()), history: null);

      expect(find.text('Brief from previous events'), findsNothing);
    });

    testWidgets('renders nothing on one event of history', (tester) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend()),
        history: _history(events: 1),
      );

      expect(find.text('Brief from previous events'), findsNothing);
    });

    testWidgets('renders nothing when no backend is configured', (
      tester,
    ) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend(available: false)),
        history: _history(events: 4),
      );

      expect(find.text('Brief from previous events'), findsNothing);
    });

    testWidgets('writes the brief on render, with no button to press', (
      tester,
    ) async {
      final backend = _FakeBackend();
      await _pump(
        tester,
        assistant: _service(backend),
        history: _history(events: 4),
      );

      expect(find.text('Brief from previous events'), findsOneWidget);
      expect(find.text('Write the brief'), findsNothing);
      expect(backend.calls, 1);
    });

    testWidgets('says what the coverage line covers, alongside the brief', (
      tester,
    ) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend()),
        history: _history(events: 4, awards: 2),
      );

      expect(find.textContaining('4 events'), findsWidgets);
      expect(find.textContaining('2 awards'), findsOneWidget);
    });

    testWidgets('lists non-consecutive seasons rather than as a range', (
      tester,
    ) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend()),
        history: TeamHistoryService(
          client: _FakeStatbotics(
            {
              3847: [_season(2026), _season(2022)],
            },
            events: {
              3847: [_event(2026, 'a'), _event(2022, 'b')],
            },
          ),
        ),
      );

      expect(find.textContaining('in 2026 and 2022'), findsOneWidget);
      expect(find.textContaining('2022 to 2026'), findsNothing);
    });

    testWidgets('writes it on render, then shows provenance and the '
        'caution', (tester) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend()),
        history: _history(events: 4),
      );

      expect(find.textContaining('Watch out for'), findsOneWidget);
      expect(find.textContaining('Written from 4 events'), findsOneWidget);
      expect(find.textContaining('fake-model'), findsOneWidget);

      expect(
        find.textContaining('Check any warning against the event it names'),
        findsOneWidget,
      );
    });

    testWidgets('a failure is a message, not a broken screen', (tester) async {
      await _pump(
        tester,
        assistant: _service(_FakeBackend(failWith: 'the router is down')),
        history: _history(events: 4),
      );

      await tester.tap(find.text('Write the brief'));
      await tester.pumpAndSettle();

      expect(find.textContaining('the router is down'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cached brief shows without touching the backend', (
      tester,
    ) async {
      final backend = _FakeBackend();
      final service = _service(backend);
      final history = _history(events: 4);
      await service.generate(
        TeamBrief.request(
          teamNumber: 3847,
          inputs: await history.briefInputsFor(3847),
        )!,
      );

      await _pump(tester, assistant: service, history: history);

      expect(find.textContaining('Watch out for'), findsOneWidget);
      expect(find.text('Write the brief'), findsNothing);
      expect(backend.calls, 1);
    });

    testWidgets('a brief written before another event is not reused', (
      tester,
    ) async {
      final backend = _FakeBackend();
      final service = _service(backend);
      await service.generate(
        TeamBrief.request(
          teamNumber: 3847,
          inputs: TeamBriefInputs(
            events: [for (var i = 0; i < 4; i++) _event(2026, 'event$i')],
          ),
        )!,
      );

      await _pump(tester, assistant: service, history: _history(events: 5));

      expect(find.textContaining('Watch out for'), findsOneWidget);
      expect(backend.calls, 2);
    });

    testWidgets(
      'a scouter without canPublish does not auto-generate and sees no '
      'button',
      (tester) async {
        final backend = _FakeBackend();
        await _pump(
          tester,
          assistant: _service(backend),
          history: _history(events: 4),
          canPublish: false,
        );

        expect(backend.calls, 0);
        expect(find.text('Write the brief'), findsNothing);
        expect(
          find.textContaining('A strategy lead can write one'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a scouter without canPublish still reads a published brief, with '
      'no regenerate button',
      (tester) async {
        final backend = _FakeBackend();
        final service = _service(backend);
        final history = _history(events: 4);
        await service.generate(
          TeamBrief.request(
            teamNumber: 3847,
            inputs: await history.briefInputsFor(3847),
          )!,
        );

        await _pump(
          tester,
          assistant: service,
          history: history,
          canPublish: false,
        );

        expect(find.textContaining('Watch out for'), findsOneWidget);
        expect(find.byIcon(Icons.refresh), findsNothing);
        expect(backend.calls, 1);
      },
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required AssistantService? assistant,
  required TeamHistoryService? history,
  bool canPublish = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TeamBriefCard(
            assistant: assistant,
            teamNumber: 3847,
            history: history,
            canPublish: canPublish,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TeamHistoryService _history({required int events, int awards = 0}) =>
    TeamHistoryService(
      client: _FakeStatbotics(
        {
          3847: [_season(2026)],
        },
        events: {
          3847: [for (var i = 0; i < events; i++) _event(2026, 'event$i')],
        },
      ),
      tbaClient: awards == 0
          ? null
          : _FakeTba([
              for (var i = 0; i < awards; i++)
                _award('District Event Winner $i', 1),
            ]),
    );

AssistantService _service(_FakeBackend backend) => AssistantService(
  backends: [backend],
  cache: AssistantCache(),
  minimumGap: Duration.zero,
);

AssistantRequest _request() => TeamBrief.request(
  teamNumber: 3847,
  inputs: TeamBriefInputs(events: [_event(2026, 'a'), _event(2025, 'b')]),
)!;

StatboticsTeamYear _season(int year, {double? norm}) => StatboticsTeamYear(
  team: 3847,
  year: year,
  wins: 39,
  losses: 27,
  ties: 0,
  epaRank: 222,
  epaRankTeamCount: 3724,
  epa: StatboticsEpa(totalPoints: 88.4, unitless: 1800, norm: norm),
);

StatboticsTeamEvent _event(
  int year,
  String key, {
  int? rank = 5,
  int? numTeams = 34,
  int wins = 13,
  int losses = 4,
  double? total,
}) => StatboticsTeamEvent(
  team: 3847,
  event: key,
  eventName: 'Houston',
  year: year,
  wins: wins,
  losses: losses,
  ties: 0,
  rank: rank,
  numTeams: numTeams,
  epa: StatboticsEpa(totalPoints: total),
);

TeamAlliancePlacement _placement(int pickIndex) => TeamAlliancePlacement(
  eventKey: '2026txhou',
  allianceNumber: 1,
  pickIndex: pickIndex,
  roundReached: 'f',
);

TbaAward _award(String name, int type, {String? awardee}) => TbaAward(
  name: name,
  awardType: type,
  eventKey: '2026txhou',
  year: 2026,
  recipients: [TbaAwardRecipient(teamKey: 'frc3847', awardee: awardee)],
);

class _FakeStatbotics extends StatboticsClient {
  _FakeStatbotics(
    this._seasons, {
    Map<int, List<StatboticsTeamEvent>> events =
        const <int, List<StatboticsTeamEvent>>{},
  }) : _events = Map<int, List<StatboticsTeamEvent>>.unmodifiable(events);

  final Map<int, List<StatboticsTeamYear>> _seasons;
  final Map<int, List<StatboticsTeamEvent>> _events;

  final List<int> eventYearsAsked = <int>[];

  @override
  Future<List<StatboticsTeamYear>> getTeamYears(int team) async =>
      _seasons[team] ?? const <StatboticsTeamYear>[];

  @override
  Future<List<StatboticsTeamEvent>> getTeamEvents(int team, {int? year}) async {
    if (year != null) {
      eventYearsAsked.add(year);
    }
    return (_events[team] ?? const <StatboticsTeamEvent>[])
        .where((e) => year == null || e.year == year)
        .toList(growable: false);
  }
}

class _FakeTba extends TbaClient {
  _FakeTba(
    this._awards, {
    this.throws = false,
    Map<String, List<List<String>>> alliances =
        const <String, List<List<String>>>{},
  }) : _alliances = Map<String, List<List<String>>>.unmodifiable(alliances),
       super(config: InMemoryTbaConfig('test-key'));

  final List<TbaAward> _awards;

  final Map<String, List<List<String>>> _alliances;

  final bool throws;

  int calls = 0;

  @override
  Future<List<TbaAward>> getTeamAwards(int teamNumber, {int? year}) async {
    calls++;
    if (throws) {
      throw TbaApiException(500, '');
    }
    return _awards;
  }

  @override
  Future<TbaEventAlliances?> getEventAlliances(String eventKey) async {
    if (throws) {
      throw TbaApiException(500, '');
    }
    final picks = _alliances[eventKey];
    if (picks == null) {
      return null;
    }
    return TbaEventAlliances(
      eventKey: eventKey,
      alliances: [
        for (final alliance in picks)
          TbaAlliance(
            name: 'Alliance',
            picks: alliance,
            status: 'f',
            record: '5-0-0',
          ),
      ],
    );
  }
}

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
      text:
          'How they perform: strong at 2026txhou.\n'
          'How they got there: rank 5 of 34 at 2026txhou.\n'
          'Watch out for: Nothing in these results stands out to flag.',
      generatedAt: DateTime.now().toUtc(),
      model: 'fake-model',
      source: AssistantSource.openRouter,
    );
  }
}
