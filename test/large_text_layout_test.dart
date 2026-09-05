import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:statbotics_client/statbotics_client.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import 'package:spectrumstrategy/src/models/match_preview.dart';
import 'package:spectrumstrategy/src/models/pick_list.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_config.dart';
import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/models/team_analysis.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scout_config_controller.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/scouting/ui/pit_question_editor.dart';
import 'package:spectrumstrategy/src/scouting/ui/scout_form_fields.dart';
import 'package:spectrumstrategy/src/services/pick_list_storage.dart';
import 'package:spectrumstrategy/src/state/event_controller.dart';
import 'package:spectrumstrategy/src/state/pick_list_controller.dart';
import 'package:spectrumstrategy/src/state/post_match_report_controller.dart';
import 'package:spectrumstrategy/src/state/strategy_controller.dart';
import 'package:spectrumstrategy/src/state/trex_assignments_controller.dart';
import 'package:spectrumstrategy/src/state/trex_team_list_controller.dart';
import 'package:spectrumstrategy/src/theme/app_theme.dart';
import 'package:spectrumstrategy/src/ui/database_tab.dart';
import 'package:spectrumstrategy/src/ui/match_info_view.dart';
import 'package:spectrumstrategy/src/ui/match_preview_screen.dart';
import 'package:spectrumstrategy/src/ui/pick_lists_screen.dart';
import 'package:spectrumstrategy/src/ui/pit_scouting_screen.dart';
import 'package:spectrumstrategy/src/ui/post_match_report_screen.dart';
import 'package:spectrumstrategy/src/ui/scouting_tab.dart';
import 'package:spectrumstrategy/src/ui/team_lookup_view.dart';
import 'package:spectrumstrategy/src/ui/trex_screen.dart';
import 'package:spectrumstrategy/src/widgets/match_schedule_row.dart';

import 'support/fake_match_directory.dart';
import 'support/fake_pick_list_sync_service.dart';
import 'support/fake_pit_photo_store.dart';
import 'support/fake_pit_scout_config_service.dart';
import 'support/fake_pit_scouting_storage.dart';
import 'support/fake_post_match_report_storage.dart';
import 'support/fake_post_match_report_sync_service.dart';
import 'support/fake_scout_config_service.dart';
import 'support/fake_scouting_storage.dart';
import 'support/fake_trex_assignments_sync_service.dart';
import 'support/fake_trex_team_list_sync_service.dart';

const Size _smallPhone = Size(360, 760);
const TextScaler _doubled = TextScaler.linear(2.0);

Future<void> _pumpAtDoubleText(
  WidgetTester tester,
  Widget home, {
  Size size = _smallPhone,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),

      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: _doubled),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

StatboticsMatch _match() => StatboticsMatch(
  key: '2026txdri1_qm1',
  event: '2026txdri1',
  matchNumber: 1,
  compLevel: 'qm',
  redTeams: const <int>[3847, 118, 2056],
  blueTeams: const <int>[254, 1323, 971],
);

class _InMemoryPickListStorage implements PickListStorage {
  final Map<String, PickList> data = <String, PickList>{};
  Set<String> _synced = <String>{};

  @override
  Future<List<PickList>> loadAll() async => data.values.toList();

  @override
  Future<void> save(PickList list) async => data[list.id] = list;

  @override
  Future<void> delete(String id) async => data.remove(id);

  @override
  Future<Set<String>> loadSyncedIds() async => Set<String>.of(_synced);

  @override
  Future<void> saveSyncedIds(Set<String> ids) async =>
      _synced = Set<String>.of(ids);
}

