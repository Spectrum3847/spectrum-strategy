import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import 'pit_photo_capture.dart';
import 'pit_photo_store.dart';

PitPhotoStore createPitPhotoStore() => IndexedDbPitPhotoStore();

class IndexedDbPitPhotoStore implements PitPhotoStore {
  IndexedDbPitPhotoStore({this._databaseName = _defaultDatabaseName});

  static const String _defaultDatabaseName = 'spectrumstrategy_pit_photos';
  static const String _storeName = 'photos';

  final String _databaseName;

  Future<web.IDBDatabase>? _database;

  static const String _prefixUpperBound = '\uffff';

  Future<web.IDBDatabase> _open() {
    return _database ??= _openDatabase().onError<Object>((error, _) {
      _database = null;

      throw StateError(
        'This browser will not let the app store photos '
        '(private browsing, or site data turned off). Allow site data, or '
        'use the app on a phone or desktop. [$error]',
      );
    });
  }

  Future<web.IDBDatabase> _openDatabase() async {
    final web.IDBOpenDBRequest request = web.window.indexedDB.open(
      _databaseName,
      1,
    );
    request.onupgradeneeded = (web.Event _) {
      final database = request.result as web.IDBDatabase;
      if (!database.objectStoreNames.contains(_storeName)) {
        database.createObjectStore(_storeName);
      }
    }.toJS;
    return await _completeRequest(request) as web.IDBDatabase;
  }

  static Future<JSAny?> _completeRequest(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = (web.Event _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }.toJS;
    request.onerror = (web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            'IndexedDB request failed: ${request.error?.message ?? 'unknown'}',
          ),
        );
      }
    }.toJS;
    return completer.future;
  }

  Future<web.IDBObjectStore> _store(String mode) async {
    final database = await _open();
    return database.transaction(_storeName.toJS, mode).objectStore(_storeName);
  }

  static String _key(String entryId, String photoId) => '$entryId/$photoId';

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
    final store = await _store('readwrite');
    await _completeRequest(
      store.put(
        _PhotoRecord(
          bytes: bytes.toJS,
          capturedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
        _key(entryId, photoId).toJS,
      ),
    );
    return photoId;
  }

  @override
  Future<List<String>> listForEntry(String entryId) async {
    validatePhotoPathSegment(entryId);
    final store = await _store('readonly');
    final range = web.IDBKeyRange.bound(
      '$entryId/'.toJS,
      '$entryId/$_prefixUpperBound'.toJS,
    );
    final keys =
        await _completeRequest(store.getAllKeys(range)) as JSArray<JSAny?>;
    final ids = <String>[
      for (final key in keys.toDart)
        if (key.isA<JSString>()) (key as JSString).toDart.split('/').last,
    ];
    ids.sort();
    return ids;
  }

  @override
  Future<Uint8List> readBytes(String entryId, String photoId) async {
    validatePhotoPathSegment(entryId);
    validatePhotoPathSegment(photoId);
    final record = await _read(entryId, photoId);
    if (record == null) {
      throw StateError('No photo stored for ${_key(entryId, photoId)}');
    }
    return (record.bytes as JSUint8Array).toDart;
  }

  @override
  Future<void> delete(String entryId, String photoId) async {
    validatePhotoPathSegment(entryId);
    validatePhotoPathSegment(photoId);
    final store = await _store('readwrite');

    await _completeRequest(store.delete(_key(entryId, photoId).toJS));
  }

  @override
  Future<void> deleteAllForEntry(String entryId) async {
    validatePhotoPathSegment(entryId);
    final store = await _store('readwrite');
    await _completeRequest(
      store.delete(
        web.IDBKeyRange.bound(
          '$entryId/'.toJS,
          '$entryId/$_prefixUpperBound'.toJS,
        ),
      ),
    );
  }

  @override
  Future<DateTime?> capturedAt(String entryId, String photoId) async {
    validatePhotoPathSegment(entryId);
    validatePhotoPathSegment(photoId);
    final record = await _read(entryId, photoId);
    if (record == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(record.capturedAtMillis.toInt());
  }

  Future<_PhotoRecord?> _read(String entryId, String photoId) async {
    final store = await _store('readonly');
    final result = await _completeRequest(
      store.get(_key(entryId, photoId).toJS),
    );
    if (result == null || !result.isA<JSObject>()) return null;

    final record = result as _PhotoRecord;
    if (!record.bytes.isA<JSUint8Array>()) return null;
    return record;
  }
}

extension type _PhotoRecord._(JSObject _) implements JSObject {
  external factory _PhotoRecord({
    required JSUint8Array bytes,
    required int capturedAtMillis,
  });

  external JSAny? get bytes;
  external num get capturedAtMillis;
}
