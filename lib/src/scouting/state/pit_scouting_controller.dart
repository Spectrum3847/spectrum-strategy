import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../state/failed_write_tracker.dart';
import '../models/pit_scout_entry.dart';
import '../services/pit_photo_store.dart';
import '../services/pit_photo_upload_service.dart';
import '../services/pit_scouting_storage.dart';
import '../services/pit_scouting_sync_service.dart';

class PitScoutingController extends ChangeNotifier {
  PitScoutingController({
    PitScoutingStorage? storage,
    this._syncService,
    this._photoStore,
    this._photoUploader,
  }) : _storage = storage ?? SharedPreferencesPitScoutingStorage();

  final PitScoutingStorage _storage;
  final PitScoutingSyncService? _syncService;
  final PitPhotoStore? _photoStore;
  final PitPhotoUploadService? _photoUploader;

  PitPhotoStore? get photoStore => _photoStore;
  PitPhotoUploadService? get photoUploader => _photoUploader;

  Future<void>? _uploadPass;

  Future<void>? _bootstrapFuture;
  Future<void> _saveQueue = Future<void>.value();
  final List<PitScoutEntry> _entries = <PitScoutEntry>[];

  final Set<String> _remoteSyncedIds = <String>{};

  final Map<String, int> _mutations = <String, int>{};

  final Map<String, PitScoutEntry> _confirmed = <String, PitScoutEntry>{};

  String? _lastError;

  final FailedWriteTracker failedWrites = FailedWriteTracker();
  bool _ready = false;
  StreamSubscription<List<PitScoutEntry>>? _remoteSubscription;
  StreamSubscription<PitScoutingSyncStatus>? _statusSubscription;
  PitScoutingSyncStatus _syncStatus = const PitScoutingSyncStatus(
    state: PitScoutingSyncState.signedOut,
  );

  bool get isReady => _ready;
  List<PitScoutEntry> get entries => List<PitScoutEntry>.unmodifiable(_entries);

  String? get lastError => _lastError;

  void clearLastError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  PitScoutingSyncService? get syncService => _syncService;
  PitScoutingSyncStatus get syncStatus => _syncStatus;

  String? get currentUserUid => _syncService?.currentUserUid;

