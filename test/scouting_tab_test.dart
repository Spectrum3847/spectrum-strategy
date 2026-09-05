import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/scouting/services/scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/ui/scouting_tab.dart';

import 'support/fake_match_directory.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_scouting_sync_service.dart';

const _testEventKey = '2026test';

Future<ScoutingController> _pumpTab(
  WidgetTester tester, {
  ScoutingSyncService? syncService,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final strategy = StrategyController(directory: FakeMatchDirectory());
  final scouting = ScoutingController(
    storage: FakeScoutingStorage(),
    syncService: syncService,
  );
  final config = ScoutConfigController(service: FakeScoutConfigService());
  final event = EventController(
    statboticsEnabled: true,
    client: _FakeStatboticsClient(),
  );

  await Future.wait(<Future<void>>[
    strategy.bootstrap(),
    scouting.bootstrap(),
    config.bootstrap(),
    event.setEventKey(_testEventKey),
  ]);

  await tester.pumpWidget(
    MaterialApp(
      home: ScoutingTab(
        strategyController: strategy,
        scoutingController: scouting,
        configController: config,
        eventController: event,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return scouting;
}

Future<ScoutingController> _pumpTabAndSaveEntry(WidgetTester tester) async {
  final scouting = await _pumpTab(tester);

  await tester.enterText(
    find.byKey(const ValueKey<String>('scout-field-matchNumber')),
    '1',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('scout-field-pTnumber')),
    '3847',
  );
  await tester.pumpAndSettle();

  await tester.drag(find.byType(ListView), const Offset(0, -3200));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Save entry'));
  await tester.pumpAndSettle();

  return scouting;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('save entry resolves tbaMatchKey for quarterfinal match', (
    tester,
  ) async {
    final scouting = await _pumpTabAndSaveEntry(tester);

    expect(scouting.entries, hasLength(1));
    expect(scouting.entries.single.teamNumber, 3847);
    expect(scouting.entries.single.tbaMatchKey, '${_testEventKey}_qf1m1');
  });

  testWidgets('deleting an entry asks for confirmation first', (tester) async {
    final scouting = await _pumpTabAndSaveEntry(tester);
    expect(scouting.entries, hasLength(1));

    Future<void> tapDelete() async {
      final icon = find.byIcon(Icons.delete_outline_rounded);
      await tester.ensureVisible(icon);
      await tester.pumpAndSettle();
      await tester.tap(icon);
      await tester.pumpAndSettle();
    }

    await tapDelete();
    expect(find.text('Delete entry?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(scouting.entries, hasLength(1));

    await tapDelete();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(scouting.entries, isEmpty);
  });

  testWidgets('sync status pill names each connection state', (tester) async {
    await _pumpTab(
      tester,
      syncService: FakeScoutingSyncService(
        initialState: ScoutingSyncState.signedOut,
      ),
    );
    expect(find.text('Not signed in to sync'), findsOneWidget);

    await _pumpTab(
      tester,
      syncService: FakeScoutingSyncService(
        initialState: ScoutingSyncState.noAccess,
      ),
    );
    expect(find.text('No team access yet'), findsOneWidget);

    await _pumpTab(
      tester,
      syncService: FakeScoutingSyncService(
        initialState: ScoutingSyncState.offline,
      ),
    );
    expect(find.text('Offline'), findsOneWidget);
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
    return <StatboticsMatch>[
      StatboticsMatch(
        key: '${eventKey}_qf1m1',
        event: eventKey,
        matchNumber: 1,
        compLevel: 'qf',
        redTeams: const <int>[3847, 2714, 245],
        blueTeams: const <int>[33, 67, 111],
      ),
    ];
  }

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async {
    return const <StatboticsTeamBasic>[];
  }
}
