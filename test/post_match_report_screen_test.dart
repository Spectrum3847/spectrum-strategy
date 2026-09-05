import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tba_client/tba_client.dart';

import 'package:spectrumstrategy/src/models/cycle_log.dart';
import 'package:spectrumstrategy/src/models/user_role.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';
import 'package:spectrumstrategy/src/state/cycle_log_controller.dart';
import 'package:spectrumstrategy/src/state/post_match_report_controller.dart';
import 'package:spectrumstrategy/src/state/user_role_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/ui/post_match_report_screen.dart';

import 'support/fake_cycle_log_storage.dart';
import 'support/fake_post_match_report_storage.dart';
import 'support/fake_post_match_report_sync_service.dart';
import 'support/fake_spectrum_auth_service.dart';
import 'support/fake_user_role_service.dart';

class _RecordingBackend implements AssistantBackend {
  int calls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    calls++;
    return AssistantSummary(
      text: 'It broke in teleop and the result matched the account.',
      generatedAt: DateTime.now().toUtc(),
      model: 'test-model',
      source: AssistantSource.openRouter,
    );
  }
}

class _FakeTbaClient extends TbaClient {
  _FakeTbaClient(this.matches) : super(config: InMemoryTbaConfig('test-key'));

  final List<TbaScheduleMatch> matches;

  @override
  Future<List<TbaScheduleMatch>> getEventMatches(String eventKey) async =>
      matches;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<PostMatchReportController> readyController(
    FakePostMatchReportSyncService sync,
  ) async {
    final controller = PostMatchReportController(syncService: sync);
    await controller.bootstrap();
    return controller;
  }

  Future<UserRoleController> readyRoles(UserRole role) async {
    const user = SpectrumUser(uid: 'lead-uid', displayName: 'Lead');
    final roleService = FakeUserRoleService()
      ..setRoles('lead-uid', <UserRole>{role});
    final roles = UserRoleController(
      authService: FakeSpectrumAuthService(initialUser: user),
      roleService: roleService,
    );
    await roles.bootstrap();
    return roles;
  }

  testWidgets('an editor can type all four sections and save them together', (
    tester,
  ) async {
    final sync = FakePostMatchReportSyncService();
    final controller = await readyController(sync);
    final roles = await readyRoles(UserRole.strategy);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: PostMatchReportScreen(
          controller: controller,
          matchLabel: 'Qual 14',
          eventKey: '2026miket',
          matchId: 'qm14',
          userRoleController: roles,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Qual 14 report'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Teleop'), findsOneWidget);
    expect(find.text('Endgame'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(4));

    await tester.enterText(fields.at(0), 'Scored two, missed the third');
    await tester.enterText(fields.at(1), 'Cycled steadily');
    await tester.enterText(fields.at(2), 'Climbed with time to spare');
    await tester.enterText(fields.at(3), 'Nothing broke');
    await tester.pumpAndSettle();

    expect(sync.pushes, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(sync.pushes, hasLength(1));
    final pushed = sync.pushes.single;
    expect(pushed.auto, 'Scored two, missed the third');
    expect(pushed.teleop, 'Cycled steadily');
    expect(pushed.endgame, 'Climbed with time to spare');
    expect(pushed.notes, 'Nothing broke');
    expect(find.text('Saved'), findsOneWidget);

    controller.dispose();
  });

  testWidgets(
    'a viewer sees the read-only notice, disabled fields, and no Save',
    (tester) async {
      final sync = FakePostMatchReportSyncService();
      final controller = await readyController(sync);
      final roles = await readyRoles(UserRole.viewer);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: PostMatchReportScreen(
            controller: controller,
            matchLabel: 'Qual 14',
            eventKey: '2026miket',
            matchId: 'qm14',
            userRoleController: roles,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Only strategy leads and admins can edit this.'),
        findsOneWidget,
      );

      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.enabled, isFalse);
      }
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);

