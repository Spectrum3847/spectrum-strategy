import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/trait_config.dart';
import 'package:spectrumstrategy/src/scouting/models/team_analysis.dart';
import 'package:spectrumstrategy/src/state/trait_table_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';
import 'package:spectrumstrategy/src/ui/trait_table_view.dart';

import 'support/fake_trait_table_sync_service.dart';

void main() {
  late FakeTraitTableSyncService sync;
  late TraitTableController controller;

  setUp(() async {
    sync = FakeTraitTableSyncService();
    controller = TraitTableController(syncService: sync);
    await controller.bootstrap();
    await controller.selectMatch(eventKey: '2026miket', matchId: 'qm14');
  });

  tearDown(() => controller.dispose());

  Future<void> pump(
    WidgetTester tester, {
    List<int> teams = const [254, 118, 1678],
    Map<int, TeamAnalysis> analyses = const {},
    Size size = const Size(1200, 900),
    bool canEdit = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => TraitTableView(
              controller: controller,
              teamNumbers: teams,
              analyses: analyses,
              canEdit: canEdit,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('draws every robot and every trait at laptop width', (
    tester,
  ) async {
    await pump(tester);

    for (final team in ['254', '118', '1678']) {
      expect(find.text(team), findsOneWidget);
    }
    for (final trait in TraitConfig.defaults.traits) {
      expect(find.text(trait.label), findsOneWidget);
    }
  });

  testWidgets(
    'all six robots are comparable at once, which is why it is a grid',
    (tester) async {
      await pump(tester, teams: const [254, 118, 1678, 2056, 33, 971]);

      for (final team in ['254', '118', '1678', '2056', '33', '971']) {
        expect(find.text(team), findsOneWidget);
      }
    },
  );

  testWidgets('becomes one card per robot on a phone', (tester) async {
    await pump(tester, size: const Size(400, 900));

    expect(find.text('254'), findsOneWidget);
    expect(find.byType(Table), findsNothing);
  });

  testWidgets('typing a value and leaving the field saves it', (tester) async {
    await pump(tester, teams: const [254]);

    await tester.enterText(find.byType(TextField).first, 'plays defense well');

    expect(
      controller.valueFor(254, TraitConfig.defaults.traits.first.key),
      isEmpty,
    );

    await tester.pump(const Duration(seconds: 1));

    expect(
      controller.valueFor(254, TraitConfig.defaults.traits.first.key),
      'plays defense well',
    );
  });

  testWidgets('a read-only grid takes no input', (tester) async {
    await pump(tester, teams: const [254], canEdit: false);

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.readOnly, isTrue);
    expect(field.decoration?.hintText, isNull);
  });

  testWidgets('does not write when the value did not change', (tester) async {
    await pump(tester, teams: const [254]);

    await tester.tap(find.byType(TextField).first);
    await tester.pump(const Duration(seconds: 1));

    expect(
      controller.valueFor(254, TraitConfig.defaults.traits.first.key),
      isEmpty,
    );
  });

  testWidgets('shows what the scouts saw beside the lead value', (
    tester,
  ) async {
    await pump(
      tester,
      teams: const [254],
      analyses: {
        254: const TeamAnalysis(teamNumber: 254, entryCount: 4, matchCount: 4),
      },
    );

    expect(find.textContaining('scouted'), findsWidgets);
  });

  testWidgets('a team with no scouting data shows no derived number', (
    tester,
  ) async {
    await pump(tester, teams: const [254]);

    expect(find.textContaining('scouted'), findsNothing);
    expect(find.textContaining('spread'), findsNothing);
  });

  testWidgets('says to pick a match when none is selected', (tester) async {
    final idle = TraitTableController(syncService: FakeTraitTableSyncService());
    await idle.bootstrap();
    addTearDown(idle.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TraitTableView(
            controller: idle,
            teamNumbers: const [],
            analyses: const {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Pick a match'), findsOneWidget);
  });

  testWidgets('says the schedule has not loaded rather than drawing nothing', (
    tester,
  ) async {
    await pump(tester, teams: const []);

    expect(find.textContaining('No robots listed'), findsOneWidget);
  });

  testWidgets('uses the palette radius rather than a hardcoded corner', (
    tester,
  ) async {
    await pump(tester, size: const Size(400, 900), teams: const [254]);

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(
      decoration.borderRadius,
      BorderRadius.circular(StrategyPalette.radiusSm),
    );
  });

  group('AI drafts', () {
    final trait = TraitConfig.defaults.traits.first;

    const analysis = TeamAnalysis(
      teamNumber: 254,
      entryCount: 4,
      matchCount: 4,
      byPhase: {StrategyPhase.teleop: PhaseStats(iqmScore: 32.4)},
    );

    testWidgets('a staged draft shows as a distinct banner, not typed text', (
      tester,
    ) async {
      await controller.generateDrafts(
        teamNumbers: const [254],
        analyses: const {254: analysis},
      );
      await pump(tester, teams: const [254]);

      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      expect(find.byIcon(Icons.auto_awesome), findsWidgets);
      expect(find.textContaining('32.4'), findsOneWidget);
    });

    testWidgets('accepting a draft writes it into the cell', (tester) async {
      await controller.generateDrafts(
        teamNumbers: const [254],
        analyses: const {254: analysis},
      );
      await pump(tester, teams: const [254]);
      final draft = controller.draftFor(254, trait.key)!;

      await tester.tap(find.byIcon(Icons.check).first);
      await tester.pumpAndSettle();

      expect(controller.valueFor(254, trait.key), draft);
      expect(controller.draftFor(254, trait.key), isNull);
    });

    testWidgets('dismissing a draft clears it without writing anything', (
      tester,
    ) async {
      await controller.generateDrafts(
        teamNumbers: const [254],
        analyses: const {254: analysis},
      );
      await pump(tester, teams: const [254]);

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      expect(controller.draftFor(254, trait.key), isNull);
      expect(controller.valueFor(254, trait.key), isEmpty);
    });

    testWidgets('a read-only grid does not offer a draft to accept', (
      tester,
    ) async {
      await controller.generateDrafts(
        teamNumbers: const [254],
        analyses: const {254: analysis},
      );
      await pump(tester, teams: const [254], canEdit: false);

      expect(find.byIcon(Icons.auto_awesome), findsNothing);
    });
  });
}
