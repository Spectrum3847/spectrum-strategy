import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/models/pick_list.dart';
import 'package:spectrumstrategy/src/services/pick_list_storage.dart';
import 'package:spectrumstrategy/src/state/pick_list_controller.dart';

import 'support/fake_pick_list_sync_service.dart';

class _InMemoryStorage implements PickListStorage {
  final Map<String, PickList> data = <String, PickList>{};
  int saves = 0;
  int deletes = 0;

  @override
  Future<List<PickList>> loadAll() async =>
      data.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> save(PickList list) async {
    data[list.id] = list;
    saves++;
  }

  @override
  Future<void> delete(String id) async {
    data.remove(id);
    deletes++;
  }

  Set<String> syncedIds = <String>{};

  @override
  Future<Set<String>> loadSyncedIds() async => Set<String>.of(syncedIds);

  @override
  Future<void> saveSyncedIds(Set<String> ids) async {
    syncedIds = Set<String>.of(ids);
  }
}

class _FailingStorage extends _InMemoryStorage {
  bool failSaves = false;
  bool failDeletes = false;

  bool Function(PickList list)? failSaveWhen;

  @override
  Future<void> save(PickList list) async {
    if (failSaves || (failSaveWhen?.call(list) ?? false)) {
      throw StateError('disk full');
    }
    await super.save(list);
  }

  @override
  Future<void> delete(String id) async {
    if (failDeletes) throw StateError('disk full');
    await super.delete(id);
  }
}

