import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'package:spectrumstrategy/src/models/trait_config.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/trait_table_controller.dart';
import 'package:spectrumstrategy/src/ui/trait_table_screen.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_trait_table_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const eventJson = '{"key":"2026txhou","name":"Houston","year":2026}';
  const matchesJson =
      '[{"key":"2026txhou_qm1","event":"2026txhou","match_number":1,'
      '"comp_level":"qm","alliances":{"red":{"team_keys":[3847,254,1678]},'
      '"blue":{"team_keys":[118,2056,33]}}}]';

  Future<http.Response> api(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/event/2026txhou')) {
      return http.Response(eventJson, 200);
    }
    if (path.endsWith('/matches')) {
      return http.Response(matchesJson, 200);
    }
    return http.Response('[]', 200);
  }

  testWidgets('picking a match points the controller at it and draws all six', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final event = EventController(
      statboticsEnabled: true,
      client: StatboticsClient(
        httpClient: MockClient(api),
        sleep: (_) async {},
      ),
    );
    addTearDown(event.dispose);
    await event.setEventKey('2026txhou');

    final sync = FakeTraitTableSyncService();
    final controller = TraitTableController(syncService: sync);
    await controller.bootstrap();
    addTearDown(controller.dispose);

    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TraitTableScreen(
            controller: controller,
            eventController: event,
            scoutingController: scouting,
            configController: config,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Pick a match'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Q1').last);
    await tester.pumpAndSettle();

    expect(sync.watched.last.eventKey, '2026txhou');
    expect(sync.watched.last.matchId, 'qm1');
    for (final team in ['3847', '254', '1678', '118', '2056', '33']) {
      expect(find.text(team), findsOneWidget);
    }
  });

  testWidgets('a failed cell write shows the pill', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final event = EventController(
      statboticsEnabled: true,
      client: StatboticsClient(
        httpClient: MockClient(api),
        sleep: (_) async {},
      ),
    );
    addTearDown(event.dispose);
    await event.setEventKey('2026txhou');

    final sync = FakeTraitTableSyncService();
    final controller = TraitTableController(syncService: sync);
    await controller.bootstrap();
    addTearDown(controller.dispose);

    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TraitTableScreen(
            controller: controller,
            eventController: event,
            scoutingController: scouting,
            configController: config,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Q1').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('not saved'), findsNothing);

    sync.failNextPush = StateError('offline');
    await controller.setCell(
      teamNumber: 254,
      traitKey: TraitConfig.defaults.traits.first.key,
      value: 'plays defense well',
    );
    await tester.pumpAndSettle();

    expect(find.text('1 edit not saved'), findsOneWidget);

    await controller.setCell(
      teamNumber: 254,
      traitKey: TraitConfig.defaults.traits.first.key,
      value: 'still strong',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('not saved'), findsNothing);
  });

  testWidgets('the alliance toggle filters to three teams and labels ours', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final event = EventController(
      statboticsEnabled: true,
      client: StatboticsClient(
        httpClient: MockClient(api),
        sleep: (_) async {},
      ),
    );
    addTearDown(event.dispose);
    await event.setEventKey('2026txhou');
    await event.setMyTeamNumber(3847);

    final sync = FakeTraitTableSyncService();
    final controller = TraitTableController(syncService: sync);
    await controller.bootstrap();
    addTearDown(controller.dispose);

    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TraitTableScreen(
            controller: controller,
            eventController: event,
            scoutingController: scouting,
            configController: config,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Q1').last);
    await tester.pumpAndSettle();

    for (final team in ['3847', '254', '1678', '118', '2056', '33']) {
      expect(find.text(team), findsOneWidget);
    }
    expect(find.text('Our alliance'), findsOneWidget);
    expect(find.text('Their alliance'), findsOneWidget);

    await tester.tap(find.text('Our alliance'));
    await tester.pumpAndSettle();

    for (final team in ['3847', '254', '1678']) {
      expect(find.text(team), findsOneWidget);
    }
    for (final team in ['118', '2056', '33']) {
      expect(find.text(team), findsNothing);
    }

    await tester.tap(find.text('Their alliance'));
    await tester.pumpAndSettle();

    for (final team in ['118', '2056', '33']) {
      expect(find.text(team), findsOneWidget);
    }
    for (final team in ['3847', '254', '1678']) {
      expect(find.text(team), findsNothing);
    }
  });

  testWidgets('falls back to red/blue labels with no team number set', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final event = EventController(
      statboticsEnabled: true,
      client: StatboticsClient(
        httpClient: MockClient(api),
        sleep: (_) async {},
      ),
    );
    addTearDown(event.dispose);
    await event.setEventKey('2026txhou');

    final controller = TraitTableController(
      syncService: FakeTraitTableSyncService(),
    );
    await controller.bootstrap();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TraitTableScreen(
            controller: controller,
            eventController: event,
            scoutingController: ScoutingController(
              storage: FakeScoutingStorage(),
            ),
            configController: ScoutConfigController(
              service: FakeScoutConfigService(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Q1').last);
    await tester.pumpAndSettle();

    expect(find.text('Red alliance'), findsOneWidget);
    expect(find.text('Blue alliance'), findsOneWidget);
    expect(find.text('Our alliance'), findsNothing);
    expect(find.text('Their alliance'), findsNothing);
  });

  testWidgets(
    'falls back to red/blue labels when our team is not in the match',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final event = EventController(
        statboticsEnabled: true,
        client: StatboticsClient(
          httpClient: MockClient(api),
          sleep: (_) async {},
        ),
      );
      addTearDown(event.dispose);
      await event.setEventKey('2026txhou');

      await event.setMyTeamNumber(9999);

      final controller = TraitTableController(
        syncService: FakeTraitTableSyncService(),
      );
      await controller.bootstrap();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TraitTableScreen(
              controller: controller,
              eventController: event,
              scoutingController: ScoutingController(
                storage: FakeScoutingStorage(),
              ),
              configController: ScoutConfigController(
                service: FakeScoutConfigService(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Q1').last);
      await tester.pumpAndSettle();

      expect(find.text('Red alliance'), findsOneWidget);
      expect(find.text('Blue alliance'), findsOneWidget);
    },
  );

  testWidgets('no toggle before a match is picked', (tester) async {
    final event = EventController(
      statboticsEnabled: true,
      client: StatboticsClient(
        httpClient: MockClient(api),
        sleep: (_) async {},
      ),
    );
    addTearDown(event.dispose);
    await event.setEventKey('2026txhou');

    final controller = TraitTableController(
      syncService: FakeTraitTableSyncService(),
    );
    await controller.bootstrap();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TraitTableScreen(
            controller: controller,
            eventController: event,
            scoutingController: ScoutingController(
              storage: FakeScoutingStorage(),
            ),
            configController: ScoutConfigController(
              service: FakeScoutConfigService(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byWidgetPredicate((w) => w is SegmentedButton), findsNothing);
  });

  testWidgets('asks for an event before offering matches', (tester) async {
    final event = EventController(
      statboticsEnabled: true,
      client: StatboticsClient(
        httpClient: MockClient(api),
        sleep: (_) async {},
      ),
    );
    addTearDown(event.dispose);

    final controller = TraitTableController(
      syncService: FakeTraitTableSyncService(),
    );
    await controller.bootstrap();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TraitTableScreen(
            controller: controller,
            eventController: event,
            scoutingController: ScoutingController(
              storage: FakeScoutingStorage(),
            ),
            configController: ScoutConfigController(
              service: FakeScoutConfigService(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Select an event'), findsOneWidget);
  });
}
