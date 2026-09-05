import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/trex_team_list.dart';
import 'package:spectrumstrategy/src/state/trex_team_list_controller.dart';

import 'support/fake_trex_team_list_sync_service.dart';

void main() {
  late FakeTRexTeamListSyncService sync;
  late TRexTeamListController controller;

  setUp(() async {
    sync = FakeTRexTeamListSyncService();
    controller = TRexTeamListController(syncService: sync);
    await controller.bootstrap();
  });

  tearDown(() => controller.dispose());

  test('starts empty when no document exists yet', () {
    expect(controller.teamList.isEmpty, isTrue);
    expect(controller.isLoading, isFalse);
    expect(sync.initialized, isTrue);
  });

  test('setTitle pushes the new title', () async {
    await controller.setTitle('Pit Scouting Team Assignments');

    expect(controller.teamList.title, 'Pit Scouting Team Assignments');
    expect(sync.pushes.single.title, 'Pit Scouting Team Assignments');
  });

  group('columns', () {
    test('addColumn appends a column locally and pushes it', () async {
      await controller.addColumn('Defense');

      expect(controller.teamList.columns.single.name, 'Defense');
      expect(sync.pushes.single.columns.single.name, 'Defense');
    });

    test('blank column names are ignored', () async {
      await controller.addColumn('   ');

      expect(controller.teamList.columns, isEmpty);
      expect(sync.pushes, isEmpty);
    });

    test(
      'renameColumn changes the name without losing the key or teams',
      () async {
        await controller.addColumn('Defense');
        final key = controller.teamList.columns.single.key;
        await controller.addTeam(key, '118');

        await controller.renameColumn(key, 'Defensive skill');

        final column = controller.teamList.columns.single;
        expect(column.key, key);
        expect(column.name, 'Defensive skill');
        expect(column.teams, ['118']);
      },
    );

    test(
      'renameColumn to a blank name is a no-op, not a nameless column',
      () async {
        await controller.addColumn('Defense');
        final key = controller.teamList.columns.single.key;
        final pushesBefore = sync.pushes.length;

        await controller.renameColumn(key, '   ');

        expect(controller.teamList.columns.single.name, 'Defense');
        expect(sync.pushes.length, pushesBefore);
      },
    );

    test('removeColumn drops the column and its teams', () async {
      await controller.addColumn('Defense');
      final key = controller.teamList.columns.single.key;

      await controller.removeColumn(key);

      expect(controller.teamList.columns, isEmpty);
    });

    test('reorderColumns moves a column to a new position', () async {
      await controller.addColumn('Defense');
      await controller.addColumn('Auton');
      await controller.addColumn('Driver skill');

      await controller.reorderColumns(0, 2);

      expect(controller.teamList.columns.map((c) => c.name), [
        'Auton',
        'Defense',
        'Driver skill',
      ]);
    });
  });

  group('teams', () {
    late String columnKey;

    setUp(() async {
      await controller.addColumn('Defense');
      columnKey = controller.teamList.columns.single.key;
    });

    test('addTeam appends a team to the column', () async {
      await controller.addTeam(columnKey, '118');

      expect(controller.teamList.columns.single.teams, ['118']);
    });

    test('renameTeam edits one entry in place', () async {
      await controller.addTeam(columnKey, '118');

      await controller.renameTeam(columnKey, 0, '254');

      expect(controller.teamList.columns.single.teams, ['254']);
    });

    test('renameTeam to a blank value is a no-op, not a blank entry', () async {
      await controller.addTeam(columnKey, '118');
      final pushesBefore = sync.pushes.length;

      await controller.renameTeam(columnKey, 0, '   ');

      expect(controller.teamList.columns.single.teams, ['118']);
      expect(sync.pushes.length, pushesBefore);
    });

    test('removeTeam drops one entry without disturbing the others', () async {
      await controller.addTeam(columnKey, '118');
      await controller.addTeam(columnKey, '254');

      await controller.removeTeam(columnKey, 0);

      expect(controller.teamList.columns.single.teams, ['254']);
    });

    test('reorderTeams moves a team within its column', () async {
      await controller.addTeam(columnKey, '118');
      await controller.addTeam(columnKey, '254');
      await controller.addTeam(columnKey, '1678');

      await controller.reorderTeams(columnKey, 0, 2);

      expect(controller.teamList.columns.single.teams, ['254', '118', '1678']);
    });
  });

  group('writes', () {
    test('does not push a write the rules would reject', () async {
      final service = FakeTRexTeamListSyncService(uid: '');
      final c = TRexTeamListController(syncService: service);
      await c.bootstrap();

      await c.addColumn('Defense');

      expect(service.pushes, isEmpty);
      expect(c.teamList.columns.single.name, 'Defense');
      c.dispose();
    });

    test(
      'a failed push keeps the value on screen and does not stop the next one',
      () async {
        expect(controller.failedWrites.hasFailures, isFalse);

        sync.failNextPush = StateError('offline');
        await controller.addColumn('Defense');

        expect(controller.teamList.columns.single.name, 'Defense');
        expect(sync.pushes, isEmpty);
        expect(controller.failedWrites.hasFailures, isTrue);
        expect(controller.failedWrites.unlandedCount, 1);

        await controller.addColumn('Auton');

        expect(sync.pushes, hasLength(1));
        expect(controller.failedWrites.hasFailures, isFalse);
      },
    );

    test('two quick edits push in the order they were made', () async {
      final laggy = LaggyTRexTeamListSyncService();
      final c = TRexTeamListController(syncService: laggy);
      await c.bootstrap();

      final first = c.addColumn('Defense');
      final second = c.addColumn('Auton');
      await Future.wait([first, second]);

      expect(
        laggy.pushes.map((t) => t.columns.map((col) => col.name).toList()),
        [
          ['Defense'],
          ['Defense', 'Auton'],
        ],
      );
      c.dispose();
    });

    test('a queued write sends what it was given, not a later edit', () async {
      final laggy = LaggyTRexTeamListSyncService();
      final c = TRexTeamListController(syncService: laggy);
      await c.bootstrap();
      await c.addColumn('Defense');
      final key = c.teamList.columns.single.key;
      laggy.pushes.clear();

      final first = c.renameColumn(key, 'first');
      final second = c.renameColumn(key, 'second');
      await Future.wait([first, second]);

      expect(laggy.pushes.map((t) => t.columns.single.name), [
        'first',
        'second',
      ]);
      c.dispose();
    });
  });

  group('remote snapshots', () {
    test('a remote snapshot replaces the local table', () async {
      sync.emit(
        TRexTeamList(
          columns: const [
            TRexTeamListColumn(key: 'k1', name: 'From another device'),
          ],
          updatedAt: DateTime.utc(2026, 8, 21),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.teamList.columns.single.name, 'From another device');
    });
  });

  group('addTeams (#1410)', () {
    test('appends a pasted list in one push, not one per team', () async {
      await controller.addColumn('Defense');
      final key = controller.teamList.columns.single.key;
      final pushesBefore = sync.pushes.length;

      await controller.addTeams(key, <String>['3847', '254', '1678']);

      expect(controller.teamList.columns.single.teams, <String>[
        '3847',
        '254',
        '1678',
      ]);
      expect(sync.pushes.length, pushesBefore + 1);
    });

    test('skips teams the column already holds', () async {
      await controller.addColumn('Defense');
      final key = controller.teamList.columns.single.key;
      await controller.addTeam(key, '3847');

      await controller.addTeams(key, <String>['3847', '254']);

      expect(controller.teamList.columns.single.teams, <String>['3847', '254']);
    });
  });
}
