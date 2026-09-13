import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/models/trait_config.dart';
import 'package:spectrumstrategy/src/models/trait_table.dart';
import 'package:spectrumstrategy/src/scouting/models/team_analysis.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_backend.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_cache.dart';
import 'package:spectrumstrategy/src/services/assistant/assistant_service.dart';
import 'package:spectrumstrategy/src/state/trait_table_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

import 'support/fake_trait_table_sync_service.dart';

void main() {
  late FakeTraitTableSyncService sync;
  late TraitTableController controller;

  Future<TraitTableController> ready(
    FakeTraitTableSyncService service, {
    String eventKey = '2026miket',
    String matchId = 'qm14',
  }) async {
    final c = TraitTableController(syncService: service);
    await c.bootstrap();
    await c.selectMatch(eventKey: eventKey, matchId: matchId);
    return c;
  }

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sync = FakeTraitTableSyncService();
    controller = await ready(sync);
  });

  tearDown(() => controller.dispose());

  group('selecting a match', () {
    test('points the watch at that match', () {
      expect(sync.watched.last.eventKey, '2026miket');
      expect(sync.watched.last.matchId, 'qm14');
    });

    test('an absent document reads as an empty table, not as null', () {
      expect(controller.hasMatch, isTrue);
      expect(controller.table.isEmpty, isTrue);
      expect(controller.table.id, '2026miket_qm14');
    });

    test('no match selected is distinct from an empty table', () async {
      final c = TraitTableController(syncService: FakeTraitTableSyncService());
      await c.bootstrap();

      expect(c.hasMatch, isFalse);
      c.dispose();
    });

    test('re-selecting the same match does not re-subscribe', () async {
      final before = sync.watched.length;
      await controller.selectMatch(eventKey: '2026miket', matchId: 'qm14');

      expect(sync.watched.length, before);
    });
  });

  group('editing', () {
    test('shows the value locally without waiting for the network', () async {
      await controller.setCell(
        teamNumber: 254,
        traitKey: 'defense',
        value: 'strong',
      );

      expect(controller.valueFor(254, 'defense'), 'strong');
    });

    test('records the author from the signed-in user', () async {
      await controller.setCell(
        teamNumber: 254,
        traitKey: 'defense',
        value: 'strong',
      );

      expect(sync.pushes.single.authorUid, 'uid-1');
      expect(sync.pushes.single.authorDisplayName, 'Lead');
    });

    test('does not push a write the rules would reject', () async {
      final service = FakeTraitTableSyncService(uid: '');
      final c = TraitTableController(syncService: service);
      await c.bootstrap();
      await c.selectMatch(eventKey: '2026miket', matchId: 'qm14');
      await c.setCell(teamNumber: 254, traitKey: 'defense', value: 'strong');

      expect(service.pushes, isEmpty);

      expect(c.valueFor(254, 'defense'), 'strong');
      c.dispose();
    });

    test('does nothing when no match is selected', () async {
      final service = FakeTraitTableSyncService();
      final c = TraitTableController(syncService: service);
      await c.bootstrap();
      await c.setCell(teamNumber: 254, traitKey: 'defense', value: 'strong');

      expect(service.pushes, isEmpty);
      c.dispose();
    });

    test(
      'a failed push keeps the value on screen and does not stop the next one',
      () async {
        expect(controller.failedWrites.hasFailures, isFalse);

        sync.failNextPush = StateError('offline');
        await controller.setCell(
          teamNumber: 254,
          traitKey: 'defense',
          value: 'strong',
        );

        expect(controller.valueFor(254, 'defense'), 'strong');
        expect(sync.pushes, isEmpty);

        expect(controller.failedWrites.hasFailures, isTrue);
        expect(controller.failedWrites.unlandedCount, 1);
        expect(controller.failedWrites.lastFailureAt, isNotNull);

        await controller.setCell(
          teamNumber: 254,
          traitKey: 'endgame',
          value: 'deep climb',
        );

        expect(sync.pushes, hasLength(1));

        expect(controller.failedWrites.hasFailures, isFalse);
        expect(controller.failedWrites.unlandedCount, 0);
        expect(controller.failedWrites.lastFailureAt, isNull);
      },
    );
  });

  group('write ordering', () {
    test('two quick edits push in the order they were made', () async {
      final laggy = LaggyTraitTableSyncService();
      final c = await ready(laggy);

      final first = c.setCell(
        teamNumber: 254,
        traitKey: 'defense',
        value: 'first',
      );
      final second = c.setCell(
        teamNumber: 254,
        traitKey: 'endgame',
        value: 'second',
      );
      await Future.wait([first, second]);

      expect(laggy.pushes.map((t) => t.valueFor(254, 'defense')), [
        'first',
        'first',
      ]);
      expect(laggy.pushes.last.valueFor(254, 'endgame'), 'second');
      c.dispose();
    });

    test('a queued write sends what it was given, not a later edit', () async {
      final laggy = LaggyTraitTableSyncService();
      final c = await ready(laggy);

      final first = c.setCell(
        teamNumber: 254,
        traitKey: 'defense',
        value: 'first',
      );
      final second = c.setCell(
        teamNumber: 254,
        traitKey: 'defense',
        value: 'second',
      );
      await Future.wait([first, second]);

      expect(laggy.pushes.map((t) => t.valueFor(254, 'defense')), [
        'first',
        'second',
      ]);
      c.dispose();
    });

    test('switching match drains queued writes first', () async {
      final laggy = LaggyTraitTableSyncService();
      final c = await ready(laggy);

      unawaited(
        c.setCell(teamNumber: 254, traitKey: 'defense', value: 'strong'),
      );
      await c.selectMatch(eventKey: '2026miket', matchId: 'qm15');

      expect(laggy.pushes.single.matchId, 'qm14');
      c.dispose();
    });
  });

  group('remote snapshots', () {
    test('a snapshot for the current match replaces the local table', () async {
      sync.emitTable(
        TraitTable(
          id: '2026miket_qm14',
          eventKey: '2026miket',
          matchId: 'qm14',
          cells: const {
            254: {'defense': 'from another device'},
          },
          updatedAt: DateTime.utc(2026, 8, 16),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.valueFor(254, 'defense'), 'from another device');
    });

    test('a snapshot for a different match is ignored', () async {
      sync.emitTable(
        TraitTable(
          id: '2026miket_qm99',
          eventKey: '2026miket',
          matchId: 'qm99',
          cells: const {
            254: {'defense': 'wrong match'},
          },
          updatedAt: DateTime.utc(2026, 8, 16),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.valueFor(254, 'defense'), isEmpty);
    });
  });

  group('trait config', () {
    test('starts on the defaults so the grid is never empty', () {
      expect(controller.config.traits, isNotEmpty);
    });

    test('follows the remote config when one arrives', () async {
      sync.emitConfig(
        TraitConfig.fromJson(const {
          'traits': [
            {'key': 'onlyOne', 'label': 'Only one'},
          ],
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.config.traits.map((t) => t.key), ['onlyOne']);
    });
  });

  group('generating drafts', () {
    test(
      'stages numeric-sourced cells from Dart, with no assistant at all',
      () async {
        await controller.generateDrafts(
          teamNumbers: [254],
          analyses: {254: _analysis(254)},
        );

        expect(controller.draftFor(254, 'teleopScoring'), contains('32.4'));

        expect(controller.draftFor(254, 'reliability'), isNotNull);

        expect(controller.draftFor(254, 'cycleTime'), isNull);
      },
    );

    test('does not draft over a cell that already has a value', () async {
      await controller.setCell(
        teamNumber: 254,
        traitKey: 'teleopScoring',
        value: 'already written',
      );

      await controller.generateDrafts(
        teamNumbers: [254],
        analyses: {254: _analysis(254)},
      );

      expect(controller.draftFor(254, 'teleopScoring'), isNull);
      expect(controller.valueFor(254, 'teleopScoring'), 'already written');
    });

    test('drafts qualitative cells through the assistant', () async {
      final backend = _ScriptedBackend(
        'cycleTime: fast, consistent cycles\n'
        'defense: plays it occasionally\n'
        'driverSkill: confident in traffic',
      );
      final withAssistant = TraitTableController(
        syncService: sync,
        assistant: AssistantService(
          backends: [backend],
          cache: AssistantCache(),
        ),
      );
      await withAssistant.bootstrap();
      await withAssistant.selectMatch(eventKey: '2026miket', matchId: 'qm14');
      addTearDown(withAssistant.dispose);

      await withAssistant.generateDrafts(
        teamNumbers: [254],
        analyses: {254: _analysis(254)},
      );

      expect(
        withAssistant.draftFor(254, 'cycleTime'),
        'fast, consistent cycles',
      );
      expect(withAssistant.draftFor(254, 'defense'), 'plays it occasionally');
      expect(
        withAssistant.draftFor(254, 'driverSkill'),
        'confident in traffic',
      );

      expect(backend.requests, hasLength(1));
    });

    test('accepting a draft writes it and clears the staged draft', () async {
      await controller.generateDrafts(
        teamNumbers: [254],
        analyses: {254: _analysis(254)},
      );
      final draft = controller.draftFor(254, 'teleopScoring')!;

      await controller.acceptDraft(teamNumber: 254, traitKey: 'teleopScoring');

      expect(controller.valueFor(254, 'teleopScoring'), draft);
      expect(controller.draftFor(254, 'teleopScoring'), isNull);
      expect(sync.pushes.single.valueFor(254, 'teleopScoring'), draft);
    });

    test('dismissing a draft discards it without writing anything', () async {
      await controller.generateDrafts(
        teamNumbers: [254],
        analyses: {254: _analysis(254)},
      );

      controller.dismissDraft(teamNumber: 254, traitKey: 'teleopScoring');

      expect(controller.draftFor(254, 'teleopScoring'), isNull);
      expect(controller.valueFor(254, 'teleopScoring'), isEmpty);
      expect(sync.pushes, isEmpty);
    });

    test('one team failing to draft does not stop the rest', () async {
      final backend = _FailingForOneTeamBackend(failFor: 254);
      final withAssistant = TraitTableController(
        syncService: sync,
        assistant: AssistantService(
          backends: [backend],
          cache: AssistantCache(),
        ),
      );
      await withAssistant.bootstrap();
      await withAssistant.selectMatch(eventKey: '2026miket', matchId: 'qm14');
      addTearDown(withAssistant.dispose);

      await withAssistant.generateDrafts(
        teamNumbers: [254, 148],
        analyses: {254: _analysis(254), 148: _analysis(148)},
      );

      expect(withAssistant.draftErrorFor(254), isNotNull);
      expect(withAssistant.draftFor(148, 'cycleTime'), isNotNull);
    });

    test('too little scouted data skips the qualitative request, but still '
        'stages the numbers', () async {
      final backend = _ScriptedBackend(
        'cycleTime: x\ndefense: y\ndriverSkill: z',
      );
      final withAssistant = TraitTableController(
        syncService: sync,
        assistant: AssistantService(
          backends: [backend],
          cache: AssistantCache(),
        ),
      );
      await withAssistant.bootstrap();
      await withAssistant.selectMatch(eventKey: '2026miket', matchId: 'qm14');
      addTearDown(withAssistant.dispose);

      await withAssistant.generateDrafts(
        teamNumbers: [254],
        analyses: {254: _analysis(254, entryCount: 1, matchCount: 1)},
      );

      expect(withAssistant.draftFor(254, 'teleopScoring'), isNotNull);
      expect(withAssistant.draftFor(254, 'cycleTime'), isNull);
      expect(backend.requests, isEmpty);
    });

    test('switching match clears staged drafts', () async {
      await controller.generateDrafts(
        teamNumbers: [254],
        analyses: {254: _analysis(254)},
      );
      expect(controller.draftFor(254, 'teleopScoring'), isNotNull);

      await controller.selectMatch(eventKey: '2026miket', matchId: 'qm15');

      expect(controller.draftFor(254, 'teleopScoring'), isNull);
    });
  });
}

TeamAnalysis _analysis(
  int teamNumber, {
  int entryCount = 4,
  int matchCount = 4,
}) => TeamAnalysis(
  teamNumber: teamNumber,
  entryCount: entryCount,
  matchCount: matchCount,
  byPhase: const {
    StrategyPhase.auton: PhaseStats(iqmScore: 5),
    StrategyPhase.teleop: PhaseStats(iqmScore: 32.4),
    StrategyPhase.endgame: PhaseStats(iqmScore: 10),
  },
  iqmTotalScore: 47.4,
  scoreStdDev: 4.2,
);

class _ScriptedBackend implements AssistantBackend {
  _ScriptedBackend(this.response);

  final String response;
  final List<AssistantRequest> requests = [];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    requests.add(request);
    return AssistantSummary(
      text: response,
      generatedAt: DateTime.utc(2026, 8, 19),
      model: 'test-model',
      source: AssistantSource.openRouter,
    );
  }
}

class _FailingForOneTeamBackend implements AssistantBackend {
  _FailingForOneTeamBackend({required this.failFor});

  final int failFor;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AssistantSummary> complete(AssistantRequest request) async {
    if (request.cacheKey.endsWith(':$failFor')) {
      throw const AssistantUnavailable('Could not reach OpenRouter: offline');
    }
    return AssistantSummary(
      text:
          'cycleTime: fast, consistent cycles\n'
          'defense: plays it occasionally\n'
          'driverSkill: confident in traffic',
      generatedAt: DateTime.utc(2026, 8, 19),
      model: 'test-model',
      source: AssistantSource.openRouter,
    );
  }
}

void unawaited(Future<void> future) {}