  Future<void> bootstrap() {
    return _bootstrapFuture ??= _bootstrap().onError<Object>((
      error,
      stackTrace,
    ) {
      _bootstrapFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _bootstrap() async {
    final loaded = await _storage.loadAll();
    _entries
      ..clear()
      ..addAll(loaded);
    _remoteSyncedIds
      ..clear()
      ..addAll(await _storage.loadSyncedIds());
    _ready = true;
    notifyListeners();

    await _pruneAlreadyUploadedPhotos();
    await _pruneStalePendingPhotos();

    final sync = _syncService;
    if (sync != null) {
      _statusSubscription = sync.statusStream.listen((status) {
        _syncStatus = status;
        notifyListeners();
      });
      _remoteSubscription = sync.remoteEntriesStream.listen(_mergeRemote);
      _syncStatus = sync.status;
      try {
        await sync.initialize();
      } catch (_) {}
    }
  }

  List<PitScoutEntry> entriesForTeam(int teamNumber) {
    return _entries
        .where((e) => e.teamNumber == teamNumber)
        .toList(growable: false);
  }

  Future<bool> saveEntry(PitScoutEntry entry) async {
    final stamped = entry.copyWith(updatedAt: DateTime.now().toUtc());
    final index = _entries.indexWhere((existing) => existing.id == stamped.id);
    final mutation = _nextMutation(stamped.id);
    if (index >= 0) {
      _entries[index] = stamped;
    } else {
      _entries.add(stamped);
    }
    final snapshot = PitScoutEntry.fromJson(stamped.toJson());
    final saved = _enqueueSave(snapshot);
    notifyListeners();
    if (!await saved) {
      _rollback(
        stamped.id,
        mutation,
        'Could not save the pit entry for team ${stamped.teamNumber}.',
      );
      return false;
    }
    final sync = _syncService;
    if (sync != null) {
      unawaited(sync.push(snapshot));
    }

    unawaited(uploadPendingPhotos());
    return true;
  }

  Future<void> removePhoto(PitScoutEntry entry, String photoId) async {
    final index = _entries.indexWhere((existing) => existing.id == entry.id);
    final current = index >= 0 ? _entries[index] : entry;
    final key = current.photoKeys[photoId];
    try {
      await _photoStore?.delete(entry.id, photoId);
    } catch (_) {}
    await saveEntry(current.withRemovedPhoto(photoId));
    if (key != null) {
      unawaited(_photoUploader?.delete(key) ?? Future<bool>.value(false));
    }
  }

  Future<bool> deleteEntry(String id) async {
    final existing = _entries.firstWhere(
      (entry) => entry.id == id,
      orElse: () => _placeholderEntry,
    );
    if (identical(existing, _placeholderEntry)) return true;
    final mutation = _nextMutation(id);
    _entries.removeWhere((entry) => entry.id == id);
    final deleted = _enqueueDelete(id);

    final wasSynced = _remoteSyncedIds.remove(id);
    if (wasSynced) {
      _persistSyncedIds();
    }
    notifyListeners();
    if (!await deleted) {
      if (wasSynced) {
        _remoteSyncedIds.add(id);
        _persistSyncedIds();
      }
      _rollback(
        id,
        mutation,
        'Could not delete the pit entry for team ${existing.teamNumber}.',
      );
      return false;
    }
    try {
      await _photoStore?.deleteAllForEntry(id);
    } catch (_) {}
    final uploader = _photoUploader;
    if (uploader != null) {
      for (final key in existing.photoKeys.values) {
        unawaited(uploader.delete(key));
      }
    }
    final sync = _syncService;
    if (sync != null) {
      unawaited(sync.delete(existing));
    }
    return true;
  }

  Future<void> syncNow() async {
    await _syncService?.syncNow();

    await uploadPendingPhotos();
  }

  Future<Uint8List?> photoBytes(PitScoutEntry entry, String photoId) async {
    final store = _photoStore;
    if (store != null && entry.photoIds.contains(photoId)) {
      try {
        return await store.readBytes(entry.id, photoId);
      } catch (_) {}
    }
    final key = entry.photoKeys[photoId] ?? photoId;
    return _photoUploader?.download(key);
  }

  Future<void> uploadPendingPhotos() {
    return _uploadPass ??= _uploadPendingPhotos().whenComplete(() {
      _uploadPass = null;
    });
  }

  Future<void> _uploadPendingPhotos() async {
    final uploader = _photoUploader;
    final store = _photoStore;
    if (uploader == null || store == null) return;
    {
      for (final entry in List<PitScoutEntry>.of(_entries)) {
        for (final photoId in entry.pendingPhotoIds.toList(growable: false)) {
          final Uint8List bytes;
          try {
            bytes = await store.readBytes(entry.id, photoId);
          } catch (_) {
            continue;
          }
          final key = await uploader.upload(bytes);
          if (key == null) return;
          await _recordUploadedPhoto(entry.id, photoId, key);
        }
      }
    }
  }

  Future<void> _recordUploadedPhoto(
    String entryId,
    String photoId,
    String key,
  ) async {
    final index = _entries.indexWhere((entry) => entry.id == entryId);
    if (index < 0) {
      await _photoUploader?.delete(key);
      return;
    }
    final updated = _entries[index].withUploadedPhoto(photoId, key);
    if (identical(updated, _entries[index])) {
      await _photoUploader?.delete(key);
      return;
    }

    _entries[index] = updated;
    _enqueueSave(PitScoutEntry.fromJson(updated.toJson()));
    notifyListeners();
    await _saveQueue;
    unawaited(_syncService?.push(updated) ?? Future<void>.value());

    try {
      await _photoStore?.delete(entryId, photoId);
    } catch (_) {}
  }

  Future<void> _pruneAlreadyUploadedPhotos() async {
    final store = _photoStore;
    if (store == null) return;
    for (final entry in List<PitScoutEntry>.of(_entries)) {
      for (final photoId in entry.photoKeys.keys) {
        try {
          await store.delete(entry.id, photoId);
        } catch (_) {}
      }
    }
  }

  static const Duration _staleUploadAge = Duration(days: 14);

  Future<void> _pruneStalePendingPhotos() async {
    final store = _photoStore;
    if (store == null || _photoUploader == null) return;
    final cutoff = DateTime.now().toUtc().subtract(_staleUploadAge);
    for (final snapshot in List<PitScoutEntry>.of(_entries)) {
      for (final photoId in snapshot.pendingPhotoIds.toList(growable: false)) {
        DateTime? capturedAt;
        try {
          capturedAt = await store.capturedAt(snapshot.id, photoId);
        } catch (_) {
          continue;
        }
        if (capturedAt == null || capturedAt.toUtc().isAfter(cutoff)) {
          continue;
        }
        try {
          await store.delete(snapshot.id, photoId);
        } catch (_) {}

        final index = _entries.indexWhere((e) => e.id == snapshot.id);
        if (index < 0) continue;
        await saveEntry(_entries[index].withRemovedPhoto(photoId));
      }
    }
  }

  Future<void> _mergeRemote(List<PitScoutEntry> remote) async {
    var changed = false;
    var syncedChanged = false;
    final remoteIds = <String>{};
    for (final incoming in remote) {
      remoteIds.add(incoming.id);
      if (_remoteSyncedIds.add(incoming.id)) {
        syncedChanged = true;
      }

      _confirmed[incoming.id] = incoming;
      final index = _entries.indexWhere((local) => local.id == incoming.id);
      if (index < 0) {
        _nextMutation(incoming.id);
        _entries.add(incoming);
        _enqueueSave(incoming);
        changed = true;
        continue;
      }
      final existing = _entries[index];
      if (incoming.updatedAt.isAfter(existing.updatedAt)) {
        _nextMutation(incoming.id);
        _entries[index] = incoming;
        _enqueueSave(incoming);
        changed = true;
      }
    }

    final removedRemotely = _remoteSyncedIds
        .where((id) => !remoteIds.contains(id))
        .toList(growable: false);
    for (final id in removedRemotely) {
      _remoteSyncedIds.remove(id);
      syncedChanged = true;
      _confirmed.remove(id);
      final before = _entries.length;
      _entries.removeWhere((entry) => entry.id == id);
      if (_entries.length != before) {
        _nextMutation(id);
        _enqueueDelete(id);
        try {
          await _photoStore?.deleteAllForEntry(id);
        } catch (_) {}
        changed = true;
      }
    }
    if (syncedChanged) {
      _persistSyncedIds();
    }
    if (changed) {
      notifyListeners();
    }
  }

  int _nextMutation(String id) {
    final next = (_mutations[id] ?? 0) + 1;
    _mutations[id] = next;
    return next;
  }

  void _rollback(String id, int mutation, String message) {
    _lastError = message;
    if (_mutations[id] != mutation) {
      notifyListeners();
      return;
    }
    final confirmed = _confirmed[id];
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (confirmed == null) {
      if (index >= 0) _entries.removeAt(index);
    } else if (index >= 0) {
      _entries[index] = confirmed;
    } else {
      _entries.add(confirmed);
    }
    notifyListeners();
  }

  Future<bool> _enqueueSave(PitScoutEntry entry) {
    final result = _saveQueue
        .then((_) => _storage.saveEntry(entry))
        .then(
          (_) {
            _confirmed[entry.id] = entry;
            if (failedWrites.recordSuccess()) notifyListeners();
            return true;
          },
          onError: (Object e) {
            debugPrint('Pit scout entry save failed: $e');
            failedWrites.recordFailure();
            notifyListeners();
            return false;
          },
        );
    _saveQueue = result;
    return result;
  }

  Future<bool> _enqueueDelete(String id) {
    final result = _saveQueue
        .then((_) => _storage.deleteEntry(id))
        .then(
          (_) {
            _confirmed.remove(id);
            if (failedWrites.recordSuccess()) notifyListeners();
            return true;
          },
          onError: (Object e) {
            debugPrint('Pit scout entry delete failed: $e');
            failedWrites.recordFailure();
            notifyListeners();
            return false;
          },
        );
    _saveQueue = result;
    return result;
  }

  void _persistSyncedIds() {
    final snapshot = _remoteSyncedIds.toSet();
    _saveQueue = _saveQueue
        .then((_) => _storage.saveSyncedIds(snapshot))
        .catchError(
          (Object e) => debugPrint('Pit scout synced-id save failed: $e'),
        );
  }

  static final PitScoutEntry _placeholderEntry = PitScoutEntry(
    id: '__missing__',
    teamNumber: 0,
  );

  @override
  void dispose() {
    _remoteSubscription?.cancel();
    _statusSubscription?.cancel();
    _syncService?.dispose();
    super.dispose();
  }
}
