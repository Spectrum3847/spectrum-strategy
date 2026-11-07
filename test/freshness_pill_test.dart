import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/models/data_freshness.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/services/pick_list_sync_service.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/pick_list_controller.dart';
import 'package:spectrumstrategy/src/ui/freshness_pill.dart';

import 'support/fake_pick_list_storage.dart';
import 'support/fake_pick_list_sync_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_scouting_sync_service.dart';

final _now = DateTime.utc(2026, 3, 14, 12);

class _FakeStatboticsClient extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async =>
      StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async =>
      <StatboticsTeamEvent>[];

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async =>
      <StatboticsMatch>[];

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async =>
      <StatboticsTeamBasic>[];
}

class _Rig {
  _Rig(this.sync, this.scouting, this.event);
  final FakeScoutingSyncService sync;
  final ScoutingController scouting;
  final EventController event;
}

Future<_Rig> _pump(
  WidgetTester tester, {
  ScoutingSyncStatus status = const ScoutingSyncStatus(
    state: ScoutingSyncState.synced,
  ),
  bool simulateOutage = false,
  int entries = 0,
  PickListSyncState? pickListState,
  double width = 800,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final sync = FakeScoutingSyncService()..simulateOutage = simulateOutage;
  final scouting = ScoutingController(
    storage: FakeScoutingStorage(),
    syncService: sync,
  );
  await scouting.bootstrap();
  for (var i = 0; i < entries; i++) {
    await scouting.saveEntry(ScoutEntry(matchId: 'm$i', teamNumber: 254 + i));
  }
  sync.emitStatus(status);
  await tester.pump();

  final event = EventController(client: _FakeStatboticsClient());
  await event.setEventKey('2026test');

  PickListController? pickLists;
  if (pickListState != null) {
    pickLists = PickListController(
      storage: FakePickListStorage(),
      syncService: FakePickListSyncService(initialState: pickListState),
    );
    await pickLists.bootstrap();
  }

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Spectrum Strategy'),
          actions: [
            FreshnessPill(
              scoutingController: scouting,
              eventController: event,
              pickListController: pickLists,
              clock: () => _now,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Rig(sync, scouting, event);
}

void main() {
  group('pill label', () {
    testWidgets('says how long ago the last sync landed', (tester) async {
      await _pump(
        tester,
        status: ScoutingSyncStatus(
          state: ScoutingSyncState.synced,
          lastSyncedAt: _now.subtract(const Duration(minutes: 5)),
        ),
      );

      expect(find.text('Synced 5m'), findsOneWidget);
    });

    testWidgets('says just synced when it has no time yet', (tester) async {
      await _pump(tester);

      expect(find.text('Synced'), findsOneWidget);
    });

    testWidgets('offline with entries waiting shows the unsynced count', (
      tester,
    ) async {
      await _pump(
        tester,
        status: const ScoutingSyncStatus(state: ScoutingSyncState.offline),
        simulateOutage: true,
        entries: 2,
      );

      expect(find.text('Offline · 2 unsynced'), findsOneWidget);
    });

    testWidgets('signed out reads local only', (tester) async {
      await _pump(
        tester,
        status: const ScoutingSyncStatus(state: ScoutingSyncState.signedOut),
      );

      expect(find.text('Local only'), findsOneWidget);
    });

    testWidgets('a refused write reads sync blocked', (tester) async {
      await _pump(
        tester,
        status: const ScoutingSyncStatus(state: ScoutingSyncState.rejected),
      );

      expect(find.text('Sync blocked'), findsOneWidget);
    });

    testWidgets('a phone-width bar keeps the icon and the count only', (
      tester,
    ) async {
      await _pump(
        tester,
        status: const ScoutingSyncStatus(state: ScoutingSyncState.offline),
        simulateOutage: true,
        entries: 3,
        width: 360,
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.textContaining('Offline'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('Data status: Offline')),
        findsOneWidget,
      );
    });

    testWidgets('the pill is at least 44px tall', (tester) async {
      await _pump(tester);

      final box = tester.getSize(find.byType(FreshnessPill));
      expect(box.height, greaterThanOrEqualTo(44));
    });
  });

  group('sheet', () {
    testWidgets('answers yes and lists each source with its last update', (
      tester,
    ) async {
      await _pump(
        tester,
        status: ScoutingSyncStatus(
          state: ScoutingSyncState.synced,
          lastSyncedAt: _now.subtract(const Duration(minutes: 5)),
        ),
        pickListState: PickListSyncState.synced,
      );

      await tester.tap(find.byType(FreshnessPill));
      await tester.pumpAndSettle();

      expect(find.text('Is my data up to date?'), findsOneWidget);
      expect(find.text('Yes. This device is in sync.'), findsOneWidget);
      expect(find.text('Scouting entries'), findsOneWidget);
      expect(find.text('Updated 5 minutes ago'), findsOneWidget);
      expect(find.text('Event data (TBA, Statbotics)'), findsOneWidget);
      expect(find.text('Pick lists'), findsOneWidget);
    });

    testWidgets('names the entries that have not reached the database', (
      tester,
    ) async {
      await _pump(
        tester,
        status: const ScoutingSyncStatus(state: ScoutingSyncState.offline),
        simulateOutage: true,
        entries: 1,
      );

      await tester.tap(find.byType(FreshnessPill));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('1 scouting entry on this device'),
        findsOneWidget,
      );
    });

    testWidgets('an offline source makes the answer not sure', (tester) async {
      await _pump(tester, pickListState: PickListSyncState.offline);

      await tester.tap(find.byType(FreshnessPill));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not sure.'), findsOneWidget);
      expect(find.textContaining('No connection'), findsOneWidget);
    });

    testWidgets('Sync now asks the scouting service to sync', (tester) async {
      final rig = await _pump(tester);

      await tester.tap(find.byType(FreshnessPill));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sync now'));
      await tester.pump();

      expect(rig.sync.syncNowCalls, 1);
    });
  });

  testWidgets('the event source gets a refresh time from the first fetch', (
    tester,
  ) async {
    final rig = await _pump(tester);

    expect(rig.event.dataFetchedAt, isNotNull);
  });

  group('ages', () {
    test('short and long forms', () {
      final at = _now.subtract(const Duration(hours: 3));
      expect(shortAgo(at, _now), '3h');
      expect(longAgo(at, _now), '3 hours ago');
      expect(shortAgo(_now, _now), 'just now');
      expect(longAgo(null, _now), 'never');
      expect(shortAgo(_now.subtract(const Duration(days: 4)), _now), '4d');
    });
  });
}