      controller.dispose();
    },
  );

  testWidgets('a failed local save shows the pill, a landed one clears it', (
    tester,
  ) async {
    final sync = FakePostMatchReportSyncService();
    final storage = FakePostMatchReportStorage();
    final controller = PostMatchReportController(
      storage: storage,
      syncService: sync,
    );
    await controller.bootstrap();
    final roles = await readyRoles(UserRole.strategy);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: PostMatchReportScreen(
          controller: controller,
          matchLabel: 'Qual 14',
          eventKey: '2026miket',
          matchId: 'qm14',
          userRoleController: roles,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('not saved'), findsNothing);

    storage.failNextSave = StateError('disk full');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('1 edit not saved'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not saved'), findsNothing);

    controller.dispose();
  });

  testWidgets(
    'a failed save keeps the typed edit on screen instead of reverting it',
    (tester) async {
      final sync = FakePostMatchReportSyncService();
      final storage = FakePostMatchReportStorage();
      final controller = PostMatchReportController(
        storage: storage,
        syncService: sync,
      );
      await controller.bootstrap();

      await controller.save(
        eventKey: '2026miket',
        matchId: 'qm14',
        auto: 'first save',
        teleop: '',
        endgame: '',
        notes: '',
      );
      final roles = await readyRoles(UserRole.strategy);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: PostMatchReportScreen(
            controller: controller,
            matchLabel: 'Qual 14',
            eventKey: '2026miket',
            matchId: 'qm14',
            userRoleController: roles,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final autoField = find.byType(TextField).first;
      storage.failNextSave = StateError('disk full');
      await tester.enterText(autoField, 'edit that never lands');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('edit that never lands'), findsOneWidget);
      expect(find.text('first save'), findsNothing);
      expect(find.text('1 edit not saved'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);

      controller.dispose();
    },
  );

  testWidgets('a cycle log note appears when one already exists', (
    tester,
  ) async {
    final sync = FakePostMatchReportSyncService();
    final controller = await readyController(sync);
    final cycleLog = CycleLogController(storage: FakeCycleLogStorage());
    await cycleLog.bootstrap();
    await cycleLog.recordEvent(
      matchKey: 'qm14',
      team: 3847,
      kind: CycleEventKind.intake,
      offsetMs: 0,
      phase: StrategyPhase.teleop,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: PostMatchReportScreen(
          controller: controller,
          matchLabel: 'Qual 14',
          eventKey: '2026miket',
          matchId: 'qm14',
          cycleLogController: cycleLog,
          cycleLogTeams: const <int>[3847, 254],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('cycle log already exists'), findsOneWidget);
    expect(find.textContaining('3847'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('shows the TBA result once it has posted, framed as a win', (
    tester,
  ) async {
    final sync = FakePostMatchReportSyncService();
    final controller = await readyController(sync);
    final tbaClient = _FakeTbaClient(<TbaScheduleMatch>[
      const TbaScheduleMatch(
        key: '2026miket_qm14',
        compLevel: 'qm',
        matchNumber: 14,
        redTeams: <int>[3847, 111, 222],
        blueTeams: <int>[254, 333, 444],
        redScore: 120,
        blueScore: 98,
        winningAlliance: 'red',
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: PostMatchReportScreen(
          controller: controller,
          matchLabel: 'Qual 14',
          eventKey: '2026miket',
          matchId: 'qm14',
          tbaClient: tbaClient,
          myTeamNumber: 3847,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Won 120 - 98'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('shows nothing for a TBA result that has not posted yet', (
    tester,
  ) async {
    final sync = FakePostMatchReportSyncService();
    final controller = await readyController(sync);
    final tbaClient = _FakeTbaClient(const <TbaScheduleMatch>[]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: PostMatchReportScreen(
          controller: controller,
          matchLabel: 'Qual 14',
          eventKey: '2026miket',
          matchId: 'qm14',
          tbaClient: tbaClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('TBA result'), findsNothing);

    controller.dispose();
  });

  testWidgets(
    "the analysis section is labelled and sits under the lead's fields",
    (tester) async {
      final sync = FakePostMatchReportSyncService();
      final controller = await readyController(sync);
      final tbaClient = _FakeTbaClient(const <TbaScheduleMatch>[]);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: PostMatchReportScreen(
            controller: controller,
            matchLabel: 'Qual 14',
            eventKey: '2026miket',
            matchId: 'qm14',
            tbaClient: tbaClient,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Analysis'), findsOneWidget);
      final notesY = tester.getTopLeft(find.text('Notes')).dy;
      final analysisY = tester.getTopLeft(find.text('Analysis')).dy;
      expect(analysisY, greaterThan(notesY));

      controller.dispose();
    },
  );

  testWidgets('no assistant configured hides the AI summary entirely', (
    tester,
  ) async {
    final sync = FakePostMatchReportSyncService();
    final controller = await readyController(sync);
    await controller.save(
      eventKey: '2026miket',
      matchId: 'qm14',
      auto: '',
      teleop: '',
      endgame: '',
      notes: 'Broke down mid-teleop, drive motor cut out.',
    );
    final tbaClient = _FakeTbaClient(const <TbaScheduleMatch>[]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: PostMatchReportScreen(
          controller: controller,
          matchLabel: 'Qual 14',
          eventKey: '2026miket',
          matchId: 'qm14',
          tbaClient: tbaClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI summary'), findsNothing);

    controller.dispose();
  });

  testWidgets('an empty report has nothing for the AI summary to say', (
    tester,
  ) async {
    final sync = FakePostMatchReportSyncService();
    final controller = await readyController(sync);
    final backend = _RecordingBackend();
    final assistant = AssistantService(
      backends: [backend],
      cache: AssistantCache(),
      minimumGap: Duration.zero,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: PostMatchReportScreen(
          controller: controller,
          matchLabel: 'Qual 14',
          eventKey: '2026miket',
          matchId: 'qm14',
          assistant: assistant,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI summary'), findsNothing);
    expect(backend.calls, 0);

    controller.dispose();
  });

  testWidgets('the AI summary is requested on demand, not computed on render', (
    tester,
  ) async {
    final sync = FakePostMatchReportSyncService();
    final controller = await readyController(sync);
    await controller.save(
      eventKey: '2026miket',
      matchId: 'qm14',
      auto: '',
      teleop: '',
      endgame: '',
      notes: 'Broke down mid-teleop, drive motor cut out.',
    );
    final backend = _RecordingBackend();
    final assistant = AssistantService(
      backends: [backend],
      cache: AssistantCache(),
      minimumGap: Duration.zero,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: PostMatchReportScreen(
          controller: controller,
          matchLabel: 'Qual 14',
          eventKey: '2026miket',
          matchId: 'qm14',
          assistant: assistant,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI summary'), findsOneWidget);
    expect(
      find.text('The summary is not written until you ask for it.'),
      findsOneWidget,
    );
    expect(backend.calls, 0);

    await tester.ensureVisible(find.text('Summarise this report'));
    await tester.tap(find.text('Summarise this report'));
    await tester.pumpAndSettle();

    expect(backend.calls, 1);
    expect(find.textContaining('It broke in teleop'), findsOneWidget);

    controller.dispose();
  });
}
