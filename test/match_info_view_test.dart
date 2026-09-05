import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/match_info_view.dart';
import 'package:statbotics_client/statbotics_client.dart';

import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';

Future<ScoutingController> _seed(List<ScoutEntry> entries) async {
  final controller = ScoutingController(storage: FakeScoutingStorage());
  await controller.bootstrap();
  for (final entry in entries) {
    await controller.saveEntry(entry);
  }
  return controller;
}

ScoutEntry _entry(
  int team, {
  String match = 'qm1',
  Map<String, dynamic> fieldValues = const <String, dynamic>{},
}) {
  return ScoutEntry(matchId: match, teamNumber: team, fieldValues: fieldValues);
}

const _eventJson = '{"key":"2026txhou","name":"Houston","year":2026}';
const _teamEventsJson =
    '[{"team":3847,"event":"2026txhou","event_name":"Houston",'
    '"team_name":"Spectrum","year":2026,"wins":0,"losses":0,"ties":0,'
    '"epa":null}]';

const _matchesJson =
    '[{"key":"2026txhou_qm1","event":"2026txhou","match_number":1,'
    '"comp_level":"qm","alliances":{"red":{"team_keys":[3847,118,2056]},'
    '"blue":{"team_keys":[254,1323,971]}}},'
    '{"key":"2026txhou_qm2","event":"2026txhou","match_number":2,'
    '"comp_level":"qm","alliances":{"red":{"team_keys":[1,2,3]},'
    '"blue":{"team_keys":[4,5,6]}}}]';

Future<http.Response> _healthyApi(http.Request request) async {
  final path = request.url.path;
  if (path.endsWith('/event/2026txhou')) return http.Response(_eventJson, 200);
  if (path.endsWith('/team_events')) return http.Response(_teamEventsJson, 200);
  if (path.endsWith('/matches')) return http.Response(_matchesJson, 200);
  if (path.endsWith('/teams')) return http.Response('[]', 200);
  return http.Response('not found', 404);
}

Future<EventController> _loadedEventController() async {
  final controller = EventController(
    client: StatboticsClient(
      httpClient: MockClient(_healthyApi),
      sleep: (_) async {},
    ),
    statboticsEnabled: true,
  );
  await controller.setEventKey('2026txhou');
  return controller;
}

Widget _host({
  required EventController eventController,
  required ScoutingController scoutingController,
  required ScoutConfigController configController,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MatchInfoView(
        eventController: eventController,
        scoutingController: scoutingController,
        configController: configController,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<ScoutConfigController> config() async {
    final controller = ScoutConfigController(service: FakeScoutConfigService());
    await controller.bootstrap();
    return controller;
  }

  testWidgets('shows an empty state with no team number set', (tester) async {
    final eventController = await _loadedEventController();
    final scouting = await _seed(const <ScoutEntry>[]);

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: scouting,
        configController: await config(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No team number set'), findsOneWidget);
  });

  testWidgets('lists a match with the pre-match and opponents tables', (
    tester,
  ) async {
    final eventController = await _loadedEventController();
    await eventController.setMyTeamNumber(3847);
    final scouting = await _seed([
      _entry(118, fieldValues: {'teleopFuelScored': 10}),
    ]);

    await tester.pumpWidget(
      _host(
        eventController: eventController,
        scoutingController: scouting,
        configController: await config(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pre-match'), findsOneWidget);
    expect(find.text('Opponents'), findsOneWidget);

    expect(find.text('118'), findsOneWidget);
    expect(find.text('2056'), findsOneWidget);
    expect(find.text('254'), findsOneWidget);
    expect(find.text('1323'), findsOneWidget);
    expect(find.text('971'), findsOneWidget);
    expect(find.text('3847'), findsNothing);

    expect(find.textContaining('Q1'), findsOneWidget);
    expect(find.textContaining('Q2'), findsNothing);
  });
}
