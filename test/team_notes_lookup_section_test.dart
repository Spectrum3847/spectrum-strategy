import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/models/trex_trait_report.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/state/trex_trait_report_controller.dart';
import 'package:spectrumstrategy/src/ui/team_notes_lookup_section.dart';

import 'support/fake_pit_scout_config_service.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_trex_trait_report_storage.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const drivetrainField = ScoutConfigField(
    title: 'Drivetrain',
    type: ScoutFieldType.text,
    code: 'drivetrain',
  );
  const pitConfig = ScoutConfig(
    title: 'Pit',

    revision: 999,
    sections: [
      ScoutConfigSection(name: 'Robot', fields: [drivetrainField]),
    ],
  );

  testWidgets('shows a prompt to type a team number until one is typed', (
    tester,
  ) async {
    final scouting = await _scoutingController();
    await _pump(tester, scoutingController: scouting);

    expect(find.text('No notes recorded for team 3847 yet.'), findsNothing);
    expect(find.widgetWithText(TextField, 'Team number'), findsOneWidget);
  });

  testWidgets('says so when a team has no notes at all', (tester) async {
    final scouting = await _scoutingController();
    await _pump(tester, scoutingController: scouting);

    await tester.enterText(find.byType(TextField), '3847');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('No notes recorded for team 3847 yet.'), findsOneWidget);
  });

  testWidgets('shows a match scouting comment for the typed team', (
    tester,
  ) async {
    final scouting = await _scoutingController([
      ScoutEntry(
        matchId: 'qm12',
        teamNumber: 3847,
        notes: 'tipped over reaching for the bar',
        authorDisplayName: 'scouter one',
      ),
    ]);
    await _pump(tester, scoutingController: scouting);

    await tester.enterText(find.byType(TextField), '3847');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('tipped over reaching for the bar'),
      findsOneWidget,
    );
    expect(find.textContaining('qm12'), findsOneWidget);
  });

  testWidgets('shows a pit scouting answer for the typed team', (tester) async {
    final scouting = await _scoutingController();
    final pit = await _pitScoutingController();
    await pit.saveEntry(
      PitScoutEntry(
        teamNumber: 3847,
        fieldValues: const {'drivetrain': 'Swerve'},
      ),
    );
    final pitConfigController = await _pitConfigController(pitConfig);

    await _pump(
      tester,
      scoutingController: scouting,
      pitScoutingController: pit,
      pitScoutConfigController: pitConfigController,
    );

    await tester.enterText(find.byType(TextField), '3847');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.textContaining('Pit scouting: Drivetrain'), findsOneWidget);
    expect(find.textContaining('Swerve'), findsOneWidget);
  });

  testWidgets('shows a T-Rex trait report for the typed team', (tester) async {
    final scouting = await _scoutingController();
    final trex = await _trexController();
    await trex.submitReport(
      TrexTraitReport(
        trait: 'defense',
        teamNumber: 3847,
        matchNumber: 12,
        report: 'plays defense from the far side',
        updatedAt: DateTime.utc(2026, 8, 1),
      ),
    );

    await _pump(
      tester,
      scoutingController: scouting,
      trexTraitReportController: trex,
    );

    await tester.enterText(find.byType(TextField), '3847');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.textContaining('T-Rex: Defense'), findsOneWidget);
    expect(
      find.textContaining('plays defense from the far side'),
      findsOneWidget,
    );
  });

  testWidgets('generates a summary once there are enough notes', (
    tester,
  ) async {
    final scouting = await _scoutingController([
      for (var i = 0; i < 3; i++)
        ScoutEntry(
          matchId: 'qm$i',
          teamNumber: 3847,
          notes: 'note $i',
          authorDisplayName: 'a',
        ),
    ]);
    final backend = _FakeBackend();

    await _pump(
      tester,
      scoutingController: scouting,
      assistant: _service(backend),
      eventKey: '2026txhou',
      canPublishSummaries: true,
    );

    await tester.enterText(find.byType(TextField), '3847');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(backend.calls, 1);
    expect(
      find.textContaining('scores well from the far side'),
      findsOneWidget,
    );
  });

  testWidgets('does not call the assistant while typing without submitting', (
    tester,
  ) async {
    final scouting = await _scoutingController([
      for (var i = 0; i < 3; i++)
        ScoutEntry(
          matchId: 'qm$i',
          teamNumber: 3847,
          notes: 'note $i',
          authorDisplayName: 'a',
        ),
    ]);
    final backend = _FakeBackend();

    await _pump(
      tester,
      scoutingController: scouting,
      assistant: _service(backend),
      eventKey: '2026txhou',
      canPublishSummaries: true,
    );

    for (final partial in ['3', '38', '384', '3847']) {
      await tester.enterText(find.byType(TextField), partial);
      await tester.pump();
    }

    expect(backend.calls, 0);
    expect(find.text('No notes recorded for team 3847 yet.'), findsNothing);
  });

  testWidgets('renders no summary card without an assistant', (tester) async {
    final scouting = await _scoutingController([
      for (var i = 0; i < 3; i++)
        ScoutEntry(matchId: 'qm$i', teamNumber: 3847, notes: 'note $i'),
    ]);

    await _pump(tester, scoutingController: scouting, eventKey: '2026txhou');

    await tester.enterText(find.byType(TextField), '3847');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Summarise the notes'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ScoutingController scoutingController,
  PitScoutingController? pitScoutingController,
  PitScoutConfigController? pitScoutConfigController,
  TrexTraitReportController? trexTraitReportController,
  AssistantService? assistant,
  String eventKey = '',
  bool canPublishSummaries = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TeamNotesLookupSection(
          scoutingController: scoutingController,
          pitScoutingController: pitScoutingController,
          pitScoutConfigController: pitScoutConfigController,
          trexTraitReportController: trexTraitReportController,
          assistant: assistant,
          eventKey: eventKey,
          canPublishSummaries: canPublishSummaries,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<ScoutingController> _scoutingController([
  List<ScoutEntry> entries = const [],
]) async {
  final controller = ScoutingController(storage: FakeScoutingStorage());
  await controller.bootstrap();
  for (final entry in entries) {
    await controller.saveEntry(entry);
  }
  return controller;
}

Future<PitScoutingController> _pitScoutingController() async {
  final controller = PitScoutingController(storage: FakePitScoutingStorage());
  await controller.bootstrap();
  return controller;
}

Future<PitScoutConfigController> _pitConfigController(
  ScoutConfig config,
) async {
  final service = FakePitScoutConfigService();
  await service.save(config);
  final controller = PitScoutConfigController(service: service);
  await controller.bootstrap();
  return controller;
}

Future<TrexTraitReportController> _trexController() async {
  final controller = TrexTraitReportController(
    storage: FakeTrexTraitReportStorage(),
  );
  await controller.bootstrap();
  return controller;
}

AssistantService _service(_FakeBackend backend) => AssistantService(
  backends: [backend],
  cache: AssistantCache(),
  minimumGap: Duration.zero,
);

class _FakeBackend implements AssistantBackend {
  int calls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    calls++;
    return AssistantSummary(
      text: 'Everyone agrees it scores well from the far side.',
      generatedAt: DateTime.now().toUtc(),
      model: 'fake-model',
      source: AssistantSource.openRouter,
    );
  }
}
