import 'dart:typed_data';

enum PhotoSource { camera, gallery }

abstract class PitPhotoStore {
  Future<String> capture({
    required String entryId,
    required PhotoSource source,
  });

  Future<String> write(String entryId, Uint8List bytes);

  Future<List<String>> listForEntry(String entryId);

  Future<Uint8List> readBytes(String entryId, String photoId);

  Future<void> delete(String entryId, String photoId);

  Future<void> deleteAllForEntry(String entryId);

  Future<DateTime?> capturedAt(String entryId, String photoId);
}
