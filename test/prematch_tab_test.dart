import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/playoff_board_controller.dart';
import 'package:spectrumstrategy/src/state/event_sections_controller.dart';
import 'package:spectrumstrategy/src/state/post_match_report_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';
import 'package:spectrumstrategy/src/ui/glass_chrome.dart';
import 'package:spectrumstrategy/src/ui/prematch_tab.dart';

import 'support/fake_post_match_report_storage.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_playoff_board_storage.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

const _testEventKey = '2026test';

Future<EventController> _pumpTab(
  WidgetTester tester, {
  EventSectionsController? sections,
  StatboticsClient? client,

  bool glass = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  if (glass) {
    tester.view.padding = const FakeViewPadding(bottom: 40);
  }
  addTearDown(tester.view.reset);

  final event = EventController(client: client ?? _FakeStatboticsClient());
  await event.setEventKey(_testEventKey);

  await tester.pumpWidget(
    MaterialApp(
      home: GlassChrome(
        enabled: glass,
        child: Scaffold(
          body: PrematchTab(
            eventController: event,
            scoutingController: ScoutingController(
              storage: FakeScoutingStorage(),
            ),
            configController: ScoutConfigController(
              service: FakeScoutConfigService(),
            ),
            playoffBoardController: PlayoffBoardController(
              storage: FakePlayoffBoardStorage(),
            ),
            eventSectionsController: sections,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return event;
}

Finder _glassInsetPadding(Finder descendant, double inset) => find.ancestor(
  of: descendant,
  matching: find.byWidgetPredicate(
    (w) => w is Padding && w.padding.resolve(TextDirection.ltr).bottom == inset,
  ),
);

class _MatchesTbaClient extends TbaClient {
  _MatchesTbaClient() : super(config: InMemoryTbaConfig('test-key'));

  @override
  Future<List<TbaScheduleMatch>> getEventMatches(String eventKey) async {
    return <TbaScheduleMatch>[
      TbaScheduleMatch.fromJson(<String, dynamic>{
        'key': '${_testEventKey}_qm1',
        'comp_level': 'qm',
        'match_number': 1,
        'winning_alliance': 'blue',
        'alliances': <String, dynamic>{
          'red': <String, dynamic>{
            'team_keys': <dynamic>['frc3847'],
            'score': 61,
          },
          'blue': <String, dynamic>{
            'team_keys': <dynamic>['frc971'],
            'score': 78,
          },
        },
      }),
    ];
  }
}

void main() {
  testWidgets('match results reach the rows after the schedule renders', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final sections = EventSectionsController(tbaClient: _MatchesTbaClient());
    addTearDown(sections.dispose);
    await sections.bootstrap();
    await sections.toggle(EventSection.matchResults);

    await _pumpTab(tester, sections: sections);
    await tester.pumpAndSettle();

    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('61'), findsOneWidget);
    expect(find.text('78'), findsOneWidget);
  });

  testWidgets('defaults to the TBA sub-tab and shows the match schedule', (
    tester,
  ) async {
    await _pumpTab(tester);

    expect(find.text('Statbotics'), findsOneWidget);
    expect(find.text('TBA'), findsOneWidget);
    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('Q2'), findsOneWidget);
    expect(
      find.text(
        'Ranked by EPA, joined with your scouting. Tap a scouted '
        'team for its breakdown. Pull to refresh.',
      ),
      findsNothing,
      reason: 'the EPA team list is behind the Statbotics segment by default',
    );
  });

  testWidgets('switching to Statbotics shows the EPA-ranked team list', (
    tester,
  ) async {
    await _pumpTab(tester);

    await tester.tap(find.text('Statbotics'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Ranked by EPA, joined with your scouting. Tap a scouted '
        'team for its breakdown. Pull to refresh.',
      ),
      findsOneWidget,
    );
    expect(find.text('3847'), findsOneWidget);
    expect(find.text('971'), findsOneWidget);
    expect(find.text('Q1'), findsNothing);
  });

  testWidgets('switching back to TBA shows the schedule again', (tester) async {
    await _pumpTab(tester);

    await tester.tap(find.text('Statbotics'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Ranked by EPA, joined with your scouting. Tap a scouted '
        'team for its breakdown. Pull to refresh.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('TBA'));
    await tester.pumpAndSettle();

    expect(find.text('Q1'), findsOneWidget);
    expect(
      find.text(
        'Ranked by EPA, joined with your scouting. Tap a scouted '
        'team for its breakdown. Pull to refresh.',
      ),
      findsNothing,
    );
  });

  testWidgets(
    'TBA sub-tab shows an empty state when the event has no matches',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final event = EventController(client: _EmptyScheduleStatboticsClient());
      await event.setEventKey(_testEventKey);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrematchTab(
              eventController: event,
              scoutingController: ScoutingController(
                storage: FakeScoutingStorage(),
              ),
              configController: ScoutConfigController(
                service: FakeScoutConfigService(),
              ),
              playoffBoardController: PlayoffBoardController(
                storage: FakePlayoffBoardStorage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No schedule for'), findsOneWidget);
    },
  );

  testWidgets('TBA sub-tab shows a spinner while the schedule is loading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final gate = Completer<void>();
    final event = EventController(client: _SlowStatboticsClient(gate.future));
    final loadFuture = event.setEventKey(_testEventKey);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrematchTab(
            eventController: event,
            scoutingController: ScoutingController(
              storage: FakeScoutingStorage(),
            ),
            playoffBoardController: PlayoffBoardController(
              storage: FakePlayoffBoardStorage(),
            ),
            configController: ScoutConfigController(
              service: FakeScoutConfigService(),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await loadFuture;
    await tester.pumpAndSettle();
  });

  group('unified destination bar', () {
    Future<void> revealDestination(
      WidgetTester tester,
      String label, {
      double delta = 120,
    }) async {
      await tester.scrollUntilVisible(
        find.text(label),
        delta,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
            )
            .first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('all four destinations are reachable from the one bar', (
      tester,
    ) async {
      await _pumpTab(tester);

      for (final label in const <String>[
        'Statbotics',
        'TBA',
        'Ranking',
        'Playoff',
      ]) {
        await revealDestination(tester, label);
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
      expect(find.text('Pick lists'), findsNothing);
    });

    testWidgets('Traits is not one of the destinations', (tester) async {
      await _pumpTab(tester);

      expect(find.text('Traits'), findsNothing);
    });

    testWidgets('the destinations bring in no nested Scaffold or AppBar', (
      tester,
    ) async {
      await _pumpTab(tester);

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('Post match appears once a controller is wired', (
      tester,
    ) async {
      final controller = await _pumpTabWithPostMatch(tester);

      await revealDestination(tester, 'Post match');
      expect(find.text('Post match'), findsOneWidget);
      await tester.tap(find.text('Post match'));
      await tester.pumpAndSettle();

      expect(
        find.text('No post match reports for this event yet.'),
        findsOneWidget,
      );

      controller.dispose();
    });

    testWidgets('Post match disappears when the shell has no controller', (
      tester,
    ) async {
      await _pumpTab(tester);

      expect(find.text('Post match'), findsNothing);
    });

    testWidgets('switching away from a destination and back keeps its state', (
      tester,
    ) async {
      await _pumpTab(tester);

      final schedule = find.byType(Scrollable).last;
      await tester.drag(schedule, const Offset(0, -120));
      await tester.pumpAndSettle();
      final offset = tester.state<ScrollableState>(schedule).position.pixels;
      expect(offset, greaterThan(0));

      await revealDestination(tester, 'Ranking');
      await tester.tap(find.text('Ranking'));
      await tester.pumpAndSettle();

      await revealDestination(tester, 'TBA', delta: -120);
      await tester.tap(find.text('TBA'));
      await tester.pumpAndSettle();

      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).last)
            .position
            .pixels,
        offset,
        reason: 'the schedule was rebuilt, so the stack is not holding state',
      );
    });

    testWidgets('each event lens renders its own body, not the selected one', (
      tester,
    ) async {
      await _pumpTab(tester);

      expect(find.text('Q1'), findsOneWidget);
      await tester.tap(find.text('Statbotics'));
      await tester.pumpAndSettle();

      expect(find.text('3847'), findsWidgets);
      expect(
        find.text('Q1', skipOffstage: false),
        findsOneWidget,
        reason: 'the TBA slot lost its schedule when Statbotics was selected',
      );

      expect(find.text('Q1'), findsNothing);
    });
  });

  group('Match prediction destination', () {
    Future<void> revealDestination(
      WidgetTester tester,
      String label, {
      double delta = 120,
    }) async {
      await tester.scrollUntilVisible(
        find.text(label),
        delta,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
            )
            .first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is reachable from the destination bar', (tester) async {
      await _pumpTab(tester);

      await revealDestination(tester, 'Prediction');
      await tester.tap(find.text('Prediction'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Enter all three teams for each alliance'),
        findsOneWidget,
      );
    });

    testWidgets('a scouted alliance shows a predicted total', (tester) async {
      final scouting = ScoutingController(storage: FakeScoutingStorage());
      await scouting.bootstrap();

      await scouting.saveEntry(
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 3847,
          fieldValues: const {'autoFuelScored': 2, 'teleopFuelScored': 5},
        ),
      );
      await scouting.saveEntry(
        ScoutEntry(
          matchId: 'qm1',
          teamNumber: 1,
          fieldValues: const {'autoFuelScored': 3, 'teleopFuelScored': 4},
        ),
      );

      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final event = EventController(client: _FakeStatboticsClient());
      await event.setEventKey(_testEventKey);

      final config = ScoutConfigController(service: FakeScoutConfigService());
      await config.bootstrap();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrematchTab(
              eventController: event,
              scoutingController: scouting,
              configController: config,
              playoffBoardController: PlayoffBoardController(
                storage: FakePlayoffBoardStorage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await revealDestination(tester, 'Prediction');
      await tester.tap(find.text('Prediction'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(1), '3847');
      await tester.enterText(find.byType(TextField).at(2), '1');
      await tester.enterText(find.byType(TextField).at(3), '2');
      await tester.enterText(find.byType(TextField).at(4), '4');
      await tester.enterText(find.byType(TextField).at(5), '5');
      await tester.enterText(find.byType(TextField).at(6), '6');
      await tester.pumpAndSettle();

      expect(find.text('14'), findsOneWidget);
    });
  });

  group('team analysis reached from the team list (#1687)', () {
    Future<ScoutingController> readyScoutingWithNotes() async {
      final controller = ScoutingController(storage: FakeScoutingStorage());
      await controller.bootstrap();

      for (var i = 0; i < 4; i++) {
        await controller.saveEntry(
          ScoutEntry(
            matchId: 'qm$i',
            teamNumber: 3847,
            notes: 'Scouted note number $i about team 3847',
          ),
        );
      }
      return controller;
    }

    Future<UserRoleController> rolesFor(Set<UserRole> roles) async {
      const user = SpectrumUser(uid: 'test-uid', displayName: 'Test');
      final roleService = FakeUserRoleService()..setRoles('test-uid', roles);
      final controller = UserRoleController(
        authService: FakeSpectrumAuthService(initialUser: user),
        roleService: roleService,
      );
      await controller.bootstrap();
      return controller;
    }

    Future<void> pumpAndOpenTeamAnalysis(
      WidgetTester tester, {
      required ScoutingController scoutingController,
      UserRoleController? userRoleController,
      bool viaRanking = false,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final event = EventController(client: _FakeStatboticsClient());
      await event.setEventKey(_testEventKey);
      final assistant = AssistantService(
        backends: [_FakeAssistantBackend()],
        cache: AssistantCache(),
        minimumGap: Duration.zero,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrematchTab(
              eventController: event,
              scoutingController: scoutingController,
              configController: ScoutConfigController(
                service: FakeScoutConfigService(),
              ),
              playoffBoardController: PlayoffBoardController(
                storage: FakePlayoffBoardStorage(),
              ),
              assistant: assistant,
              userRoleController: userRoleController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (viaRanking) {
        await tester.scrollUntilVisible(
          find.text('Ranking'),
          120,
          scrollable: find
              .byWidgetPredicate(
                (w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.right,
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ranking'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('3847'));
        await tester.pumpAndSettle();
        return;
      }

      await tester.tap(find.text('Statbotics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spectrum'));
      await tester.pumpAndSettle();
    }

    testWidgets('a strategy lead gets "Summarise the comments" the same as the '
        'Database tab', (tester) async {
      final scouting = await readyScoutingWithNotes();
      final roles = await rolesFor(<UserRole>{UserRole.strategy});

      await pumpAndOpenTeamAnalysis(
        tester,
        scoutingController: scouting,
        userRoleController: roles,
      );

      expect(find.text('Team 3847'), findsOneWidget);
      expect(find.text('Summarise the comments'), findsOneWidget);
    });

    testWidgets(
      'a scouter (cannot publish) does not get "Summarise the comments"',
      (tester) async {
        final scouting = await readyScoutingWithNotes();
        final roles = await rolesFor(<UserRole>{UserRole.scouter});

        await pumpAndOpenTeamAnalysis(
          tester,
          scoutingController: scouting,
          userRoleController: roles,
        );

        expect(find.text('Team 3847'), findsOneWidget);
        expect(find.text('Summarise the comments'), findsNothing);
        expect(
          find.text(
            '4 comments on this team. No summary yet. A strategy lead '
            'can write one.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'no signed-in role defaults to false, matching TeamAnalysisScreen and '
      "CommentDigestCard's own defaults",
      (tester) async {
        final scouting = await readyScoutingWithNotes();

        await pumpAndOpenTeamAnalysis(tester, scoutingController: scouting);

        expect(find.text('Team 3847'), findsOneWidget);
        expect(find.text('Summarise the comments'), findsNothing);
      },
    );

    testWidgets(
      'a strategy lead gets "Summarise the comments" from Ranking too',
      (tester) async {
        final scouting = await readyScoutingWithNotes();
        final roles = await rolesFor(<UserRole>{UserRole.strategy});

        await pumpAndOpenTeamAnalysis(
          tester,
          scoutingController: scouting,
          userRoleController: roles,
          viaRanking: true,
        );

        expect(find.text('Team 3847'), findsOneWidget);
        expect(find.text('Summarise the comments'), findsOneWidget);
      },
    );

    testWidgets(
      'a scouter (cannot publish) does not get "Summarise the comments" '
      'from Ranking either',
      (tester) async {
        final scouting = await readyScoutingWithNotes();
        final roles = await rolesFor(<UserRole>{UserRole.scouter});

        await pumpAndOpenTeamAnalysis(
          tester,
          scoutingController: scouting,
          userRoleController: roles,
          viaRanking: true,
        );

        expect(find.text('Team 3847'), findsOneWidget);
        expect(find.text('Summarise the comments'), findsNothing);
        expect(
          find.text(
            '4 comments on this team. No summary yet. A strategy lead '
            'can write one.',
          ),
          findsOneWidget,
        );
      },
    );
  });
  testWidgets(
    'the bottom inset sits outside the scrollable, not laid out under '
    'it, on the TBA schedule and the EPA-ranked team list',
    (tester) async {
      await _pumpTab(tester, glass: true);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

      final schedule = find.ancestor(
        of: find.text('Q1'),
        matching: find.byType(CustomScrollView),
      );
      final scheduleRefresh = find.ancestor(
        of: schedule,
        matching: find.byType(RefreshIndicator),
      );
      expect(scheduleRefresh, findsOneWidget);

      expect(_glassInsetPadding(scheduleRefresh, 40), findsOneWidget);
      expect(
        find.descendant(
          of: scheduleRefresh,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Padding &&
                w.padding.resolve(TextDirection.ltr).bottom == 40,
          ),
        ),
        findsNothing,
        reason:
            'the inset must not sit between RefreshIndicator and the '
            'scrollable it wraps',
      );
      expect(
        tester.getRect(schedule).bottom,
        closeTo(screen.height - 40, 0.5),
        reason: 'the schedule stops short of the reserved strip',
      );

      await tester.tap(find.text('Statbotics'));
      await tester.pumpAndSettle();

      final epaText = find.text(
        'Ranked by EPA, joined with your scouting. Tap a '
        'scouted team for its breakdown. Pull to refresh.',
      );
      final epaList = find.ancestor(
        of: epaText,
        matching: find.byType(ListView),
      );
      final epaRefresh = find.ancestor(
        of: epaList,
        matching: find.byType(RefreshIndicator),
      );
      expect(epaRefresh, findsOneWidget);
      expect(_glassInsetPadding(epaRefresh, 40), findsOneWidget);
      expect(
        find.descendant(
          of: epaRefresh,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Padding &&
                w.padding.resolve(TextDirection.ltr).bottom == 40,
          ),
        ),
        findsNothing,
      );
      expect(tester.getRect(epaList).bottom, closeTo(screen.height - 40, 0.5));
    },
  );

  testWidgets(
    'pull-to-refresh on the TBA schedule still reaches EventController.refresh',
    (tester) async {
      final client = _CountingStatboticsClient();
      await _pumpTab(tester, glass: true, client: client);
      final loadedCalls = client.matchesCalls;

      final schedule = find.ancestor(
        of: find.text('Q1'),
        matching: find.byType(CustomScrollView),
      );
      final refresh = find.ancestor(
        of: schedule,
        matching: find.byType(RefreshIndicator),
      );

      await tester.widget<RefreshIndicator>(refresh).onRefresh();

      expect(client.matchesCalls, greaterThan(loadedCalls));
    },
  );
}

class _FakeAssistantBackend implements AssistantBackend {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    throw const AssistantUnavailable('test backend never generates');
  }
}

Future<PostMatchReportController> _pumpTabWithPostMatch(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final event = EventController(client: _FakeStatboticsClient());
  await event.setEventKey(_testEventKey);

  final postMatchReport = PostMatchReportController(
    storage: FakePostMatchReportStorage(),
  );
  await postMatchReport.bootstrap();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PrematchTab(
          eventController: event,
          scoutingController: ScoutingController(
            storage: FakeScoutingStorage(),
          ),
          configController: ScoutConfigController(
            service: FakeScoutConfigService(),
          ),
          playoffBoardController: PlayoffBoardController(
            storage: FakePlayoffBoardStorage(),
          ),
          postMatchReportController: postMatchReport,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return postMatchReport;
}

class _EmptyScheduleStatboticsClient extends _FakeStatboticsClient {
  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    return const <StatboticsMatch>[];
  }
}

class _CountingStatboticsClient extends _FakeStatboticsClient {
  int matchesCalls = 0;

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    matchesCalls++;
    return super.getEventMatches(eventKey);
  }
}

class _SlowStatboticsClient extends _FakeStatboticsClient {
  _SlowStatboticsClient(this._gate);

  final Future<void> _gate;

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    await _gate;
    return super.getEventMatches(eventKey);
  }
}

class _FakeStatboticsClient extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async {
    return StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);
  }

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async {
    return <StatboticsTeamEvent>[
      StatboticsTeamEvent(
        team: 3847,
        event: eventKey,
        eventName: 'Test Event',

        teamName: 'Spectrum',
        year: 2026,
        wins: 2,
        losses: 0,
        ties: 0,
        epa: StatboticsEpa.empty,
      ),
      StatboticsTeamEvent(
        team: 971,
        event: eventKey,
        eventName: 'Test Event',
        year: 2026,
        wins: 1,
        losses: 1,
        ties: 0,
        epa: StatboticsEpa.empty,
      ),
    ];
  }

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    return <StatboticsMatch>[
      StatboticsMatch(
        key: '${eventKey}_qm1',
        event: eventKey,
        matchNumber: 1,
        compLevel: 'qm',
        redTeams: const <int>[3847, 118, 2056],
        blueTeams: const <int>[971, 1323, 33],
      ),
      StatboticsMatch(
        key: '${eventKey}_qm2',
        event: eventKey,
        matchNumber: 2,
        compLevel: 'qm',
        redTeams: const <int>[254, 118, 1323],
        blueTeams: const <int>[971, 2056, 33],
      ),

      for (var number = 3; number <= 60; number++)
        StatboticsMatch(
          key: '${eventKey}_qm$number',
          event: eventKey,
          matchNumber: number,
          compLevel: 'qm',
          redTeams: const <int>[254, 118, 1323],
          blueTeams: const <int>[971, 2056, 33],
        ),
      StatboticsMatch(
        key: '${eventKey}_f1m1',
        event: eventKey,
        matchNumber: 1,
        compLevel: 'f',
        redTeams: const <int>[3847, 971, 118],
        blueTeams: const <int>[254, 1323, 2056],
      ),
    ];
  }

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async {
    return <StatboticsTeamBasic>[
      StatboticsTeamBasic(team: 3847, nickname: 'Spectrum'),
      StatboticsTeamBasic(team: 254, nickname: 'The Cheesy Poofs'),
    ];
  }
}
