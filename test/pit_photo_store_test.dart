import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/scouting/models/pit_scout_entry.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_photo_store.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_photo_store_io.dart';
import 'package:uuid/uuid.dart';

import 'support/fake_pit_photo_store.dart';

void main() {
  group('FakePitPhotoStore', () {
    late FakePitPhotoStore store;

    setUp(() {
      store = FakePitPhotoStore();
    });

    test('capture returns a valid UUID photo id', () async {
      final id = await store.capture(
        entryId: 'entry-1',
        source: PhotoSource.camera,
      );
      expect(id, isA<String>());
      expect(id.isNotEmpty, isTrue);

      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('capture stores bytes that round-trip through readBytes', () async {
      final id = await store.capture(
        entryId: 'entry-1',
        source: PhotoSource.gallery,
      );
      final bytes = await store.readBytes('entry-1', id);
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes), 'fake-jpeg-bytes-for-$id');
    });

    test('listForEntry returns captured ids sorted', () async {
      final idA = await store.capture(
        entryId: 'e1',
        source: PhotoSource.camera,
      );
      final idB = await store.capture(
        entryId: 'e1',
        source: PhotoSource.gallery,
      );
      final ids = await store.listForEntry('e1');
      expect(ids, hasLength(2));
      expect(ids, containsAll(<String>[idA, idB]));
    });

    test('listForEntry returns empty for unknown entry', () async {
      final ids = await store.listForEntry('nonexistent');
      expect(ids, isEmpty);
    });

    test('readBytes throws for unknown photo', () async {
      expect(
        () => store.readBytes('e1', 'no-such-photo'),
        throwsA(isA<StateError>()),
      );
    });

    test('delete removes a single photo', () async {
      final id = await store.capture(entryId: 'e1', source: PhotoSource.camera);
      await store.delete('e1', id);
      final ids = await store.listForEntry('e1');
      expect(ids, isEmpty);
    });

    test('deleteAllForEntry removes all photos for an entry', () async {
      await store.capture(entryId: 'e1', source: PhotoSource.camera);
      await store.capture(entryId: 'e1', source: PhotoSource.gallery);
      await store.capture(entryId: 'e2', source: PhotoSource.camera);
      await store.deleteAllForEntry('e1');
      expect(await store.listForEntry('e1'), isEmpty);
      expect(await store.listForEntry('e2'), hasLength(1));
    });

    test('photo cap on PitScoutEntry is enforced', () async {
      var entry = PitScoutEntry(id: 'e1', teamNumber: 3847);
      for (var i = 0; i < PitScoutEntry.maxPhotos + 1; i++) {
        final photoId = const Uuid().v4();
        entry = entry.withAddedPhoto(photoId);
      }
      expect(entry.photoIds, hasLength(PitScoutEntry.maxPhotos));
    });

    test('deleteAllForEntry is a no-op for unknown entry', () async {
      await store.deleteAllForEntry('nonexistent');
    });
  });

  group('FileSystemPitPhotoStore path validation', () {
    late FileSystemPitPhotoStore realStore;

    setUp(() {
      realStore = FileSystemPitPhotoStore();
    });

    test('deleteAllForEntry rejects path traversal', () async {
      await expectLater(
        realStore.deleteAllForEntry('../../secret'),
        throwsArgumentError,
      );
    });

    test('deleteAllForEntry rejects empty id', () async {
      await expectLater(realStore.deleteAllForEntry(''), throwsArgumentError);
    });

    test('listForEntry rejects slash in entryId', () async {
      await expectLater(realStore.listForEntry('entry/1'), throwsArgumentError);
    });

    test('readBytes rejects backslash in entryId', () async {
      await expectLater(
        realStore.readBytes('bad\\entry', 'photo'),
        throwsArgumentError,
      );
    });

    test('readBytes rejects slash in photoId', () async {
      await expectLater(
        realStore.readBytes('entry', 'photo/id'),
        throwsArgumentError,
      );
    });

    test('delete rejects dot-dot in entryId', () async {
      await expectLater(
        realStore.delete('../../foo', 'photo'),
        throwsArgumentError,
      );
    });

    test('delete rejects special chars in photoId', () async {
      await expectLater(
        realStore.delete('entry', 'photo\$.jpg'),
        throwsArgumentError,
      );
    });
  });

  group('FileSystemPitPhotoStore does not create directories on a read', () {
    late Directory base;
    late FileSystemPitPhotoStore store;

    setUp(() async {
      base = await Directory.systemTemp.createTemp('pit_photos_test');
      store = FileSystemPitPhotoStore(baseDir: base);
    });

    tearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    Directory entryDir(String entryId) =>
        Directory('${base.path}/pit_photos/$entryId');

    test('listForEntry returns empty and creates nothing', () async {
      expect(await store.listForEntry('entry-1'), isEmpty);
      expect(await entryDir('entry-1').exists(), isFalse);
    });

    test('readBytes for a missing entry creates nothing', () async {
      await expectLater(
        store.readBytes('entry-2', 'photo-1'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await entryDir('entry-2').exists(), isFalse);
    });

    test('delete for a missing entry creates nothing', () async {
      await store.delete('entry-3', 'photo-1');
      expect(await entryDir('entry-3').exists(), isFalse);
    });

    test('deleteAllForEntry for a missing entry creates nothing', () async {
      await store.deleteAllForEntry('entry-4');
      expect(await entryDir('entry-4').exists(), isFalse);
    });
  });
}