void main() {
  testWidgets('a schedule row holds six teams at 200% text', (tester) async {
    await _pumpAtDoubleText(
      tester,
      Scaffold(
        body: ListView(
          children: <Widget>[
            MatchScheduleRow(
              match: _match(),
              nicknames: const <int, String>{
                3847: 'Spectrum',
                254: 'The Cheesy Poofs',
              },
            ),
          ],
        ),
      ),
    );

    expect(find.textContaining('3847'), findsWidgets);
    expect(find.textContaining('971'), findsWidgets);
  });

  testWidgets('the scout form section holds up at 200% text', (tester) async {
    await _pumpAtDoubleText(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: ScoutFormSection(
            section: const ScoutConfigSection(
              name: 'Autonomous',
              fields: <ScoutConfigField>[
                ScoutConfigField(
                  title: 'Coral L1 scored in the reef',
                  code: 'coralL1',
                  type: ScoutFieldType.counter,
                ),
                ScoutConfigField(
                  title: 'Left the starting line',
                  code: 'left',
                  type: ScoutFieldType.boolean,
                ),

                ScoutConfigField(
                  title: 'Where did it score from',
                  code: 'scoreFrom',
                  type: ScoutFieldType.select,
                  choices: <String, String>{
                    '1': 'Outpost trench, far side of the field',
                    '2': 'Depot',
                  },
                ),
                ScoutConfigField(
                  title: 'Notes',
                  code: 'notes',
                  type: ScoutFieldType.text,
                ),
              ],
            ),
            keyPrefix: 'scout-field',

            values: <String, dynamic>{
              'coralL1': 12,
              'left': true,
              'scoreFrom': '1',
            },
            textControllers: <String, TextEditingController>{
              'notes': TextEditingController(),
            },
            onFieldChanged: (String code, dynamic value) {},
          ),
        ),
      ),
    );

    expect(find.text('Coral L1 scored in the reef'), findsOneWidget);
    expect(find.text('Where did it score from'), findsOneWidget);

    expect(find.text('Outpost trench, far side of the field'), findsOneWidget);
  });

  testWidgets('the scouting capture tab holds up at 200% text', (tester) async {
    final strategy = StrategyController(directory: FakeMatchDirectory());
    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await Future.wait(<Future<void>>[
      strategy.bootstrap(),
      scouting.bootstrap(),
      config.bootstrap(),
    ]);

    await _pumpAtDoubleText(
      tester,
      ScoutingTab(
        strategyController: strategy,
        scoutingController: scouting,
        configController: config,
        eventController: EventController(),
      ),
    );

    expect(find.textContaining('No event selected'), findsWidgets);
  });

  testWidgets('the Database tab rows view holds up at 200% text', (
    tester,
  ) async {
    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await scouting.bootstrap();
    await config.bootstrap();
    await scouting.saveEntry(
      ScoutEntry(
        matchId: '2026txdri1_qm1',
        teamNumber: 3847,
        alliance: 'Red',
        authorDisplayName: 'Alexandria',
        notes: 'Fast cycles, dropped one coral in the last twenty seconds',
        fieldValues: const <String, dynamic>{
          'scouter': 'Alexandria',
          'matchNumber': 1,
          'robot': 'Red 1',
          'pTnumber': 3847,
        },
      ),
    );

    await _pumpAtDoubleText(
      tester,
      Scaffold(
        body: DatabaseTab(
          scoutingController: scouting,
          configController: config,
          eventController: EventController(),
          canEditAnyEntry: true,
          canAddManualEntry: true,
        ),
      ),
    );

    expect(find.textContaining('Alexandria'), findsWidgets);
    await tester.drag(find.byType(TableView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('3847'), findsWidgets);
  });

  testWidgets('the match preview holds up at 200% text', (tester) async {
    await _pumpAtDoubleText(
      tester,
      MatchPreviewScreen(
        preview: MatchPreview.fromMatch(
          _match(),
          nicknames: const <int, String>{3847: 'Spectrum'},
          teamEvents: const <int, StatboticsTeamEvent>{},
          analyses: const <int, TeamAnalysis>{},
        ),
      ),
    );

    expect(find.textContaining('For the strategy call'), findsOneWidget);
  });

  testWidgets('the pick list screens hold up at 200% text', (tester) async {
    final controller = PickListController(
      storage: _InMemoryPickListStorage(),
      syncService: FakePickListSyncService(),
      idGenerator: () => 'list-1',
      clock: () => DateTime.utc(2026, 8, 5),
    );
    await controller.bootstrap();
    final list = (await controller.create('First pick candidates'))!;
    for (final int team in const <int>[3847, 254, 118]) {
      await controller.addTeam(list.id, team);
    }

    await _pumpAtDoubleText(tester, PickListsScreen(controller: controller));
    expect(find.text('First pick candidates'), findsOneWidget);

    await _pumpAtDoubleText(
      tester,
      PickListEditorScreen(controller: controller, listId: list.id),
    );
    expect(find.textContaining('3847'), findsWidgets);
  });

  testWidgets('the pit scouting screen holds up at 200% text', (tester) async {
    final controller = PitScoutingController(
      storage: FakePitScoutingStorage(),
      photoStore: FakePitPhotoStore(),
    );
    await controller.bootstrap();
    await controller.saveEntry(
      PitScoutEntry(teamNumber: 3847, authorUid: 'uid-1'),
    );
    final configController = PitScoutConfigController(
      service: FakePitScoutConfigService(),
    );
    await configController.bootstrap();

    await _pumpAtDoubleText(
      tester,
      PitScoutingScreen(
        controller: controller,
        configController: configController,
      ),
    );

    await tester.ensureVisible(find.text('Questionnaire'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Questionnaire'));
    await tester.pumpAndSettle();

    expect(find.text('Team Number'), findsOneWidget);
    expect(find.textContaining('3847'), findsWidgets);

    expect(find.text('Tank / Skid Steer'), findsOneWidget);
  });

  testWidgets('the pit question editor holds up at 200% text', (tester) async {
    final configController = PitScoutConfigController(
      service: FakePitScoutConfigService(),
    );
    await configController.bootstrap();

    await _pumpAtDoubleText(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: PitQuestionEditor(controller: configController),
        ),
      ),
    );

    expect(find.text('Drivetrain'), findsOneWidget);
    expect(find.text('Drivetrain Type'), findsOneWidget);
  });

  testWidgets('the T-Rex assignments tab holds up at 200% text', (
    tester,
  ) async {
    final sync = FakeTRexAssignmentsSyncService();
    final trexController = TRexAssignmentsController(syncService: sync);
    await trexController.bootstrap();
    await trexController.addColumn('Defense');
    await trexController.addName(
      trexController.assignments.columns.single.key,
      'Alexandra',
    );

    final teamListSync = FakeTRexTeamListSyncService();
    final trexTeamListController = TRexTeamListController(
      syncService: teamListSync,
    );
    await trexTeamListController.bootstrap();
    await trexTeamListController.addColumn('Defense');
    await trexTeamListController.addTeam(
      trexTeamListController.teamList.columns.single.key,
      '3847',
    );

    await _pumpAtDoubleText(
      tester,
      TrexScreen(
        trexController: trexController,
        trexTeamListController: trexTeamListController,
        canEditTRexAssignments: true,
      ),
    );

    await tester.ensureVisible(find.text('Assignments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assignments'));
    await tester.pumpAndSettle();

    expect(find.text('Alexandra'), findsOneWidget);

    expect(find.text('3847'), findsOneWidget);
  });

  testWidgets('the post match report form holds up at 200% text', (
    tester,
  ) async {
    final controller = PostMatchReportController(
      storage: FakePostMatchReportStorage(),
      syncService: FakePostMatchReportSyncService(),
    );
    await controller.bootstrap();

    await _pumpAtDoubleText(
      tester,
      PostMatchReportScreen(
        controller: controller,
        matchLabel: 'Qual 1',
        eventKey: '2026txdri1',
        matchId: 'qm1',
      ),
    );

    expect(find.text('Qual 1 report'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Teleop'), findsOneWidget);
    expect(find.text('Endgame'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);

    controller.dispose();
  });

  testWidgets("the pit scouting screen's Database tab holds up at 200% text", (
    tester,
  ) async {
    final pitController = PitScoutingController(
      storage: FakePitScoutingStorage(),
      photoStore: FakePitPhotoStore(),
    );
    await pitController.bootstrap();
    await pitController.saveEntry(
      PitScoutEntry(
        teamNumber: 3847,
        authorDisplayName: 'Alexandria',
        fieldValues: const <String, dynamic>{
          'drivetrainType': 'swerve',
          'frameDimensions': '28x30, welded aluminum tube frame perimeter',
        },
      ),
    );
    final pitConfig = PitScoutConfigController(
      service: FakePitScoutConfigService(),
    );
    await pitConfig.bootstrap();

    await _pumpAtDoubleText(
      tester,
      PitScoutingScreen(controller: pitController, configController: pitConfig),
    );

    await tester.tap(find.text('Team 3847'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Alexandria'), findsWidgets);

    expect(find.textContaining('Swerve'), findsWidgets);
  });

  testWidgets('the team lookup view holds up at 200% text', (tester) async {
    final scouting = ScoutingController(storage: FakeScoutingStorage());
    final config = ScoutConfigController(service: FakeScoutConfigService());
    await scouting.bootstrap();
    await config.bootstrap();
    await scouting.saveEntry(
      ScoutEntry(
        matchId: '2026txdri1_qm1',
        teamNumber: 3847,
        alliance: 'Red',
        authorDisplayName: 'Alexandria',
        notes: 'Fast cycles, dropped one coral in the last twenty seconds',
        fieldValues: const <String, dynamic>{
          'scouter': 'Alexandria',
          'matchNumber': 1,
          'robot': 'Red 1',
          'pTnumber': 3847,
          'teleopFuelScored': 30,
          'autoFuelScored': 5,
          'eLow': 'Outpost',
        },
      ),
    );

    await _pumpAtDoubleText(
      tester,
      Scaffold(
        body: TeamLookupView(
          scoutingController: scouting,
          configController: config,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '3847');
    await tester.pumpAndSettle();

    expect(find.text('Team 3847'), findsOneWidget);
    expect(find.textContaining('Match 1'), findsOneWidget);
    expect(
      find.textContaining('Fast cycles, dropped one coral'),
      findsOneWidget,
    );
  });

  testWidgets('the match info view holds up at 200% text', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const eventJson = '{"key":"2026txhou","name":"Houston","year":2026}';
    const matchesJson =
        '[{"key":"2026txhou_qm1","event":"2026txhou","match_number":1,'
        '"comp_level":"qm","alliances":{"red":{"team_keys":[3847,118,2056]},'
        '"blue":{"team_keys":[254,1323,971]}}}]';
    Future<http.Response> handler(http.Request request) async {
      final path = request.url.path;
      if (path.endsWith('/event/2026txhou')) {
        return http.Response(eventJson, 200);
      }
      if (path.endsWith('/team_events')) return http.Response('[]', 200);
      if (path.endsWith('/matches')) return http.Response(matchesJson, 200);
      if (path.endsWith('/teams')) return http.Response('[]', 200);
      return http.Response('not found', 404);
    }

    final eventController = EventController(
      client: StatboticsClient(
        httpClient: MockClient(handler),
        sleep: (_) async {},
      ),
      statboticsEnabled: true,
    );
    await eventController.setEventKey('2026txhou');
    await eventController.setMyTeamNumber(3847);

    final scoutingController = ScoutingController(
      storage: FakeScoutingStorage(),
    );
    await scoutingController.bootstrap();
    await scoutingController.saveEntry(
      ScoutEntry(
        matchId: 'qm1',
        teamNumber: 118,
        fieldValues: const {'teleopFuelScored': 10},
        notes:
            'A long scouting note about this robot, its drivetrain, its '
            'launcher cadence, and how it played defense in the endgame.',
      ),
    );
    final configController = ScoutConfigController(
      service: FakeScoutConfigService(),
    );
    await configController.bootstrap();

    await _pumpAtDoubleText(
      tester,
      Scaffold(
        body: MatchInfoView(
          eventController: eventController,
          scoutingController: scoutingController,
          configController: configController,
        ),
      ),
    );

    expect(find.text('Pre-match'), findsOneWidget);
    expect(find.text('Opponents'), findsOneWidget);
    expect(find.text('118'), findsOneWidget);
  });
}