void main() {
  test('PickList.fromJson clamps junk teamNumbers elements', () {
    final list = PickList.fromJson(<String, dynamic>{
      'id': 'a',
      'name': 'Picks',
      'teamNumbers': <dynamic>['junk', 3847, -5, 2714.0, null, 1000000],
      'updatedAt': '2026-06-27T00:00:00.000Z',
    });
    expect(list.teamNumbers, <int>[3847, 2714]);
  });

  test('PickList toJson/fromJson round-trips including author fields', () {
    final list = PickList(
      id: 'a',
      name: 'Picks',
      teamNumbers: const <int>[3847, 2714],
      updatedAt: DateTime.utc(2026, 6, 27),
      authorUid: 'uid-1',
      authorDisplayName: 'Scout McScoutface',
    );
    final round = PickList.fromJson(list.toJson());
    expect(round.id, 'a');
    expect(round.name, 'Picks');
    expect(round.teamNumbers, <int>[3847, 2714]);
    expect(round.updatedAt, DateTime.utc(2026, 6, 27));
    expect(round.authorUid, 'uid-1');
    expect(round.authorDisplayName, 'Scout McScoutface');
  });

  test('PickList toJson emits updatedAt in UTC ISO format', () {
    final list = PickList(
      id: 'b',
      name: 'Test',
      teamNumbers: const <int>[],
      updatedAt: DateTime.utc(2026, 6, 27, 12, 0, 0),
    );
    final json = list.toJson();
    expect(json['updatedAt'] as String, endsWith('Z'));
  });

  test('PickList fromJson defaults author fields to empty string', () {
    final list = PickList.fromJson(<String, dynamic>{
      'id': 'c',
      'name': 'No author',
      'teamNumbers': <int>[],
      'updatedAt': '2026-01-01T00:00:00.000Z',
    });
    expect(list.authorUid, '');
    expect(list.authorDisplayName, '');
  });

  group('PickListController', () {
    late _InMemoryStorage storage;
    late PickListController controller;
    late int counter;

    setUp(() {
      storage = _InMemoryStorage();
      counter = 0;
      controller = PickListController(
        storage: storage,
        idGenerator: () => 'id${counter++}',
        clock: () => DateTime.utc(2026, 6, 27),
      );
    });

    test('create adds a list and persists it', () async {
      await controller.bootstrap();
      final list = (await controller.create('My picks'))!;
      expect(controller.lists, hasLength(1));
      expect(list.name, 'My picks');
      expect(storage.saves, 1);
    });

    test('addTeam dedupes; reorder and removeTeam keep rank order', () async {
      await controller.bootstrap();
      final l = (await controller.create('Picks'))!;
      await controller.addTeam(l.id, 3847);
      await controller.addTeam(l.id, 2714);
      await controller.addTeam(l.id, 118);
      expect(controller.byId(l.id)!.teamNumbers, <int>[3847, 2714, 118]);

      await controller.addTeam(l.id, 3847);
      expect(controller.byId(l.id)!.teamNumbers, <int>[3847, 2714, 118]);

      await controller.reorder(l.id, 0, 2);
      expect(controller.byId(l.id)!.teamNumbers, <int>[2714, 118, 3847]);

      await controller.reorder(l.id, 2, 0);
      expect(controller.byId(l.id)!.teamNumbers, <int>[3847, 2714, 118]);

      await controller.removeTeam(l.id, 118);
      expect(controller.byId(l.id)!.teamNumbers, <int>[3847, 2714]);
    });

    test('delete removes the list', () async {
      await controller.bootstrap();
      final l = (await controller.create('Picks'))!;
      await controller.delete(l.id);
      expect(controller.lists, isEmpty);
      expect(storage.deletes, 1);
    });

    test('bootstrap loads persisted lists', () async {
      await storage.save(
        PickList(
          id: 'x',
          name: 'Old',
          teamNumbers: const <int>[9],
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await controller.bootstrap();
      expect(controller.lists.map((l) => l.id), <String>['x']);
    });
  });

  group('PickListController sync', () {
    late _InMemoryStorage storage;
    late FakePickListSyncService sync;
    late PickListController controller;
    late int counter;

    setUp(() {
      storage = _InMemoryStorage();
      counter = 0;
      sync = FakePickListSyncService(
        currentUserUid: 'uid-me',
        currentUserDisplayName: 'Me',
      );
      controller = PickListController(
        storage: storage,
        syncService: sync,
        idGenerator: () => 'id${counter++}',
        clock: () => DateTime.utc(2026, 6, 27),
      );
    });

    test('create stamps authorUid from currentUserUid and pushes', () async {
      await controller.bootstrap();
      (await controller.create('My list'))!;
      await Future<void>.delayed(Duration.zero);

      expect(sync.pushed, hasLength(1));
      expect(sync.pushed.first.authorUid, 'uid-me');
      expect(sync.pushed.first.authorDisplayName, 'Me');
    });

    test('rename pushes the whole updated snapshot', () async {
      await controller.bootstrap();
      final l = (await controller.create('List'))!;
      sync.pushed.clear();

      await controller.rename(l.id, 'Renamed');
      await Future<void>.delayed(Duration.zero);

      expect(sync.pushed, hasLength(1));
      expect(sync.pushed.first.name, 'Renamed');
    });

    test('addTeam mirrors as an item-level add, not a whole push', () async {
      await controller.bootstrap();
      final l = (await controller.create('List'))!;
      sync.pushed.clear();

      await controller.addTeam(l.id, 3847);
      await Future<void>.delayed(Duration.zero);

      expect(sync.pushed, isEmpty);
      expect(sync.teamAdds, hasLength(1));
      expect(sync.teamAdds.single.$2, 3847);
      expect(sync.teamAdds.single.$1.teamNumbers, contains(3847));
    });

    test('removeTeam mirrors as an item-level remove', () async {
      await controller.bootstrap();
      final l = (await controller.create('List'))!;
      await controller.addTeam(l.id, 3847);
      sync.pushed.clear();
      sync.teamAdds.clear();

      await controller.removeTeam(l.id, 3847);
      await Future<void>.delayed(Duration.zero);

      expect(sync.pushed, isEmpty);
      expect(sync.teamRemoves, hasLength(1));
      expect(sync.teamRemoves.single.$2, 3847);
      expect(sync.teamRemoves.single.$1.teamNumbers, isNot(contains(3847)));
    });

    test('reorder pushes the whole snapshot (last write wins)', () async {
      await controller.bootstrap();
      final l = (await controller.create('List'))!;
      await controller.addTeam(l.id, 111);
      await controller.addTeam(l.id, 254);
      sync.pushed.clear();
      sync.teamAdds.clear();

      await controller.reorder(l.id, 1, 0);
      await Future<void>.delayed(Duration.zero);

      expect(sync.teamAdds, isEmpty);
      expect(sync.pushed, hasLength(1));
      expect(sync.pushed.single.teamNumbers, <int>[254, 111]);
    });

    test('delete calls sync.delete', () async {
      await controller.bootstrap();
      final l = (await controller.create('List'))!;
      sync.pushed.clear();

      await controller.delete(l.id);
      await Future<void>.delayed(Duration.zero);

      expect(sync.deleted, hasLength(1));
      expect(sync.deleted.first.id, l.id);
    });

    test('mergeRemote adds new remote list', () async {
      await controller.bootstrap();

      final remote = PickList(
        id: 'remote-1',
        name: 'Remote list',
        teamNumbers: const <int>[254],
        updatedAt: DateTime.utc(2026, 6, 27),
        authorUid: 'uid-other',
        authorDisplayName: 'Teammate',
      );
      sync.emitRemote(<PickList>[remote]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.lists.any((l) => l.id == 'remote-1'), isTrue);
    });

    test(
      'a list that drops out of a later remote snapshot is removed',
      () async {
        await controller.bootstrap();

        final remote = PickList(
          id: 'remote-1',
          name: 'Remote list',
          teamNumbers: const <int>[254],
          updatedAt: DateTime.utc(2026, 6, 27),
          authorUid: 'uid-other',
          authorDisplayName: 'Teammate',
        );
        sync.emitRemote(<PickList>[remote]);
        await Future<void>.delayed(Duration.zero);
        expect(controller.lists, hasLength(1));

        sync.emitRemote(const <PickList>[]);
        await Future<void>.delayed(Duration.zero);

        expect(controller.lists, isEmpty);
        expect(storage.data, isEmpty);
      },
    );

    test('a local-only list survives remote snapshots that lack it', () async {
      await controller.bootstrap();
      (await controller.create('Offline list'))!;

      sync.emitRemote(const <PickList>[]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.lists, hasLength(1));
    });

    test('mergeRemote replaces local with newer remote (LWW)', () async {
      await controller.bootstrap();
      final l = (await controller.create('Local list'))!;

      final newerRemote = PickList(
        id: l.id,
        name: 'Updated remotely',
        teamNumbers: const <int>[9999],
        updatedAt: DateTime.utc(2026, 6, 28),
        authorUid: 'uid-me',
        authorDisplayName: 'Me',
      );
      sync.emitRemote(<PickList>[newerRemote]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.byId(l.id)!.name, 'Updated remotely');
    });

    test('mergeRemote ignores stale remote', () async {
      await controller.bootstrap();
      final l = (await controller.create('Fresh local'))!;

      final staleRemote = PickList(
        id: l.id,
        name: 'Stale remote',
        teamNumbers: const <int>[],
        updatedAt: DateTime.utc(2026, 6, 26),
        authorUid: 'uid-me',
        authorDisplayName: 'Me',
      );
      sync.emitRemote(<PickList>[staleRemote]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.byId(l.id)!.name, 'Fresh local');
    });

    test('remote list from another author appears in lists', () async {
      await controller.bootstrap();

      final other = PickList(
        id: 'other-1',
        name: 'Other team list',
        teamNumbers: const <int>[3847],
        updatedAt: DateTime.utc(2026, 6, 27),
        authorUid: 'uid-other',
        authorDisplayName: 'Teammate',
      );
      sync.emitRemote(<PickList>[other]);
      await Future<void>.delayed(Duration.zero);

      final found = controller.lists.firstWhere((l) => l.id == 'other-1');
      expect(found.authorUid, 'uid-other');
      expect(found.authorDisplayName, 'Teammate');
    });

    test(
      'mergeRemote accepts equal-timestamp snapshot with merged content',
      () async {
        await controller.bootstrap();
        final l = (await controller.create('List'))!;
        await controller.addTeam(l.id, 111);
        final local = controller.byId(l.id)!;

        final merged = PickList(
          id: l.id,
          name: local.name,
          teamNumbers: <int>[...local.teamNumbers, 254],
          updatedAt: local.updatedAt,
          authorUid: local.authorUid,
          authorDisplayName: local.authorDisplayName,
        );
        sync.emitRemote(<PickList>[merged]);
        await Future<void>.delayed(Duration.zero);

        expect(
          controller.byId(l.id)!.teamNumbers,
          containsAll(<int>[111, 254]),
        );
      },
    );

    test('mutate stamps strictly after a newer remote updatedAt', () async {
      await controller.bootstrap();

      final remote = PickList(
        id: 'remote-1',
        name: 'Remote',
        teamNumbers: const <int>[254],
        updatedAt: DateTime.utc(2026, 6, 28),
        authorUid: 'uid-other',
        authorDisplayName: 'Teammate',
      );
      sync.emitRemote(<PickList>[remote]);
      await Future<void>.delayed(Duration.zero);

      await controller.addTeam('remote-1', 3847);

      final updated = controller.byId('remote-1')!;
      expect(updated.updatedAt.isAfter(DateTime.utc(2026, 6, 28)), isTrue);
    });
  });

  group('rollback on a failed local write', () {
    test('a failed delete puts the list back and reports why', () async {
      final storage = _FailingStorage();
      final controller = PickListController(storage: storage);
      await controller.bootstrap();
      final list = (await controller.create('Picks'))!;

      storage.failDeletes = true;
      await controller.delete(list.id);

      expect(controller.byId(list.id), isNotNull);
      expect(controller.lastError, contains('Picks'));

      expect(storage.data.containsKey(list.id), isTrue);
    });

    test('a failed save restores the previous value', () async {
      final storage = _FailingStorage();
      final controller = PickListController(storage: storage);
      await controller.bootstrap();
      final list = (await controller.create('Picks'))!;
      await controller.addTeam(list.id, 3847);

      storage.failSaves = true;
      await controller.addTeam(list.id, 254);

      expect(controller.byId(list.id)!.teamNumbers, <int>[3847]);
      expect(controller.lastError, isNotNull);
    });

    test(
      'a failed write does not roll back onto an unconfirmed value',
      () async {
        final storage = _FailingStorage();
        final controller = PickListController(storage: storage);
        await controller.bootstrap();
        final list = (await controller.create('Picks'))!;

        await controller.addTeam(list.id, 254);

        storage.failSaves = true;
        final failingB = controller.addTeam(list.id, 100);
        final failingC = controller.addTeam(list.id, 200);
        await Future.wait(<Future<void>>[failingB, failingC]);

        expect(controller.byId(list.id)!.teamNumbers, <int>[254]);
        expect(controller.lastError, isNotNull);
      },
    );

    test('a successful write leaves no error behind', () async {
      final storage = _FailingStorage();
      final controller = PickListController(storage: storage);
      await controller.bootstrap();
      final list = (await controller.create('Picks'))!;
      await controller.addTeam(list.id, 3847);

      expect(controller.lastError, isNull);
      expect(controller.byId(list.id)!.teamNumbers, <int>[3847]);
    });

    test('clearLastError clears it', () async {
      final storage = _FailingStorage();
      final controller = PickListController(storage: storage);
      await controller.bootstrap();
      final list = (await controller.create('Picks'))!;

      storage.failDeletes = true;
      await controller.delete(list.id);
      expect(controller.lastError, isNotNull);

      controller.clearLastError();
      expect(controller.lastError, isNull);
    });

    test('a stale rollback does not overwrite a newer edit', () async {
      final storage = _FailingStorage();
      final controller = PickListController(storage: storage);
      await controller.bootstrap();
      final list = (await controller.create('Picks'))!;

      var failed = false;
      storage.failSaveWhen = (l) {
        if (failed || !l.teamNumbers.contains(254)) return false;
        failed = true;
        return true;
      };
      final failing = controller.addTeam(list.id, 254);
      await controller.rename(list.id, 'Renamed');
      await failing;

      expect(controller.byId(list.id)!.name, 'Renamed');

      expect(controller.lastError, isNotNull);
    });
  });

  group('rollback edge cases', () {
    test(
      'a failed create takes the list back out and pushes nothing',
      () async {
        final storage = _FailingStorage()..failSaves = true;
        final sync = FakePickListSyncService();
        final controller = PickListController(
          storage: storage,
          syncService: sync,
        );
        await controller.bootstrap();

        final list = await controller.create('Picks');

        expect(list, isNull);
        expect(controller.lists, isEmpty);
        expect(controller.lastError, contains('Picks'));

        expect(sync.pushed, isEmpty);
      },
    );

    test(
      'a failed delete of a synced list restores the synced set on disk',
      () async {
        final storage = _FailingStorage();
        final sync = FakePickListSyncService();
        final controller = PickListController(
          storage: storage,
          syncService: sync,
        );
        await controller.bootstrap();
        final list = (await controller.create('Picks'))!;
        sync.emitRemote(<PickList>[list]);

        await pumpEventQueue();
        expect(storage.syncedIds, contains(list.id));

        storage.failDeletes = true;
        expect(await controller.delete(list.id), isFalse);
        await pumpEventQueue();

        expect(controller.byId(list.id), isNotNull);
        expect(storage.syncedIds, contains(list.id));
      },
    );

    test('delete reports success and failure through its own result', () async {
      final storage = _FailingStorage();
      final controller = PickListController(storage: storage);
      await controller.bootstrap();
      final list = (await controller.create('Picks'))!;

      storage.failDeletes = true;
      expect(await controller.delete(list.id), isFalse);

      storage.failDeletes = false;
      expect(await controller.delete(list.id), isTrue);

      expect(await controller.delete(list.id), isTrue);
    });

    test('a remote update is not rolled back over', () async {
      final storage = _FailingStorage();
      final sync = FakePickListSyncService();
      final controller = PickListController(
        storage: storage,
        syncService: sync,
      );
      await controller.bootstrap();
      final list = (await controller.create('Picks'))!;

      var failed = false;
      storage.failSaveWhen = (l) {
        if (failed || !l.teamNumbers.contains(254)) return false;
        failed = true;
        return true;
      };
      final failing = controller.addTeam(list.id, 254);
      sync.emitRemote(<PickList>[
        list.copyWith(
          name: 'From another device',
          updatedAt: list.updatedAt.add(const Duration(minutes: 1)),
        ),
      ]);
      await failing;
      await pumpEventQueue();

      expect(controller.byId(list.id)!.name, 'From another device');
    });
  });
}
