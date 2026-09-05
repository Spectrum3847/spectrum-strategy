import 'dart:typed_data';

import 'package:spectrumstrategy/src/scouting/services/pit_photo_store.dart';
import 'package:uuid/uuid.dart';

class FakePitPhotoStore implements PitPhotoStore {
  final Map<String, Map<String, Uint8List>> _store =
      <String, Map<String, Uint8List>>{};
  final Map<String, Map<String, DateTime>> _capturedAt =
      <String, Map<String, DateTime>>{};

  @override
  Future<String> capture({
    required String entryId,
    required PhotoSource source,
  }) async {
    final photoId = const Uuid().v4();
    _store.putIfAbsent(entryId, () => <String, Uint8List>{});
    _store[entryId]![photoId] = Uint8List.fromList(
      'fake-jpeg-bytes-for-$photoId'.codeUnits,
    );
    _capturedAt.putIfAbsent(entryId, () => <String, DateTime>{});
    _capturedAt[entryId]![photoId] = DateTime.now();
    return photoId;
  }

  void setCapturedAtForTesting(String entryId, String photoId, DateTime at) {
    _capturedAt.putIfAbsent(entryId, () => <String, DateTime>{})[photoId] = at;
  }

  @override
  Future<DateTime?> capturedAt(String entryId, String photoId) async {
    return _capturedAt[entryId]?[photoId];
  }

  @override
  Future<List<String>> listForEntry(String entryId) async {
    final photos = _store[entryId];
    if (photos == null) return <String>[];
    return photos.keys.toList()..sort();
  }

  @override
  Future<Uint8List> readBytes(String entryId, String photoId) async {
    final photos = _store[entryId];
    if (photos == null || !photos.containsKey(photoId)) {
      throw StateError('Photo not found: $entryId/$photoId');
    }
    return photos[photoId]!;
  }

  @override
  Future<void> delete(String entryId, String photoId) async {
    _store[entryId]?.remove(photoId);
    _capturedAt[entryId]?.remove(photoId);
  }

  @override
  Future<void> deleteAllForEntry(String entryId) async {
    _store.remove(entryId);
    _capturedAt.remove(entryId);
  }
}
