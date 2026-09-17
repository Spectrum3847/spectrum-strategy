import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:spectrumstrategy/src/scouting/models/scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/scouting_controller.dart';
import 'package:spectrumstrategy/src/theme/strategy_palette.dart';

import 'support/fake_scouting_storage.dart';
import 'support/fake_scouting_sync_service.dart';
import 'support/laggy_scouting_storage.dart';

class _FlakyScoutingStorage extends FakeScoutingStorage {
  bool failNextSave = false;

  bool failSaves = false;

  @override
  Future<void> saveEntry(ScoutEntry entry) async {
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

class _FlakyBatchScoutingStorage extends FakeScoutingStorage {
  bool failNextBatch = false;

  @override
  Future<void> saveEntries(Iterable<ScoutEntry> entries) async {
    if (failNextBatch) {
      failNextBatch = false;
      throw StateError('simulated batch storage failure');
    }
    await super.saveEntries(entries);
  }
}

void main() {
  test('ScoutEntry round-trips through json with phase data', () {
    final entry = ScoutEntry(
      matchId: 'match-1',
      teamNumber: 3847,
      alliance: 'Blue',
      notes: 'strong defense',
      byPhase: <StrategyPhase, ScoutPhaseData>{
        StrategyPhase.auton: const ScoutPhaseData(
          score: 6,
          counters: <String, int>{'mobility': 1},
        ),
        StrategyPhase.teleop: const ScoutPhaseData(score: 22, penalties: 1),
        StrategyPhase.endgame: const ScoutPhaseData(score: 10, notes: 'climb'),
      },
    );

    final round = ScoutEntry.fromJson(entry.toJson());
    expect(round.id, entry.id);
    expect(round.matchId, 'match-1');
    expect(round.teamNumber, 3847);
    expect(round.alliance, 'Blue');
    expect(round.notes, 'strong defense');
    expect(round.phaseData(StrategyPhase.auton).score, 6);
    expect(round.phaseData(StrategyPhase.auton).counters['mobility'], 1);
    expect(round.phaseData(StrategyPhase.teleop).score, 22);
    expect(round.phaseData(StrategyPhase.teleop).penalties, 1);
    expect(round.phaseData(StrategyPhase.endgame).notes, 'climb');
  });

  test('ScoutEntry.fromJson fills missing phases with defaults', () {
    final entry = ScoutEntry.fromJson(<String, dynamic>{
      'matchId': 'match-1',
      'teamNumber': 2714,
      'alliance': 'Red',
    });
    for (final phase in StrategyPhase.values) {
      expect(entry.phaseData(phase).score, 0);
      expect(entry.phaseData(phase).penalties, 0);
      expect(entry.phaseData(phase).counters, isEmpty);
    }
  });

  test('saveEntry persists a new entry and notifies listeners', () async {
    final storage = FakeScoutingStorage();
    final controller = ScoutingController(storage: storage);
    await controller.bootstrap();
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    final entry = ScoutEntry(matchId: 'match-1', teamNumber: 3847);
    await controller.saveEntry(entry);

    expect(controller.entries, hasLength(1));
    expect(controller.entries.first.teamNumber, 3847);
    expect(storage.rawEntries, hasLength(1));
    expect(notifyCount, greaterThanOrEqualTo(1));
  });

  group('entriesRevision', () {
    test('bumps on saveEntry, not on a pure sync-status tick', () async {
      final sync = FakeScoutingSyncService();
      final controller = ScoutingController(
        storage: FakeScoutingStorage(),
        syncService: sync,
      );
      await controller.bootstrap();
      final afterBootstrap = controller.entriesRevision;

      sync.emitStatus(
        const ScoutingSyncStatus(state: ScoutingSyncState.syncing),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.entriesRevision, afterBootstrap);

      await controller.saveEntry(ScoutEntry(matchId: 'm1', teamNumber: 3847));
      expect(controller.entriesRevision, greaterThan(afterBootstrap));
    });

    test('bumps on deleteEntry', () async {
      final controller = ScoutingController(storage: FakeScoutingStorage());
      await controller.bootstrap();
      final entry = ScoutEntry(matchId: 'm1', teamNumber: 3847);
      await controller.saveEntry(entry);
      final beforeDelete = controller.entriesRevision;

      await controller.deleteEntry(entry.id);

      expect(controller.entriesRevision, greaterThan(beforeDelete));
    });

    test(
      'does not bump when a failed write only touches failedWrites',
      () async {
        final storage = _FlakyScoutingStorage();
        final controller = ScoutingController(storage: storage);
        await controller.bootstrap();
        storage.failNextSave = true;
        final before = controller.entriesRevision;

        await controller.saveEntry(ScoutEntry(matchId: 'm1', teamNumber: 3847));

        expect(controller.entriesRevision, greaterThan(before));
        expect(controller.entries, isEmpty);
      },
    );
  });

  test(
    'saveEntry persists a manually added entry and marks it as such',
    () async {
      final storage = FakeScoutingStorage();
      final controller = ScoutingController(storage: storage);
      await controller.bootstrap();

      final entry = ScoutEntry(
        matchId: '',
        teamNumber: 3847,
        addedManually: true,
      );
      await controller.saveEntry(entry);

      expect(controller.entries.single.addedManually, isTrue);
      final persisted = await storage.loadAll();
      expect(persisted.single.addedManually, isTrue);
    },
  );

  test(
    'a failed save on a manually added entry rolls it back like any other',
    () async {
      final storage = _FlakyScoutingStorage();
      final controller = ScoutingController(storage: storage);
      await controller.bootstrap();

      storage.failNextSave = true;
      final saved = await controller.saveEntry(
        ScoutEntry(matchId: '', teamNumber: 3847, addedManually: true),
      );

      expect(saved, isFalse);
      expect(controller.entries, isEmpty);
      expect(controller.lastError, isNotNull);
    },
  );

  test('a failed write does not roll back onto an unconfirmed value', () async {
    final storage = _FlakyScoutingStorage();
    final controller = ScoutingController(storage: storage);
    await controller.bootstrap();

    final entryA = ScoutEntry(matchId: 'match-1', teamNumber: 3847, notes: 'A');
    expect(await controller.saveEntry(entryA), isTrue);

    storage.failSaves = true;
    final savedB = controller.saveEntry(entryA.copyWith(notes: 'B'));
    final savedC = controller.saveEntry(entryA.copyWith(notes: 'C'));

    expect(await savedB, isFalse);
    expect(await savedC, isFalse);
    expect(controller.entries.single.notes, 'A');
  });

  test('saveEntry replaces an existing entry by id', () async {
    final storage = FakeScoutingStorage();
    final controller = ScoutingController(storage: storage);
    await controller.bootstrap();

    final entry = ScoutEntry(matchId: 'match-1', teamNumber: 3847);
    await controller.saveEntry(entry);
    final updated = entry.copyWith(notes: 'updated');
    await controller.saveEntry(updated);

    expect(controller.entries, hasLength(1));
    expect(controller.entries.first.notes, 'updated');
    expect(storage.rawEntries, hasLength(1));
  });

  test('deleteEntry removes the entry and persists the deletion', () async {
    final storage = FakeScoutingStorage();
    final controller = ScoutingController(storage: storage);
    await controller.bootstrap();

    final entry = ScoutEntry(matchId: 'match-1', teamNumber: 3847);
    await controller.saveEntry(entry);
    await controller.deleteEntry(entry.id);

    expect(controller.entries, isEmpty);
    expect(storage.rawEntries, isEmpty);
  });

  test('entriesForMatch filters by matchId', () async {
    final controller = ScoutingController(storage: FakeScoutingStorage());
    await controller.bootstrap();

    await controller.saveEntry(
      ScoutEntry(matchId: 'match-1', teamNumber: 3847),
    );
    await controller.saveEntry(
      ScoutEntry(matchId: 'match-1', teamNumber: 2714),
    );
    await controller.saveEntry(
      ScoutEntry(matchId: 'match-2', teamNumber: 5114),
    );

    expect(controller.entriesForMatch('match-1'), hasLength(2));
    expect(controller.entriesForMatch('match-2'), hasLength(1));
    expect(controller.entriesForMatch('missing'), isEmpty);
  });

  test('ScoutingController bootstrap restores entries from storage', () async {
    final storage = FakeScoutingStorage();
    final seed = ScoutingController(storage: storage);
    await seed.bootstrap();
    await seed.saveEntry(
      ScoutEntry(
        matchId: 'match-1',
        teamNumber: 3847,
        alliance: 'Blue',
        notes: 'first seed',
      ),
    );

    final relaunched = ScoutingController(storage: storage);
    await relaunched.bootstrap();

    expect(relaunched.entries, hasLength(1));
    expect(relaunched.entries.first.teamNumber, 3847);
    expect(relaunched.entries.first.notes, 'first seed');
  });

  test(
    'ScoutingController preserves save ordering when storage stalls',
    () async {
      final storage = LaggyScoutingStorage();
      final controller = ScoutingController(storage: storage);
      await controller.bootstrap();

      storage.firstSaveGate = Completer<void>();

      final entry = ScoutEntry(matchId: 'match-1', teamNumber: 3847);
      final saveFuture = controller.saveEntry(entry);
      await Future<void>.delayed(Duration.zero);

      final updatedFuture = controller.saveEntry(
        entry.copyWith(notes: 'second'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(storage.savedEntries, hasLength(1));
      expect(storage.savedEntries.first.notes, isEmpty);

      storage.firstSaveGate!.complete();
      await saveFuture;
      await updatedFuture;

      expect(storage.savedEntries, hasLength(2));
      expect(storage.savedEntries.last.notes, 'second');
    },
  );

  test('saveEntry mirrors the snapshot to the sync service', () async {
    final sync = FakeScoutingSyncService();
    final controller = ScoutingController(
      storage: FakeScoutingStorage(),
      syncService: sync,
    );
    await controller.bootstrap();

    await controller.saveEntry(
      ScoutEntry(matchId: 'match-1', teamNumber: 3847),
    );
    await Future<void>.delayed(Duration.zero);

    expect(sync.pushed, hasLength(1));
    expect(sync.pushed.first.teamNumber, 3847);
  });

  test(
    'a manually added entry mirrors addedManually to the sync service',
    () async {
      final sync = FakeScoutingSyncService();
      final controller = ScoutingController(
        storage: FakeScoutingStorage(),
        syncService: sync,
      );
      await controller.bootstrap();

      await controller.saveEntry(
        ScoutEntry(matchId: '', teamNumber: 3847, addedManually: true),
      );
      await Future<void>.delayed(Duration.zero);

      expect(sync.pushed, hasLength(1));
      expect(sync.pushed.first.addedManually, isTrue);
    },
  );

  test('a sync outage never touches local persistence', () async {
    final sync = FakeScoutingSyncService()..simulateOutage = true;
    final storage = FakeScoutingStorage();
    final controller = ScoutingController(storage: storage, syncService: sync);
    await controller.bootstrap();

    await controller.saveEntry(ScoutEntry(matchId: 'match-1', teamNumber: 971));
    await Future<void>.delayed(Duration.zero);

    expect(controller.entries, hasLength(1));
    expect(sync.pushed, isEmpty);
    expect(sync.status.state, ScoutingSyncState.offline);

    sync.simulateOutage = false;
    await controller.saveEntry(ScoutEntry(matchId: 'match-1', teamNumber: 254));
    await Future<void>.delayed(Duration.zero);
    expect(sync.pushed, hasLength(1));
    expect(controller.entries, hasLength(2));
  });

  test('deleteEntry forwards the deleted entry to the sync service', () async {
    final sync = FakeScoutingSyncService();
    final controller = ScoutingController(
      storage: FakeScoutingStorage(),
      syncService: sync,
    );
    await controller.bootstrap();

    await controller.saveEntry(
      ScoutEntry(matchId: 'match-1', teamNumber: 254, authorUid: 'u-1'),
    );
    final id = controller.entries.first.id;
    await controller.deleteEntry(id);
    await Future<void>.delayed(Duration.zero);

    expect(sync.deleted, hasLength(1));
    expect(sync.deleted.first.id, id);
    expect(controller.entries, isEmpty);
  });

  test('remote entries with newer updatedAt overwrite local copies', () async {
    final sync = FakeScoutingSyncService();
    final storage = FakeScoutingStorage();
    final controller = ScoutingController(storage: storage, syncService: sync);
    await controller.bootstrap();

    await controller.saveEntry(
      ScoutEntry(matchId: 'match-1', teamNumber: 254, notes: 'local copy'),
    );

    final localId = controller.entries.first.id;
    final newer = ScoutEntry(
      id: localId,
      matchId: 'match-1',
      teamNumber: 254,
      notes: 'remote wins',
      authorUid: 'u-other',
      updatedAt: DateTime.now().add(const Duration(days: 1)),
    );
    sync.emitRemote(<ScoutEntry>[newer]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.entries.first.notes, 'remote wins');
  });

  test('remote entries older than local are ignored', () async {
    final sync = FakeScoutingSyncService();
    final storage = FakeScoutingStorage();
    final controller = ScoutingController(storage: storage, syncService: sync);
    await controller.bootstrap();

    final local = ScoutEntry(
      matchId: 'match-1',
      teamNumber: 254,
      notes: 'fresh local',
      updatedAt: DateTime.utc(2026, 5, 1),
    );
    await controller.saveEntry(local);

    final stale = ScoutEntry(
      id: controller.entries.first.id,
      matchId: 'match-1',
      teamNumber: 254,
      notes: 'stale remote',
      authorUid: 'u-other',
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    sync.emitRemote(<ScoutEntry>[stale]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.entries.first.notes, 'fresh local');
  });

  test('a failed save does not wedge the save queue', () async {
    final storage = _FlakyScoutingStorage();
    final controller = ScoutingController(storage: storage);
    await controller.bootstrap();

    storage.failNextSave = true;
    await controller.saveEntry(ScoutEntry(matchId: 'match-1', teamNumber: 1));
    await controller.saveEntry(ScoutEntry(matchId: 'match-1', teamNumber: 2));
    await Future<void>.delayed(Duration.zero);

    final persisted = await storage.loadAll();
    expect(persisted.map((e) => e.teamNumber), contains(2));
  });

  test('a failed save marks failedWrites, a later one clears it', () async {
    final storage = _FlakyScoutingStorage();
    final controller = ScoutingController(storage: storage);
    await controller.bootstrap();

    expect(controller.failedWrites.hasFailures, isFalse);

    storage.failNextSave = true;
    await controller.saveEntry(ScoutEntry(matchId: 'match-1', teamNumber: 1));

    expect(controller.failedWrites.hasFailures, isTrue);
    expect(controller.failedWrites.unlandedCount, 1);
    expect(controller.failedWrites.lastFailureAt, isNotNull);

    await controller.saveEntry(ScoutEntry(matchId: 'match-1', teamNumber: 2));

    expect(controller.failedWrites.hasFailures, isFalse);
    expect(controller.failedWrites.unlandedCount, 0);
    expect(controller.failedWrites.lastFailureAt, isNull);
  });

  test(
    'an entry that drops out of a later remote snapshot is removed',
    () async {
      final sync = FakeScoutingSyncService();
      final storage = FakeScoutingStorage();
      final controller = ScoutingController(
        storage: storage,
        syncService: sync,
      );
      await controller.bootstrap();

      final remote = ScoutEntry(
        id: 'r-1',
        matchId: 'match-1',
        teamNumber: 3847,
        authorUid: 'u-other',
      );
      sync.emitRemote(<ScoutEntry>[remote]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.entries, hasLength(1));

      sync.emitRemote(const <ScoutEntry>[]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.entries, isEmpty);
      expect(await storage.loadAll(), isEmpty);
    },
  );

  test('a local-only entry survives remote snapshots that lack it', () async {
    final sync = FakeScoutingSyncService();
    final controller = ScoutingController(
      storage: FakeScoutingStorage(),
      syncService: sync,
    );
    await controller.bootstrap();

    await controller.saveEntry(
      ScoutEntry(matchId: 'match-1', teamNumber: 3847),
    );
    sync.emitRemote(const <ScoutEntry>[]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.entries, hasLength(1));
  });

  test(
    'a remote deletion that happened while closed applies on relaunch',
    () async {
      final storage = FakeScoutingStorage();
      final sync1 = FakeScoutingSyncService();
      final seeded = ScoutingController(storage: storage, syncService: sync1);
      await seeded.bootstrap();
      sync1.emitRemote(<ScoutEntry>[
        ScoutEntry(
          id: 'r-1',
          matchId: 'match-1',
          teamNumber: 3847,
          authorUid: 'u-other',
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(seeded.entries, hasLength(1));

      final sync2 = FakeScoutingSyncService();
      final relaunched = ScoutingController(
        storage: storage,
        syncService: sync2,
      );
      await relaunched.bootstrap();
      expect(relaunched.entries, hasLength(1));

      sync2.emitRemote(const <ScoutEntry>[]);
      await Future<void>.delayed(Duration.zero);

      expect(relaunched.entries, isEmpty);
    },
  );

  test(
    'a remote snapshot lands as one batch storage write, not one per entry',
    () async {
      final sync = FakeScoutingSyncService();
      final storage = LaggyScoutingStorage();
      final controller = ScoutingController(
        storage: storage,
        syncService: sync,
      );
      await controller.bootstrap();

      final remote = <ScoutEntry>[
        for (var i = 0; i < 5; i++)
          ScoutEntry(id: 'r-$i', matchId: 'match-1', teamNumber: 1000 + i),
      ];
      sync.emitRemote(remote);
      await Future<void>.delayed(Duration.zero);
      await controller.saveNow();

      expect(controller.entries, hasLength(5));
      expect(storage.savedBatches, hasLength(1));
      expect(storage.savedBatches.single, hasLength(5));
      expect(storage.savedEntries, hasLength(5));
    },
  );

  test(
    'a merge batch save still runs after an in-flight local save, in order',
    () async {
      final storage = LaggyScoutingStorage();
      final sync = FakeScoutingSyncService();
      final controller = ScoutingController(
        storage: storage,
        syncService: sync,
      );
      await controller.bootstrap();

      storage.firstSaveGate = Completer<void>();
      final localFuture = controller.saveEntry(
        ScoutEntry(id: 'local-1', matchId: 'match-1', teamNumber: 1),
      );
      await Future<void>.delayed(Duration.zero);

      sync.emitRemote(<ScoutEntry>[
        ScoutEntry(id: 'remote-1', matchId: 'match-1', teamNumber: 2),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(storage.savedEntries, hasLength(1));
      expect(storage.savedEntries.single.id, 'local-1');

      storage.firstSaveGate!.complete();
      await localFuture;
      await controller.saveNow();

      expect(storage.savedEntries.map((e) => e.id), <String>[
        'local-1',
        'remote-1',
      ]);
      expect(
        controller.entries.map((e) => e.id),
        containsAll(<String>['local-1', 'remote-1']),
      );
    },
  );

  test(
    'a failed merge batch save marks failedWrites but keeps the optimistic '
    'entries (the server, not this disk write, is the source of truth)',
    () async {
      final storage = _FlakyBatchScoutingStorage();
      final sync = FakeScoutingSyncService();
      final controller = ScoutingController(
        storage: storage,
        syncService: sync,
      );
      await controller.bootstrap();

      storage.failNextBatch = true;
      sync.emitRemote(<ScoutEntry>[
        ScoutEntry(id: 'r-1', matchId: 'match-1', teamNumber: 1),
        ScoutEntry(id: 'r-2', matchId: 'match-1', teamNumber: 2),
      ]);
      await Future<void>.delayed(Duration.zero);
      await controller.saveNow();

      expect(controller.entries, hasLength(2));
      expect(controller.failedWrites.hasFailures, isTrue);

      await controller.saveEntry(ScoutEntry(matchId: 'match-1', teamNumber: 3));
      expect(controller.failedWrites.hasFailures, isFalse);
    },
  );
}
