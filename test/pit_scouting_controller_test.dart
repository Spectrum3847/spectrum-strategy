import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_photo_store.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_photo_upload_service.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_scouting_storage.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_scouting_sync_service.dart';
import 'package:spectrumstrategy/src/scouting/state/pit_scouting_controller.dart';

import 'support/fake_pit_photo_store.dart';
import 'support/fake_pit_scouting_sync_service.dart';

class _InMemoryStorage implements PitScoutingStorage {
  final Map<String, PitScoutEntry> data = <String, PitScoutEntry>{};
  int saves = 0;
  int deletes = 0;

  @override
  Future<List<PitScoutEntry>> loadAll() async =>
      data.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> saveEntry(PitScoutEntry entry) async {
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
  Future<void> saveEntry(PitScoutEntry entry) async {
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

void main() {
  test('PitScoutEntry toJson/fromJson round-trips', () {
    final entry = PitScoutEntry(
      id: 'abc',
      teamNumber: 3847,
      eventKey: '2025flor',
      fieldValues: <String, dynamic>{
        'drivetrainType': 'swerve',
        'canClimb': true,
      },
      authorUid: 'uid-1',
      authorDisplayName: 'Scout',
      updatedAt: DateTime.utc(2026, 6, 27, 12, 0),
    );
    final round = PitScoutEntry.fromJson(entry.toJson());
    expect(round.id, 'abc');
    expect(round.teamNumber, 3847);
    expect(round.eventKey, '2025flor');
    expect(round.fieldValues['drivetrainType'], 'swerve');
    expect(round.fieldValues['canClimb'], true);
    expect(round.authorUid, 'uid-1');
    expect(round.authorDisplayName, 'Scout');
    expect(round.updatedAt, DateTime.utc(2026, 6, 27, 12, 0));
  });

  test(
    'PitScoutEntry toJson emits updatedAt as UTC ISO 8601 with Z suffix',
    () {
      final entry = PitScoutEntry(
        teamNumber: 1,
        updatedAt: DateTime.utc(2026, 1, 1, 0, 0, 0),
      );
      final json = entry.toJson();
      expect(json['updatedAt'] as String, endsWith('Z'));
    },
  );

  test('PitScoutEntry fromJson defaults author fields to empty string', () {
    final entry = PitScoutEntry.fromJson(<String, dynamic>{
      'id': 'x',
      'teamNumber': 254,
      'updatedAt': '2026-01-01T00:00:00.000Z',
    });
    expect(entry.authorUid, '');
    expect(entry.authorDisplayName, '');
    expect(entry.eventKey, '');
  });

  test('toRemoteJson omits photoIds, toJson includes it', () {
    final entry = PitScoutEntry(
      teamNumber: 3847,
      photoIds: <String>['pic-1', 'pic-2'],
    );
    expect(entry.toJson().containsKey('photoIds'), isTrue);
    expect(entry.toRemoteJson().containsKey('photoIds'), isFalse);
  });

  test('PitScoutEntry constructor forces updatedAt to UTC', () {
    final local = DateTime(2026, 6, 27, 10, 0);
    final entry = PitScoutEntry(teamNumber: 1, updatedAt: local);
    expect(entry.updatedAt.isUtc, isTrue);
  });

  group('PitScoutingController (local-only)', () {
    late _InMemoryStorage storage;
    late PitScoutingController controller;

    setUp(() {
      storage = _InMemoryStorage();
      controller = PitScoutingController(storage: storage);
    });

    tearDown(() => controller.dispose());

    test('bootstrap loads stored entries and sets isReady', () async {
      await storage.saveEntry(
        PitScoutEntry(
          id: 'e1',
          teamNumber: 3847,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await controller.bootstrap();
      expect(controller.isReady, isTrue);
      expect(controller.entries.any((e) => e.id == 'e1'), isTrue);
    });

    test('saveEntry persists and appears in entries', () async {
      await controller.bootstrap();
      final entry = PitScoutEntry(id: 'a', teamNumber: 254);
      await controller.saveEntry(entry);
      expect(controller.entries.any((e) => e.id == 'a'), isTrue);
      expect(storage.saves, greaterThanOrEqualTo(1));
    });

    test('saveEntry stamps a fresh UTC updatedAt', () async {
      await controller.bootstrap();
      final before = DateTime.now().toUtc().subtract(
        const Duration(seconds: 1),
      );
      final entry = PitScoutEntry(
        id: 'b',
        teamNumber: 1,
        updatedAt: DateTime.utc(2000),
      );
      await controller.saveEntry(entry);
      final saved = controller.entries.firstWhere((e) => e.id == 'b');
      expect(saved.updatedAt.isAfter(before), isTrue);
      expect(saved.updatedAt.isUtc, isTrue);
    });

    test('deleteEntry removes from entries and storage', () async {
      await controller.bootstrap();
      final entry = PitScoutEntry(id: 'c', teamNumber: 9);
      await controller.saveEntry(entry);
      await controller.deleteEntry('c');
      expect(controller.entries.any((e) => e.id == 'c'), isFalse);
      expect(storage.deletes, 1);
    });

    test('entriesForTeam filters by team number', () async {
      await controller.bootstrap();
      await controller.saveEntry(PitScoutEntry(id: 'p1', teamNumber: 3847));
      await controller.saveEntry(PitScoutEntry(id: 'p2', teamNumber: 254));
      await controller.saveEntry(PitScoutEntry(id: 'p3', teamNumber: 3847));
      final team3847 = controller.entriesForTeam(3847);
      expect(team3847.length, 2);
      expect(team3847.every((e) => e.teamNumber == 3847), isTrue);
    });

    test('local-only: no sync service, no push attempted', () async {
      await controller.bootstrap();

      await controller.saveEntry(PitScoutEntry(id: 'd', teamNumber: 1));
      expect(controller.syncStatus.state, PitScoutingSyncState.signedOut);
    });
  });

  group('PitScoutingController sync', () {
    late _InMemoryStorage storage;
    late FakePitScoutingSyncService sync;
    late PitScoutingController controller;

    setUp(() {
      storage = _InMemoryStorage();
      sync = FakePitScoutingSyncService(
        currentUserUid: 'uid-me',
        currentUserDisplayName: 'Scout',
      );
      controller = PitScoutingController(storage: storage, syncService: sync);
    });

    tearDown(() => controller.dispose());

    test('saveEntry pushes to sync service', () async {
      await controller.bootstrap();
      final entry = PitScoutEntry(id: 'e1', teamNumber: 3847);
      await controller.saveEntry(entry);
      await Future<void>.delayed(Duration.zero);
      expect(sync.pushed, hasLength(1));
      expect(sync.pushed.first.id, 'e1');
    });

    test('deleteEntry calls sync.delete', () async {
      await controller.bootstrap();
      final entry = PitScoutEntry(id: 'e2', teamNumber: 254);
      await controller.saveEntry(entry);
      sync.pushed.clear();
      await controller.deleteEntry('e2');
      await Future<void>.delayed(Duration.zero);
      expect(sync.deleted, hasLength(1));
      expect(sync.deleted.first.id, 'e2');
    });

    test('mergeRemote adds new entry from remote', () async {
      await controller.bootstrap();
      final remote = PitScoutEntry(
        id: 'remote-1',
        teamNumber: 118,
        updatedAt: DateTime.utc(2026, 6, 27),
        authorUid: 'uid-other',
        authorDisplayName: 'Teammate',
      );
      sync.emitRemote(<PitScoutEntry>[remote]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.entries.any((e) => e.id == 'remote-1'), isTrue);
    });

    test(
      'an entry that drops out of a later remote snapshot is removed',
      () async {
        await controller.bootstrap();
        final remote = PitScoutEntry(
          id: 'remote-1',
          teamNumber: 118,
          updatedAt: DateTime.utc(2026, 6, 27),
          authorUid: 'uid-other',
          authorDisplayName: 'Teammate',
        );
        sync.emitRemote(<PitScoutEntry>[remote]);
        await Future<void>.delayed(Duration.zero);
        expect(controller.entries, hasLength(1));

        sync.emitRemote(const <PitScoutEntry>[]);
        await Future<void>.delayed(Duration.zero);

        expect(controller.entries, isEmpty);
        expect(storage.data, isEmpty);
      },
    );

    test('a local-only entry survives remote snapshots that lack it', () async {
      await controller.bootstrap();
      await controller.saveEntry(PitScoutEntry(id: 'local-1', teamNumber: 971));

      sync.emitRemote(const <PitScoutEntry>[]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.entries, hasLength(1));
    });

    test('a failed save does not wedge the save queue', () async {
      final flaky = _FlakyStorage();
      final local = PitScoutingController(storage: flaky);
      await local.bootstrap();

      flaky.failNextSave = true;
      await local.saveEntry(PitScoutEntry(id: 'p1', teamNumber: 1));
      await local.saveEntry(PitScoutEntry(id: 'p2', teamNumber: 2));
      await Future<void>.delayed(Duration.zero);

      expect(flaky.data.containsKey('p2'), isTrue);
      local.dispose();
    });

    test(
      'a failed save marks failedWrites, and a later success clears it',
      () async {
        final flaky = _FlakyStorage();
        final local = PitScoutingController(storage: flaky);
        await local.bootstrap();
        expect(local.failedWrites.hasFailures, isFalse);

        flaky.failNextSave = true;
        await local.saveEntry(PitScoutEntry(id: 'p1', teamNumber: 1));

        expect(local.failedWrites.hasFailures, isTrue);
        expect(local.failedWrites.unlandedCount, 1);

        await local.saveEntry(PitScoutEntry(id: 'p2', teamNumber: 2));

        expect(local.failedWrites.hasFailures, isFalse);
        local.dispose();
      },
    );

    test(
      'a failed write does not roll back onto an unconfirmed value',
      () async {
        final flaky = _FlakyStorage();
        final local = PitScoutingController(storage: flaky);
        await local.bootstrap();

        final entryA = PitScoutEntry(
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

    test('mergeRemote replaces local with newer remote (LWW)', () async {
      await controller.bootstrap();
      final local = PitScoutEntry(
        id: 'shared',
        teamNumber: 3847,
        fieldValues: <String, dynamic>{'drivetrainType': 'tank'},
        updatedAt: DateTime.utc(2026, 6, 26),
      );
      await controller.saveEntry(local);

      final newerRemote = PitScoutEntry(
        id: 'shared',
        teamNumber: 3847,
        fieldValues: <String, dynamic>{'drivetrainType': 'swerve'},
        updatedAt: DateTime.now().toUtc().add(const Duration(days: 1)),
        authorUid: 'uid-me',
        authorDisplayName: 'Scout',
      );
      sync.emitRemote(<PitScoutEntry>[newerRemote]);
      await Future<void>.delayed(Duration.zero);

      final found = controller.entries.firstWhere((e) => e.id == 'shared');
      expect(found.fieldValues['drivetrainType'], 'swerve');
    });

    test('mergeRemote ignores stale remote', () async {
      await controller.bootstrap();
      final local = PitScoutEntry(
        id: 'fresh',
        teamNumber: 1,
        fieldValues: <String, dynamic>{'note': 'local'},
        updatedAt: DateTime.utc(2026, 6, 27),
      );
      await controller.saveEntry(local);

      final staleRemote = PitScoutEntry(
        id: 'fresh',
        teamNumber: 1,
        fieldValues: <String, dynamic>{'note': 'old remote'},
        updatedAt: DateTime.utc(2026, 6, 26),
        authorUid: 'uid-me',
        authorDisplayName: 'Scout',
      );
      sync.emitRemote(<PitScoutEntry>[staleRemote]);
      await Future<void>.delayed(Duration.zero);

      final found = controller.entries.firstWhere((e) => e.id == 'fresh');

      expect(found.updatedAt.isAfter(DateTime.utc(2026, 6, 26)), isTrue);
    });

    test('currentUserUid proxies sync service', () async {
      await controller.bootstrap();
      expect(controller.currentUserUid, 'uid-me');
    });
  });

  group('PitScoutingController with photo store', () {
    late _InMemoryStorage storage;
    late FakePitPhotoStore photoStore;
    late PitScoutingController controller;

    setUp(() {
      storage = _InMemoryStorage();
      photoStore = FakePitPhotoStore();
      controller = PitScoutingController(
        storage: storage,
        photoStore: photoStore,
      );
    });

    tearDown(() => controller.dispose());

    test('deleteEntry removes photos for that entry', () async {
      await controller.bootstrap();
      final entry = PitScoutEntry(id: 'p1', teamNumber: 3847);
      await controller.saveEntry(entry);

      final photoId1 = await photoStore.capture(
        entryId: entry.id,
        source: PhotoSource.camera,
      );
      final photoId2 = await photoStore.capture(
        entryId: entry.id,
        source: PhotoSource.gallery,
      );
      final withPhotos = entry
          .withAddedPhoto(photoId1)
          .withAddedPhoto(photoId2);
      await controller.saveEntry(withPhotos);
      expect(await photoStore.listForEntry(entry.id), hasLength(2));

      await controller.deleteEntry(entry.id);

      expect(await photoStore.listForEntry(entry.id), isEmpty);
    });

    test(
      'deleteEntry is a no-op for photo store when entry has no photos',
      () async {
        await controller.bootstrap();
        final entry = PitScoutEntry(id: 'p2', teamNumber: 254);
        await controller.saveEntry(entry);
        await controller.deleteEntry(entry.id);
      },
    );
  });

  group('photo upload', () {
    late _InMemoryStorage storage;
    late FakePitPhotoStore photoStore;
    late List<String> uploadedBodies;
    late List<String> deletedKeys;
    late int nextKey;
    late bool workerUp;

    PitScoutingController build() {
      return PitScoutingController(
        storage: storage,
        photoStore: photoStore,
        photoUploader: PitPhotoUploadService(
          baseUrlLoader: () async => 'https://photos.example.workers.dev',
          idTokenProvider: () async => 'fb-token',
          httpClient: MockClient((request) async {
            if (!workerUp) return http.Response('', 503);
            if (request.method == 'POST') {
              uploadedBodies.add(utf8.decode(request.bodyBytes));
              return http.Response(
                jsonEncode({'key': 'key-${nextKey++}.jpg'}),
                201,
              );
            }
            if (request.method == 'DELETE') {
              deletedKeys.add(request.url.pathSegments.last);
              return http.Response('', 204);
            }
            return http.Response.bytes(Uint8List.fromList(<int>[9]), 200);
          }),
        ),
      );
    }

    setUp(() {
      storage = _InMemoryStorage();
      photoStore = FakePitPhotoStore();
      uploadedBodies = <String>[];
      deletedKeys = <String>[];
      nextKey = 1;
      workerUp = true;
    });

    Future<(PitScoutingController, PitScoutEntry, String)>
    withOnePhoto() async {
      final controller = build();
      await controller.bootstrap();
      var entry = PitScoutEntry(id: 'e1', teamNumber: 3847);
      await controller.saveEntry(entry);
      final photoId = await photoStore.capture(
        entryId: entry.id,
        source: PhotoSource.camera,
      );
      entry = controller.entries.first.withAddedPhoto(photoId);
      await controller.saveEntry(entry);
      return (controller, entry, photoId);
    }

    test('a captured photo uploads and its key lands on the entry', () async {
      final (controller, _, photoId) = await withOnePhoto();
      await controller.uploadPendingPhotos();

      expect(uploadedBodies, hasLength(1));
      expect(uploadedBodies.first, contains(photoId));
      expect(controller.entries.first.photoKeys[photoId], 'key-1.jpg');
      expect(controller.entries.first.pendingPhotoIds, isEmpty);
    });

    test('a photo already uploaded is not sent twice', () async {
      final (controller, _, _) = await withOnePhoto();
      await controller.uploadPendingPhotos();
      await controller.uploadPendingPhotos();

      expect(uploadedBodies, hasLength(1));
    });

    test(
      'uploading a photo prunes its local file once the key is recorded',
      () async {
        final (controller, entry, _) = await withOnePhoto();
        await controller.uploadPendingPhotos();

        expect(await photoStore.listForEntry(entry.id), isEmpty);
      },
    );

    test('an upload that fails stays pending for the next pass', () async {
      workerUp = false;
      final (controller, entry, photoId) = await withOnePhoto();
      await controller.uploadPendingPhotos();

      expect(controller.entries.first.photoKeys, isEmpty);
      expect(controller.entries.first.pendingPhotoIds, <String>[photoId]);

      expect(await photoStore.listForEntry(entry.id), <String>[photoId]);

      workerUp = true;
      await controller.uploadPendingPhotos();
      expect(controller.entries.first.photoKeys[photoId], 'key-1.jpg');
    });

    test('recording a key does not bump updatedAt', () async {
      final (controller, _, _) = await withOnePhoto();
      final before = controller.entries.first.updatedAt;
      await controller.uploadPendingPhotos();

      expect(controller.entries.first.updatedAt, before);
    });

    test('removing a photo deletes the object it named', () async {
      final (controller, _, photoId) = await withOnePhoto();
      await controller.uploadPendingPhotos();

      await controller.removePhoto(controller.entries.first, photoId);

      await Future<void>.delayed(Duration.zero);

      expect(deletedKeys, <String>['key-1.jpg']);
      expect(controller.entries.first.photoIds, isEmpty);
      expect(controller.entries.first.photoKeys, isEmpty);
      expect(await photoStore.listForEntry('e1'), isEmpty);
    });

    test(
      'removing a photo keeps a key recorded after the caller read the entry',
      () async {
        final controller = build();
        await controller.bootstrap();
        var entry = PitScoutEntry(id: 'e1', teamNumber: 3847);
        await controller.saveEntry(entry);
        final keep = await photoStore.capture(
          entryId: 'e1',
          source: PhotoSource.camera,
        );
        final drop = await photoStore.capture(
          entryId: 'e1',
          source: PhotoSource.camera,
        );
        await controller.saveEntry(
          controller.entries.first.withAddedPhoto(keep).withAddedPhoto(drop),
        );

        final stale = controller.entries.first;
        await controller.uploadPendingPhotos();
        expect(controller.entries.first.photoKeys, hasLength(2));

        await controller.removePhoto(stale, drop);
        await Future<void>.delayed(Duration.zero);

        final after = controller.entries.first;
        expect(after.photoIds, <String>[keep]);

        expect(after.photoKeys.containsKey(keep), isTrue);
        expect(after.pendingPhotoIds, isEmpty);

        expect(deletedKeys, hasLength(1));
      },
    );

    test('deleting an entry deletes every object it referenced', () async {
      final (controller, _, _) = await withOnePhoto();
      await controller.uploadPendingPhotos();

      await controller.deleteEntry('e1');

      await Future<void>.delayed(Duration.zero);

      expect(deletedKeys, <String>['key-1.jpg']);
    });

    test('photoBytes prefers the local file before it uploads', () async {
      final (controller, _, photoId) = await withOnePhoto();

      final bytes = await controller.photoBytes(
        controller.entries.first,
        photoId,
      );

      expect(utf8.decode(bytes!), contains(photoId));
    });

    test('photoBytes falls back to the Worker once the local copy is pruned '
        'after upload', () async {
      final (controller, entry, photoId) = await withOnePhoto();
      await controller.uploadPendingPhotos();
      expect(await photoStore.listForEntry(entry.id), isEmpty);

      final bytes = await controller.photoBytes(
        controller.entries.first,
        photoId,
      );
      expect(bytes, <int>[9]);
    });

    test(
      'photoBytes falls back to the Worker for a remote-only photo',
      () async {
        final controller = build();
        await controller.bootstrap();
        final remote = PitScoutEntry.fromJson(<String, dynamic>{
          'id': 'e2',
          'teamNumber': 254,
          'photoKeys': <String>['key-9.jpg'],
          'updatedAt': DateTime.utc(2026, 8, 1).toIso8601String(),
        });

        expect(remote.photoIds, isEmpty);
        expect(await controller.photoBytes(remote, 'key-9.jpg'), <int>[9]);
      },
    );

    test(
      'a controller with no uploader leaves photos pending, not broken',
      () async {
        final controller = PitScoutingController(
          storage: storage,
          photoStore: photoStore,
        );
        await controller.bootstrap();
        final photoId = await photoStore.capture(
          entryId: 'e3',
          source: PhotoSource.camera,
        );
        await controller.saveEntry(
          PitScoutEntry(id: 'e3', teamNumber: 1).withAddedPhoto(photoId),
        );
        await controller.uploadPendingPhotos();

        expect(uploadedBodies, isEmpty);
        expect(controller.entries.first.pendingPhotoIds, <String>[photoId]);
      },
    );
  });

  group('pit photo prune on bootstrap', () {
    test(
      'a photo already recorded as uploaded is pruned at bootstrap',
      () async {
        final storage = _InMemoryStorage();
        final photoStore = FakePitPhotoStore();
        final photoId = await photoStore.capture(
          entryId: 'legacy',
          source: PhotoSource.camera,
        );
        storage.data['legacy'] = PitScoutEntry(
          id: 'legacy',
          teamNumber: 3847,
          photoIds: <String>[photoId],
          photoKeys: <String, String>{photoId: 'key-1.jpg'},
        );

        final controller = PitScoutingController(
          storage: storage,
          photoStore: photoStore,
        );
        await controller.bootstrap();

        expect(await photoStore.listForEntry('legacy'), isEmpty);
        controller.dispose();
      },
    );

    test('a photo that never uploaded survives bootstrap', () async {
      final storage = _InMemoryStorage();
      final photoStore = FakePitPhotoStore();
      final photoId = await photoStore.capture(
        entryId: 'legacy2',
        source: PhotoSource.camera,
      );
      storage.data['legacy2'] = PitScoutEntry(
        id: 'legacy2',
        teamNumber: 254,
        photoIds: <String>[photoId],
      );

      final controller = PitScoutingController(
        storage: storage,
        photoStore: photoStore,
      );
      await controller.bootstrap();

      expect(await photoStore.listForEntry('legacy2'), <String>[photoId]);
      controller.dispose();
    });
  });

  group('stale pending photo prune on bootstrap', () {
    test('a pending photo older than the cutoff is dropped', () async {
      final storage = _InMemoryStorage();
      final photoStore = FakePitPhotoStore();
      final photoId = await photoStore.capture(
        entryId: 'stale',
        source: PhotoSource.camera,
      );
      photoStore.setCapturedAtForTesting(
        'stale',
        photoId,
        DateTime.now().toUtc().subtract(const Duration(days: 30)),
      );
      storage.data['stale'] = PitScoutEntry(
        id: 'stale',
        teamNumber: 3847,
        photoIds: <String>[photoId],
      );

      final controller = PitScoutingController(
        storage: storage,
        photoStore: photoStore,
        photoUploader: PitPhotoUploadService(
          baseUrlLoader: () async => 'https://photos.example.workers.dev',
          idTokenProvider: () async => 'fb-token',
          httpClient: MockClient((request) async => http.Response('', 503)),
        ),
      );
      await controller.bootstrap();

      expect(await photoStore.listForEntry('stale'), isEmpty);
      expect(controller.entries.first.photoIds, isEmpty);
      controller.dispose();
    });

    test('a pending photo within the cutoff survives bootstrap', () async {
      final storage = _InMemoryStorage();
      final photoStore = FakePitPhotoStore();
      final photoId = await photoStore.capture(
        entryId: 'fresh',
        source: PhotoSource.camera,
      );
      storage.data['fresh'] = PitScoutEntry(
        id: 'fresh',
        teamNumber: 3847,
        photoIds: <String>[photoId],
      );

      final controller = PitScoutingController(
        storage: storage,
        photoStore: photoStore,
        photoUploader: PitPhotoUploadService(
          baseUrlLoader: () async => 'https://photos.example.workers.dev',
          idTokenProvider: () async => 'fb-token',
          httpClient: MockClient((request) async => http.Response('', 503)),
        ),
      );
      await controller.bootstrap();

      expect(await photoStore.listForEntry('fresh'), <String>[photoId]);
      expect(controller.entries.first.photoIds, <String>[photoId]);
      controller.dispose();
    });

    test(
      'a stale pending photo is untouched with no photo uploader configured',
      () async {
        final storage = _InMemoryStorage();
        final photoStore = FakePitPhotoStore();
        final photoId = await photoStore.capture(
          entryId: 'unconfigured',
          source: PhotoSource.camera,
        );
        photoStore.setCapturedAtForTesting(
          'unconfigured',
          photoId,
          DateTime.now().toUtc().subtract(const Duration(days: 30)),
        );
        storage.data['unconfigured'] = PitScoutEntry(
          id: 'unconfigured',
          teamNumber: 3847,
          photoIds: <String>[photoId],
        );

        final controller = PitScoutingController(
          storage: storage,
          photoStore: photoStore,
        );
        await controller.bootstrap();

        expect(await photoStore.listForEntry('unconfigured'), <String>[
          photoId,
        ]);
        controller.dispose();
      },
    );
  });
}
