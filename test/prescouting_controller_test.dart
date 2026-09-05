import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/prescout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/prescouting_storage.dart';
import 'package:spectrumstrategy/src/scouting/services/prescouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/prescouting_controller.dart';

import 'support/fake_prescouting_sync_service.dart';

class _InMemoryStorage implements PrescoutingStorage {
  final Map<String, PrescoutEntry> data = <String, PrescoutEntry>{};
  int loads = 0;
  int saves = 0;
  int deletes = 0;

  @override
  Future<List<PrescoutEntry>> loadAll() async {
    loads++;
    return data.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<void> saveEntry(PrescoutEntry entry) async {
    data[entry.id] = entry;
    saves++;
  }

  @override
  Future<void> deleteEntry(String id) async {
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

class _FlakyStorage extends _InMemoryStorage {
  bool failNextSave = false;

  bool failSaves = false;

  @override
  Future<void> saveEntry(PrescoutEntry entry) async {
    if (failSaves) {
      throw StateError('simulated storage failure');
    }
    if (failNextSave) {
      failNextSave = false;
      throw StateError('simulated storage failure');
    }
    await super.saveEntry(entry);
  }
}

class _GatedStorage extends _InMemoryStorage {
  final List<PrescoutEntry> savedEntries = <PrescoutEntry>[];
  Completer<void>? firstSaveGate;

  @override
  Future<void> saveEntry(PrescoutEntry entry) async {
    savedEntries.add(entry);
    final gate = firstSaveGate;
    if (gate != null) {
      await gate.future;
    }
    await super.saveEntry(entry);
  }
}

void main() {
  group('PrescoutingController (local-only)', () {
    late _InMemoryStorage storage;
    late PrescoutingController controller;

    setUp(() {
      storage = _InMemoryStorage();
      controller = PrescoutingController(storage: storage);
    });

    tearDown(() => controller.dispose());

    test('bootstrap loads stored entries and sets isReady', () async {
      await storage.saveEntry(
        PrescoutEntry(
          id: 'e1',
          teamNumber: 3847,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await controller.bootstrap();
      expect(controller.isReady, isTrue);
      expect(controller.entries.any((e) => e.id == 'e1'), isTrue);
    });

    test('bootstrap is idempotent', () async {
      final first = controller.bootstrap();
      final second = controller.bootstrap();
      expect(second, same(first));
      await Future.wait(<Future<void>>[first, second]);
      expect(controller.isReady, isTrue);
      expect(storage.loads, 1);
    });

    test('saveEntry persists and appears in entries', () async {
      await controller.bootstrap();
      final entry = PrescoutEntry(id: 'a', teamNumber: 254);
      await controller.saveEntry(entry);
      expect(controller.entries.any((e) => e.id == 'a'), isTrue);
      expect(storage.saves, greaterThanOrEqualTo(1));
    });

    test('saveEntry stamps a fresh UTC updatedAt', () async {
      await controller.bootstrap();
      final before = DateTime.now().toUtc().subtract(
        const Duration(seconds: 1),
      );
      final entry = PrescoutEntry(
        id: 'b',
        teamNumber: 1,
        updatedAt: DateTime.utc(2000),
      );
      await controller.saveEntry(entry);
      final saved = controller.entries.firstWhere((e) => e.id == 'b');
      expect(saved.updatedAt.isAfter(before), isTrue);
      expect(saved.updatedAt.isUtc, isTrue);
    });

    test('saves complete in call order when storage stalls', () async {
      final gated = _GatedStorage();
      final local = PrescoutingController(storage: gated);
      await local.bootstrap();

      gated.firstSaveGate = Completer<void>();
      final first = local.saveEntry(
        PrescoutEntry(id: 'p1', teamNumber: 1, eventKey: 'first'),
      );
      await Future<void>.delayed(Duration.zero);
      final second = local.saveEntry(
        PrescoutEntry(id: 'p2', teamNumber: 2, eventKey: 'second'),
      );

      expect(gated.savedEntries, hasLength(1));

      gated.firstSaveGate!.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(gated.savedEntries.map((e) => e.eventKey), <String>[
        'first',
        'second',
      ]);
      local.dispose();
    });

    test('persisted snapshots reflect state at enqueue time', () async {
      final gated = _GatedStorage();
      final local = PrescoutingController(storage: gated);
      await local.bootstrap();

      gated.firstSaveGate = Completer<void>();
      final entry = PrescoutEntry(
        id: 'p1',
        teamNumber: 3847,
        fieldValues: <String, dynamic>{'note': 'first'},
      );
      final first = local.saveEntry(entry);
      await Future<void>.delayed(Duration.zero);
      final second = local.saveEntry(
        entry.copyWith(fieldValues: <String, dynamic>{'note': 'second'}),
      );

      gated.firstSaveGate!.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(gated.savedEntries, hasLength(2));
      expect(gated.savedEntries[0].fieldValues['note'], 'first');
      expect(gated.savedEntries[1].fieldValues['note'], 'second');
      expect(local.entries.single.fieldValues['note'], 'second');
      local.dispose();
    });

    test('deleteEntry removes from entries and storage', () async {
      await controller.bootstrap();
      final entry = PrescoutEntry(id: 'c', teamNumber: 9);
      await controller.saveEntry(entry);
      await controller.deleteEntry('c');
      expect(controller.entries.any((e) => e.id == 'c'), isFalse);
      expect(storage.deletes, 1);
    });

    test('entriesForTeam filters by team number', () async {
      await controller.bootstrap();
      await controller.saveEntry(PrescoutEntry(id: 'p1', teamNumber: 3847));
      await controller.saveEntry(PrescoutEntry(id: 'p2', teamNumber: 254));
      await controller.saveEntry(PrescoutEntry(id: 'p3', teamNumber: 3847));
      final team3847 = controller.entriesForTeam(3847);
      expect(team3847.length, 2);
      expect(team3847.every((e) => e.teamNumber == 3847), isTrue);
    });

    test('local-only: no sync service, no push attempted', () async {
      await controller.bootstrap();

      await controller.saveEntry(PrescoutEntry(id: 'd', teamNumber: 1));
      expect(controller.syncStatus.state, PrescoutingSyncState.signedOut);
    });
  });

  group('PrescoutingController sync', () {
    late _InMemoryStorage storage;
    late FakePrescoutingSyncService sync;
    late PrescoutingController controller;

    setUp(() {
      storage = _InMemoryStorage();
      sync = FakePrescoutingSyncService(
        currentUserUid: 'uid-me',
        currentUserDisplayName: 'Scout',
      );
      controller = PrescoutingController(storage: storage, syncService: sync);
    });

    tearDown(() => controller.dispose());

    test('saveEntry pushes to sync service', () async {
      await controller.bootstrap();
      final entry = PrescoutEntry(id: 'e1', teamNumber: 3847);
      await controller.saveEntry(entry);
      await Future<void>.delayed(Duration.zero);
      expect(sync.pushed, hasLength(1));
      expect(sync.pushed.first.id, 'e1');
    });

    test('saveEntry stamps the signed-in user onto the local copy, not just '
        'the copy pushed to sync', () async {
      await controller.bootstrap();

      final entry = PrescoutEntry(id: 'e1', teamNumber: 3847);
      await controller.saveEntry(entry);
      await Future<void>.delayed(Duration.zero);

      final local = controller.entries.single;
      expect(local.authorUid, 'uid-me');
      expect(local.authorDisplayName, 'Scout');
    });

    test('saveEntry keeps an existing author when editing', () async {
      await controller.bootstrap();
      final entry = PrescoutEntry(
        id: 'e1',
        teamNumber: 3847,
        authorUid: 'uid-other',
        authorDisplayName: 'Teammate',
      );
      await controller.saveEntry(entry);
      await Future<void>.delayed(Duration.zero);

      expect(controller.entries.single.authorUid, 'uid-other');
      expect(controller.entries.single.authorDisplayName, 'Teammate');
    });

    test('deleteEntry calls sync.delete', () async {
      await controller.bootstrap();
      final entry = PrescoutEntry(id: 'e2', teamNumber: 254);
      await controller.saveEntry(entry);
      sync.pushed.clear();
      await controller.deleteEntry('e2');
      await Future<void>.delayed(Duration.zero);
      expect(sync.deleted, hasLength(1));
      expect(sync.deleted.first.id, 'e2');
    });

    test('mergeRemote adds new entry from remote', () async {
      await controller.bootstrap();
      final remote = PrescoutEntry(
        id: 'remote-1',
        teamNumber: 118,
        updatedAt: DateTime.utc(2026, 6, 27),
        authorUid: 'uid-other',
        authorDisplayName: 'Teammate',
      );
      sync.emitRemote(<PrescoutEntry>[remote]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.entries.any((e) => e.id == 'remote-1'), isTrue);
    });

    test('mergeRemote replaces local with newer remote (LWW)', () async {
      await controller.bootstrap();
      final local = PrescoutEntry(
        id: 'shared',
        teamNumber: 3847,
        fieldValues: <String, dynamic>{'drivetrainType': 'tank'},
        updatedAt: DateTime.utc(2026, 6, 26),
      );
      await controller.saveEntry(local);

      final newerRemote = PrescoutEntry(
        id: 'shared',
        teamNumber: 3847,
        fieldValues: <String, dynamic>{'drivetrainType': 'swerve'},
        updatedAt: DateTime.now().toUtc().add(const Duration(days: 1)),
        authorUid: 'uid-me',
        authorDisplayName: 'Scout',
      );
      sync.emitRemote(<PrescoutEntry>[newerRemote]);
      await Future<void>.delayed(Duration.zero);

      final found = controller.entries.firstWhere((e) => e.id == 'shared');
      expect(found.fieldValues['drivetrainType'], 'swerve');
    });

    test('mergeRemote ignores stale remote', () async {
      await controller.bootstrap();
      final local = PrescoutEntry(
        id: 'fresh',
        teamNumber: 1,
        fieldValues: <String, dynamic>{'note': 'local'},
        updatedAt: DateTime.utc(2026, 6, 27),
      );
      await controller.saveEntry(local);

      final staleRemote = PrescoutEntry(
        id: 'fresh',
        teamNumber: 1,
        fieldValues: <String, dynamic>{'note': 'old remote'},
        updatedAt: DateTime.utc(2026, 6, 26),
        authorUid: 'uid-me',
        authorDisplayName: 'Scout',
      );
      sync.emitRemote(<PrescoutEntry>[staleRemote]);
      await Future<void>.delayed(Duration.zero);

      final found = controller.entries.firstWhere((e) => e.id == 'fresh');

      expect(found.updatedAt.isAfter(DateTime.utc(2026, 6, 26)), isTrue);
    });

    test(
      'an entry that drops out of a later remote snapshot is removed',
      () async {
        await controller.bootstrap();
        final remote = PrescoutEntry(
          id: 'remote-1',
          teamNumber: 118,
          updatedAt: DateTime.utc(2026, 6, 27),
          authorUid: 'uid-other',
          authorDisplayName: 'Teammate',
        );
        sync.emitRemote(<PrescoutEntry>[remote]);
        await Future<void>.delayed(Duration.zero);
        expect(controller.entries, hasLength(1));

        sync.emitRemote(const <PrescoutEntry>[]);
        await Future<void>.delayed(Duration.zero);

        expect(controller.entries, isEmpty);
        expect(storage.data, isEmpty);
      },
    );

    test('a local-only entry survives remote snapshots that lack it', () async {
      await controller.bootstrap();
      await controller.saveEntry(PrescoutEntry(id: 'local-1', teamNumber: 971));

      sync.emitRemote(const <PrescoutEntry>[]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.entries, hasLength(1));
    });

    test('a failed save does not wedge the save queue', () async {
      final flaky = _FlakyStorage();
      final local = PrescoutingController(storage: flaky);
      await local.bootstrap();

      flaky.failNextSave = true;
      await local.saveEntry(PrescoutEntry(id: 'p1', teamNumber: 1));
      await local.saveEntry(PrescoutEntry(id: 'p2', teamNumber: 2));
      await Future<void>.delayed(Duration.zero);

      expect(flaky.data.containsKey('p2'), isTrue);
      local.dispose();
    });

    test(
      'a failed save marks failedWrites, and a later success clears it',
      () async {
        final flaky = _FlakyStorage();
        final local = PrescoutingController(storage: flaky);
        await local.bootstrap();
        expect(local.failedWrites.hasFailures, isFalse);

        flaky.failNextSave = true;
        await local.saveEntry(PrescoutEntry(id: 'p1', teamNumber: 1));

        expect(local.failedWrites.hasFailures, isTrue);
        expect(local.failedWrites.unlandedCount, 1);

        await local.saveEntry(PrescoutEntry(id: 'p2', teamNumber: 2));

        expect(local.failedWrites.hasFailures, isFalse);
        local.dispose();
      },
    );

    test(
      'a failed write does not roll back onto an unconfirmed value',
      () async {
        final flaky = _FlakyStorage();
        final local = PrescoutingController(storage: flaky);
        await local.bootstrap();

        final entryA = PrescoutEntry(
          id: 'p1',
          teamNumber: 1,
          fieldValues: <String, dynamic>{'drivetrainType': 'A'},
        );
        expect(await local.saveEntry(entryA), isTrue);

        flaky.failSaves = true;
        final savedB = local.saveEntry(
          entryA.copyWith(
            fieldValues: <String, dynamic>{'drivetrainType': 'B'},
          ),
        );
        final savedC = local.saveEntry(
          entryA.copyWith(
            fieldValues: <String, dynamic>{'drivetrainType': 'C'},
          ),
        );

        expect(await savedB, isFalse);
        expect(await savedC, isFalse);
        expect(local.entries.single.fieldValues['drivetrainType'], 'A');
        local.dispose();
      },
    );

    test('currentUserUid proxies sync service', () async {
      await controller.bootstrap();
      expect(controller.currentUserUid, 'uid-me');
    });
  });
}
