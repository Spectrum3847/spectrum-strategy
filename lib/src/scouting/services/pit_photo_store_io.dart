import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'pit_photo_capture.dart';
import 'pit_photo_store.dart';

PitPhotoStore createPitPhotoStore() => FileSystemPitPhotoStore();

class FileSystemPitPhotoStore implements PitPhotoStore {
  FileSystemPitPhotoStore({this._baseDir});

  final Directory? _baseDir;

  Future<Directory> get _resolvedDir async {
    final override = _baseDir;
    if (override != null) return override;
    return getApplicationDocumentsDirectory();
  }

  Future<Directory> _entryDir(String entryId) async {
    validatePhotoPathSegment(entryId);
    final base = await _resolvedDir;
    return Directory('${base.path}/pit_photos/$entryId');
  }

  Future<Directory> _createdEntryDir(String entryId) async {
    final dir = await _entryDir(entryId);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<String> capture({
    required String entryId,
    required PhotoSource source,
  }) async {
    validatePhotoPathSegment(entryId);
    return write(entryId, await pickAndCompressPhoto(source));
  }

  @override
  Future<String> write(String entryId, Uint8List bytes) async {
    validatePhotoPathSegment(entryId);
    final photoId = const Uuid().v4();
    final dir = await _createdEntryDir(entryId);
    await File('${dir.path}/$photoId.jpg').writeAsBytes(bytes);
    return photoId;
  }

  @override
  Future<List<String>> listForEntry(String entryId) async {
    validatePhotoPathSegment(entryId);
    final dir = await _entryDir(entryId);
    if (!await dir.exists()) return <String>[];
    final entities = dir.listSync();
    final ids = <String>[];
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.jpg')) {
        ids.add(entity.uri.pathSegments.last.replaceAll('.jpg', ''));
      }
    }
    ids.sort();
    return ids;
  }

  @override
  Future<Uint8List> readBytes(String entryId, String photoId) async {
    validatePhotoPathSegment(entryId);
    validatePhotoPathSegment(photoId);
    final dir = await _entryDir(entryId);
    return await File('${dir.path}/$photoId.jpg').readAsBytes();
  }

  @override
  Future<void> delete(String entryId, String photoId) async {
    validatePhotoPathSegment(entryId);
    validatePhotoPathSegment(photoId);
    final dir = await _entryDir(entryId);
    final file = File('${dir.path}/$photoId.jpg');
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> deleteAllForEntry(String entryId) async {
    final dir = await _entryDir(entryId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  @override
  Future<DateTime?> capturedAt(String entryId, String photoId) async {
    validatePhotoPathSegment(entryId);
    validatePhotoPathSegment(photoId);
    final dir = await _entryDir(entryId);
    final file = File('${dir.path}/$photoId.jpg');
    try {
      return await file.lastModified();
    } catch (_) {
      return null;
    }
  }
}
