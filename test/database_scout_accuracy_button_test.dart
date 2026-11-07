import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/scouter_opr_fixtures.dart';

class _FakeStatboticsClient extends StatboticsClient {
  @override
  Future<StatboticsEvent?> getEvent(String eventKey) async =>
      StatboticsEvent(key: eventKey, name: 'Test Event', year: 2026);

  @override
  Future<List<StatboticsTeamEvent>> getEventTeams(String eventKey) async =>
      const <StatboticsTeamEvent>[];

  @override
  Future<List<StatboticsMatch>> getEventMatches(String eventKey) async =>
      const <StatboticsMatch>[];

  @override
  Future<List<StatboticsTeamBasic>> getEventTeamsBasic(String eventKey) async =>
      const <StatboticsTeamBasic>[];
}

class _FakeTbaClient extends TbaClient {
  _FakeTbaClient()
    : super(
        config: InMemoryTbaConfig('test-key'),
        httpClient: MockClient((_) async => http.Response('[]', 404)),
      );

  final List<String> detailedRequests = <String>[];

  @override
  Future<List<TbaScheduleMatch>> getEventMatchesDetailed(
    String eventKey,
  ) async {
    detailedRequests.add(eventKey);
    return <TbaScheduleMatch>[
      tbaMatch(1, red: [1, 2, 3], blue: [4, 5, 6], redFuel: 50, blueFuel: 60),
    ];
  }
}

void main() {
  Future<_FakeTbaClient?> pumpTab(
    WidgetTester tester, {
    required bool canEditAnyEntry,
    bool withEvent = true,
    bool withTba = true,
    Size size = const Size(1200, 900),
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tba = withTba ? _FakeTbaClient() : null;
    final event = EventController(
      client: _FakeStatboticsClient(),
      tbaClient: tba,
    );
    if (withEvent) await event.setEventKey('2026txhou');
    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await scouting.bootstrap();
    await config.bootstrap();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatabaseTab(
            scoutingController: scouting,
            configController: config,
            eventController: event,
            canEditAnyEntry: canEditAnyEntry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tba;
  }

  final button = find.widgetWithText(OutlinedButton, 'Scout accuracy');

  testWidgets('leads with an event and a TBA client see the button', (
    tester,
  ) async {
    await pumpTab(tester, canEditAnyEntry: true);

    expect(button, findsOneWidget);
  });

  testWidgets('a scouter does not see the button', (tester) async {
    await pumpTab(tester, canEditAnyEntry: false);

    expect(button, findsNothing);
  });

  testWidgets('no event hides the button', (tester) async {
    await pumpTab(tester, canEditAnyEntry: true, withEvent: false);

    expect(button, findsNothing);
  });

  testWidgets('no TBA client hides the button', (tester) async {
    await pumpTab(tester, canEditAnyEntry: true, withTba: false);

    expect(button, findsNothing);
  });

  testWidgets('the button opens the screen and fetches the event', (
    tester,
  ) async {
    final tba = await pumpTab(tester, canEditAnyEntry: true);

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Scout accuracy'), findsOneWidget);
    expect(find.textContaining('For coaching, not blame'), findsOneWidget);
    expect(tba!.detailedRequests, ['2026txhou']);
  });

  testWidgets('a phone gets it in the actions menu', (tester) async {
    await pumpTab(tester, canEditAnyEntry: true, size: const Size(390, 844));

    expect(button, findsNothing);
    await tester.tap(find.byTooltip('Database actions'));
    await tester.pumpAndSettle();
    expect(find.text('Scout accuracy'), findsOneWidget);

    await tester.tap(find.text('Scout accuracy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('For coaching, not blame'), findsOneWidget);
  });

  testWidgets('a phone scouter gets no menu entry', (tester) async {
    await pumpTab(tester, canEditAnyEntry: false, size: const Size(390, 844));

    await tester.tap(find.byTooltip('Database actions'));
    await tester.pumpAndSettle();

    expect(find.text('Scout accuracy'), findsNothing);
  });
}
