import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/ui/team_compare_view.dart';

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
  String? tbaMatchKey,
  Map<String, dynamic> fieldValues = const <String, dynamic>{},
}) {
  return ScoutEntry(
    matchId: 'session-uuid',
    teamNumber: team,
    tbaMatchKey: tbaMatchKey,
    fieldValues: fieldValues,
  );
}

Future<ScoutConfigController> _config() async {
  final controller = ScoutConfigController(service: FakeScoutConfigService());
  await controller.bootstrap();
  return controller;
}

Widget _host({
  required ScoutingController scoutingController,
  required ScoutConfigController configController,
  AssistantService? assistant,
}) {
  return MaterialApp(
    home: Scaffold(
      body: TeamCompareView(
        scoutingController: scoutingController,
        configController: configController,
        eventController: EventController(),
        assistant: assistant,
      ),
    ),
  );
}

class _FakeBackend implements AssistantBackend {
  _FakeBackend();

  int calls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    calls++;
    return AssistantSummary(
      text: 'Scores well from the far side, watch for disconnects.',
      generatedAt: DateTime.now().toUtc(),
      model: 'fake-model',
      source: AssistantSource.openRouter,
    );
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('starts with three empty team-number columns', (tester) async {
    final scouting = await _seed(const <ScoutEntry>[]);
    await tester.pumpWidget(
      _host(scoutingController: scouting, configController: await _config()),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Team number'), findsNWidgets(3));
    expect(find.text('Enter a team number to compare.'), findsNWidgets(3));
  });

  testWidgets('typing a team number with no entries says so', (tester) async {
    final scouting = await _seed(const <ScoutEntry>[]);
    await tester.pumpWidget(
      _host(scoutingController: scouting, configController: await _config()),
    );
    await tester.enterText(find.byType(TextField).first, '254');
    await tester.pumpAndSettle();

    expect(find.text('No scout entries for team 254 yet.'), findsOneWidget);
  });

  testWidgets('a scouted team shows its match table and fuel graph', (
    tester,
  ) async {
    final scouting = await _seed([
      _entry(
        254,
        tbaMatchKey: '2026txhou_qm1',
        fieldValues: {
          'starting': 'Depot Trench',
          'autoFuelScored': 5,
          'teleopFuelScored': 30,
        },
      ),
    ]);
    await tester.pumpWidget(
      _host(scoutingController: scouting, configController: await _config()),
    );
    await tester.enterText(find.byType(TextField).first, '254');
    await tester.pumpAndSettle();

    expect(find.text('Team 254'), findsOneWidget);
    expect(find.text('Match 1'), findsOneWidget);
    expect(find.text('Depot Trench'), findsOneWidget);
    expect(find.text('Auto fuel'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
  });

  testWidgets('the other two columns stay untouched', (tester) async {
    final scouting = await _seed([_entry(254, tbaMatchKey: '2026txhou_qm1')]);
    await tester.pumpWidget(
      _host(scoutingController: scouting, configController: await _config()),
    );
    await tester.enterText(find.byType(TextField).first, '254');
    await tester.pumpAndSettle();

    expect(find.text('Enter a team number to compare.'), findsNWidgets(2));
  });

  testWidgets(
    'the AI summary offers a button but does not generate on render',
    (tester) async {
      final backend = _FakeBackend();
      final assistant = AssistantService(
        backends: [backend],
        cache: AssistantCache(),
        minimumGap: Duration.zero,
      );
      final scouting = await _seed([
        _entry(
          254,
          tbaMatchKey: '2026txhou_qm1',
          fieldValues: {'teleopFuelScored': 10},
        ),
      ]);
      await tester.pumpWidget(
        _host(
          scoutingController: scouting,
          configController: await _config(),
          assistant: assistant,
        ),
      );
      await tester.enterText(find.byType(TextField).first, '254');
      await tester.pumpAndSettle();

      expect(find.text('Generate summary'), findsOneWidget);
      expect(backend.calls, 0);

      await tester.ensureVisible(find.text('Generate summary'));
      await tester.tap(find.text('Generate summary'));
      await tester.pumpAndSettle();

      expect(backend.calls, 1);
      expect(
        find.textContaining('Scores well from the far side'),
        findsOneWidget,
      );
    },
  );
}
