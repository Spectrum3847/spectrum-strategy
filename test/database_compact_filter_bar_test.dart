import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_scouting_sync_service.dart';

void main() {
  Future<FakeScoutingSyncService> pumpTab(
    WidgetTester tester, {
    required Size size,
    List<ScoutEntry> entries = const <ScoutEntry>[],
    bool canEditAnyEntry = true,
    double textScale = 1.0,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final sync = FakeScoutingSyncService();
    final scouting = ScoutingController(
      storage: FakeScoutingStorage(),
      syncService: sync,
    );
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await scouting.bootstrap();
    await config.bootstrap();
    for (final ScoutEntry entry in entries) {
      await scouting.saveEntry(entry);
    }
    final event = EventController(client: _FakeStatboticsClient());

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: DatabaseTab(
                scoutingController: scouting,
                configController: config,
                eventController: event,
                canEditAnyEntry: canEditAnyEntry,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return sync;
  }

  ScoutEntry entry({required int team, required String match}) {
    return ScoutEntry(
      matchId: 'session-$team-$match',
      teamNumber: team,
      tbaMatchKey: '2026txhou_qm$match',
      fieldValues: <String, dynamic>{'pTnumber': team},
    );
  }

  const Size phone = Size(390, 844);
  const Size tablet = Size(1200, 1600);

  group('parseDatabaseSearch', () {
    test('bare digits are a team', () {
      expect(parseDatabaseSearch('3847'), (team: '3847', match: ''));
    });

    test('a q, m or # token is a match', () {
      expect(parseDatabaseSearch('q42'), (team: '', match: '42'));
      expect(parseDatabaseSearch('m42'), (team: '', match: '42'));
      expect(parseDatabaseSearch('#42'), (team: '', match: '42'));
    });

    test('a match marker separated by a space still binds to its number', () {
      expect(parseDatabaseSearch('q 42'), (team: '', match: '42'));
    });

    test('a team and a match can be typed together, in either order', () {
      expect(parseDatabaseSearch('3847 q42'), (team: '3847', match: '42'));
      expect(parseDatabaseSearch('q42 3847'), (team: '3847', match: '42'));
    });

    test('text that parses as neither filter is ignored', () {
      expect(parseDatabaseSearch('hello'), (team: '', match: ''));
      expect(parseDatabaseSearch(''), (team: '', match: ''));
    });

    test('the text form round-trips what the two fields hold', () {
      expect(databaseSearchText(team: '3847', match: '42'), '3847 q42');
      expect(databaseSearchText(team: '3847', match: ''), '3847');
      expect(databaseSearchText(team: '', match: ''), '');
      expect(
        parseDatabaseSearch(databaseSearchText(team: '3847', match: '42')),
        (team: '3847', match: '42'),
      );
    });
  });

  testWidgets('a phone gets one filter row, not two labelled fields', (
    tester,
  ) async {
    await pumpTab(
      tester,
      size: phone,
      entries: [entry(team: 100, match: '1')],
    );

    expect(find.text('Filter by team'), findsNothing);
    expect(find.text('Filter by match'), findsNothing);
    expect(find.text('Team or q42'), findsOneWidget);

    expect(find.text('Export CSV'), findsNothing);
    expect(find.byTooltip('Refresh from database'), findsNothing);
    expect(find.byTooltip('Database actions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the first data row sits near the top of a phone screen', (
    tester,
  ) async {
    await pumpTab(
      tester,
      size: phone,
      entries: [entry(team: 100, match: '1')],
    );

    expect(tester.getRect(find.text('100')).top, lessThan(115));
  });

  testWidgets('a sync state that is not quiet keeps its whole line', (
    tester,
  ) async {
    final FakeScoutingSyncService sync = await pumpTab(
      tester,
      size: phone,
      entries: [entry(team: 100, match: '1')],
    );

    sync.emitStatus(const ScoutingSyncStatus(state: ScoutingSyncState.offline));
    await tester.pumpAndSettle();

    expect(find.text('Offline, showing cached entries'), findsOneWidget);
  });

  testWidgets('typing a team filters the table and shows a chip', (
    tester,
  ) async {
    await pumpTab(
      tester,
      size: phone,
      entries: [
        entry(team: 100, match: '1'),
        entry(team: 200, match: '1'),
      ],
    );

    await tester.enterText(find.byType(TextField), '200');
    await tester.pumpAndSettle();

    expect(find.text('100'), findsNothing);
    expect(find.text('200'), findsWidgets);

    expect(find.widgetWithText(InputChip, 'Team 200'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear Team 200'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'Team 200'), findsNothing);
    expect(find.text('100'), findsWidgets);
  });

  testWidgets('a q-prefixed number filters by match', (tester) async {
    await pumpTab(
      tester,
      size: phone,
      entries: [
        entry(team: 100, match: '42'),
        entry(team: 200, match: '43'),
      ],
    );

    await tester.enterText(find.byType(TextField), 'q43');
    await tester.pumpAndSettle();

    expect(find.text('100'), findsNothing);
    expect(find.text('200'), findsWidgets);
    expect(find.widgetWithText(InputChip, 'Match 43'), findsOneWidget);
  });

  testWidgets('a non-default row order is a chip that clears itself', (
    tester,
  ) async {
    await pumpTab(
      tester,
      size: phone,
      entries: [entry(team: 100, match: '1')],
    );

    expect(find.byType(InputChip), findsNothing);

    await tester.tap(find.byTooltip('Row order: Match 1 first'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(PopupMenuItem<EntryOrder>, 'Newest first'),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'Newest first'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear Newest first'));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets('a tablet keeps both labelled fields and the export button', (
    tester,
  ) async {
    await pumpTab(
      tester,
      size: tablet,
      entries: [entry(team: 100, match: '1')],
    );

    expect(find.text('Filter by team'), findsOneWidget);
    expect(find.text('Filter by match'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.byTooltip('Refresh from database'), findsOneWidget);
    expect(find.text('Team or q42'), findsNothing);
  });

  testWidgets('a filter typed on a tablet survives narrowing to a phone', (
    tester,
  ) async {
    await pumpTab(
      tester,
      size: tablet,
      entries: [
        entry(team: 100, match: '1'),
        entry(team: 200, match: '1'),
      ],
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Filter by team'),
      '200',
    );
    await tester.pumpAndSettle();

    tester.view.physicalSize = phone;
    await tester.pumpAndSettle();

    expect(find.text('100'), findsNothing);
    expect(find.widgetWithText(InputChip, 'Team 200'), findsOneWidget);
    final TextField search = tester.widget<TextField>(find.byType(TextField));
    expect(search.controller?.text, '200');
  });

  testWidgets('a phone at 200% text does not overflow', (tester) async {
    await pumpTab(
      tester,
      size: phone,
      entries: [entry(team: 100, match: '1')],
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Database actions'), findsOneWidget);
  });
}

class _FakeStatboticsClient extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async {
    return StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);
  }

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async {
    return const <StatboticsTeamEvent>[];
  }

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async {
    return const <StatboticsMatch>[];
  }

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async {
    return const <StatboticsTeamBasic>[];
  }
}
