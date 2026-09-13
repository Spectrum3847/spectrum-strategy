import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/models/trex_assignments.dart';
import 'package:spectrumstrategy/src/state/trex_assignments_controller.dart';

import 'support/fake_trex_assignments_sync_service.dart';

void main() {
  late FakeTRexAssignmentsSyncService sync;
  late TRexAssignmentsController controller;

  setUp(() async {
    sync = FakeTRexAssignmentsSyncService();
    controller = TRexAssignmentsController(syncService: sync);
    await controller.bootstrap();
  });

  tearDown(() => controller.dispose());

  test('starts empty when no document exists yet', () {
    expect(controller.assignments.isEmpty, isTrue);
    expect(controller.isLoading, isFalse);
    expect(sync.initialized, isTrue);
  });

  group('columns', () {
    test('addColumn appends a trait column locally and pushes it', () async {
      await controller.addColumn('Defense');

      expect(controller.assignments.columns.single.name, 'Defense');
      expect(sync.pushes.single.columns.single.name, 'Defense');
    });

    test('blank column names are ignored', () async {
      await controller.addColumn('   ');

      expect(controller.assignments.columns, isEmpty);
      expect(sync.pushes, isEmpty);
    });

    test(
      'renameColumn changes the name without losing the key or names',
      () async {
        await controller.addColumn('Defense');
        final key = controller.assignments.columns.single.key;
        await controller.addName(key, 'Alex');

        await controller.renameColumn(key, 'Defensive skill');

        final column = controller.assignments.columns.single;
        expect(column.key, key);
        expect(column.name, 'Defensive skill');
        expect(column.names, ['Alex']);
      },
    );

    test(
      'renameColumn to a blank name is a no-op, not a nameless column',
      () async {
        await controller.addColumn('Defense');
        final key = controller.assignments.columns.single.key;
        final pushesBefore = sync.pushes.length;

        await controller.renameColumn(key, '   ');

        expect(controller.assignments.columns.single.name, 'Defense');
        expect(sync.pushes.length, pushesBefore);
      },
    );

    test('removeColumn drops the column and its names', () async {
      await controller.addColumn('Defense');
      final key = controller.assignments.columns.single.key;

      await controller.removeColumn(key);

      expect(controller.assignments.columns, isEmpty);
    });

    test('reorderColumns moves a column to a new position', () async {
      await controller.addColumn('Defense');
      await controller.addColumn('Auton');
      await controller.addColumn('Driver skill');

      await controller.reorderColumns(0, 2);

      expect(controller.assignments.columns.map((c) => c.name), [
        'Auton',
        'Defense',
        'Driver skill',
      ]);
    });
  });

  group('names', () {
    late String columnKey;

    setUp(() async {
      await controller.addColumn('Defense');
      columnKey = controller.assignments.columns.single.key;
    });

    test('addName appends a scouter to the column', () async {
      await controller.addName(columnKey, 'Alex');

      expect(controller.assignments.columns.single.names, ['Alex']);
    });

    test('renameName edits one entry in place', () async {
      await controller.addName(columnKey, 'Alex');

      await controller.renameName(columnKey, 0, 'Alexis');

      expect(controller.assignments.columns.single.names, ['Alexis']);
    });

    test(
      'renameName to a blank name is a no-op, not a nameless entry',
      () async {
        await controller.addName(columnKey, 'Alex');
        final pushesBefore = sync.pushes.length;

        await controller.renameName(columnKey, 0, '   ');

        expect(controller.assignments.columns.single.names, ['Alex']);
        expect(sync.pushes.length, pushesBefore);
      },
    );

    test('removeName drops one entry without disturbing the others', () async {
      await controller.addName(columnKey, 'Alex');
      await controller.addName(columnKey, 'Sam');

      await controller.removeName(columnKey, 0);

      expect(controller.assignments.columns.single.names, ['Sam']);
    });

    test('reorderNames moves a name within its column', () async {
      await controller.addName(columnKey, 'Alex');
      await controller.addName(columnKey, 'Sam');
      await controller.addName(columnKey, 'Jordan');

      await controller.reorderNames(columnKey, 0, 2);

      expect(controller.assignments.columns.single.names, [
        'Sam',
        'Alex',
        'Jordan',
      ]);
    });
  });

  group('writes', () {
    test('does not push a write the rules would reject', () async {
      final service = FakeTRexAssignmentsSyncService(uid: '');
      final c = TRexAssignmentsController(syncService: service);
      await c.bootstrap();

      await c.addColumn('Defense');

      expect(service.pushes, isEmpty);

      expect(c.assignments.columns.single.name, 'Defense');
      c.dispose();
    });

    test(
      'a failed push keeps the value on screen and does not stop the next one',
      () async {
        expect(controller.failedWrites.hasFailures, isFalse);

        sync.failNextPush = StateError('offline');
        await controller.addColumn('Defense');

        expect(controller.assignments.columns.single.name, 'Defense');
        expect(sync.pushes, isEmpty);
        expect(controller.failedWrites.hasFailures, isTrue);
        expect(controller.failedWrites.unlandedCount, 1);

        await controller.addColumn('Auton');

        expect(sync.pushes, hasLength(1));
        expect(controller.failedWrites.hasFailures, isFalse);
      },
    );

    test('two quick edits push in the order they were made', () async {
      final laggy = LaggyTRexAssignmentsSyncService();
      final c = TRexAssignmentsController(syncService: laggy);
      await c.bootstrap();

      final first = c.addColumn('Defense');
      final second = c.addColumn('Auton');
      await Future.wait([first, second]);

      expect(
        laggy.pushes.map((a) => a.columns.map((col) => col.name).toList()),
        [
          ['Defense'],
          ['Defense', 'Auton'],
        ],
      );
      c.dispose();
    });

    test('a queued write sends what it was given, not a later edit', () async {
      final laggy = LaggyTRexAssignmentsSyncService();
      final c = TRexAssignmentsController(syncService: laggy);
      await c.bootstrap();
      await c.addColumn('Defense');
      final key = c.assignments.columns.single.key;

      laggy.pushes.clear();

      final first = c.renameColumn(key, 'first');
      final second = c.renameColumn(key, 'second');
      await Future.wait([first, second]);

      expect(laggy.pushes.map((a) => a.columns.single.name), [
        'first',
        'second',
      ]);
      c.dispose();
    });
  });

  group('remote snapshots', () {
    test('a remote snapshot replaces the local table', () async {
      sync.emit(
        TRexAssignments(
          columns: const [
            TRexTraitColumn(key: 'k1', name: 'From another device'),
          ],
          updatedAt: DateTime.utc(2026, 8, 19),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.assignments.columns.single.name, 'From another device');
    });
  });

  group('addNames (#1410)', () {
    test('appends a pasted list in one push, not one per name', () async {
      await controller.addColumn('Defense');
      final key = controller.assignments.columns.single.key;
      final pushesBefore = sync.pushes.length;

      await controller.addNames(key, <String>['Ada', 'Grace', 'Alan']);

      expect(controller.assignments.columns.single.names, <String>[
        'Ada',
        'Grace',
        'Alan',
      ]);
      expect(sync.pushes.length, pushesBefore + 1);
    });

    test(
      'skips names the column already holds, matched case-insensitively',
      () async {
        await controller.addColumn('Defense');
        final key = controller.assignments.columns.single.key;
        await controller.addName(key, 'Ada');

        await controller.addNames(key, <String>['ada', 'Grace']);

        expect(controller.assignments.columns.single.names, <String>[
          'Ada',
          'Grace',
        ]);
      },
    );

    test('a list of nothing but blanks pushes nothing', () async {
      await controller.addColumn('Defense');
      final key = controller.assignments.columns.single.key;
      final pushesBefore = sync.pushes.length;

      await controller.addNames(key, <String>['  ', '']);

      expect(controller.assignments.columns.single.names, isEmpty);
      expect(sync.pushes.length, pushesBefore);
    });
  });
}
