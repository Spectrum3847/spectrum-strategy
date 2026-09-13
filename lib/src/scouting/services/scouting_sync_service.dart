import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../../services/spectrum_auth_service.dart';
import '../models/scout_entry.dart';

enum ScoutingSyncState { signedOut, noAccess, syncing, synced, offline }

class ScoutingSyncStatus {
  const ScoutingSyncStatus({
    required this.state,
    this.lastSyncedAt,
    this.error,
    this.pendingWrites = 0,
  });

  final ScoutingSyncState state;
  final DateTime? lastSyncedAt;
  final String? error;

  final int pendingWrites;
}

abstract class ScoutingSyncService {
  Stream<ScoutingSyncStatus> get statusStream;
  ScoutingSyncStatus get status;
  Stream<List<ScoutEntry>> get remoteEntriesStream;
  Future<void> initialize();
  Future<void> push(ScoutEntry entry);
  Future<void> delete(ScoutEntry entry);
  Future<void> syncNow();
  Future<void> dispose();
}

class FirestoreScoutingSyncService implements ScoutingSyncService {
  FirestoreScoutingSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<ScoutingSyncStatus> _statusController =
      StreamController<ScoutingSyncStatus>.broadcast();
  final StreamController<List<ScoutEntry>> _remoteController =
      StreamController<List<ScoutEntry>>.broadcast();

  ScoutingSyncStatus _status = const ScoutingSyncStatus(
    state: ScoutingSyncState.signedOut,
  );
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteSubscription;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  @override
  Stream<ScoutingSyncStatus> get statusStream => _statusController.stream;

  @override
  ScoutingSyncStatus get status => _status;

  @override
  Stream<List<ScoutEntry>> get remoteEntriesStream => _remoteController.stream;

  @override
  Future<void> initialize() async {
    _authSubscription = _authService.snapshotStream.listen(_onAuthChanged);
    _onAuthChanged(_authService.snapshot);
  }

  void _onAuthChanged(SpectrumAuthSnapshot snapshot) {
    if (snapshot.state == SpectrumAuthState.signedIn) {
      _subscribeToRemote();
    } else {
      _remoteSubscription?.cancel();
      _remoteSubscription = null;
      _emit(const ScoutingSyncStatus(state: ScoutingSyncState.signedOut));
    }
  }

  @override
  Future<void> push(ScoutEntry entry) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }

    final stamped = entry.copyWith(
      authorUid: entry.authorUid.isEmpty ? user.uid : entry.authorUid,
      authorDisplayName: entry.authorDisplayName.isEmpty
          ? user.displayName
          : entry.authorDisplayName,
    );
    try {
      await _collection().doc(stamped.id).set(<String, dynamic>{
        ...stamped.toJson(),

        'updatedAtTs': Timestamp.fromDate(stamped.updatedAt.toUtc()),
      });
      _emit(
        ScoutingSyncStatus(
          state: ScoutingSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        ScoutingSyncStatus(
          state: ScoutingSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> delete(ScoutEntry entry) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }

    try {
      await _collection().doc(entry.id).delete();
      _emit(
        ScoutingSyncStatus(
          state: ScoutingSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        ScoutingSyncStatus(
          state: ScoutingSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> syncNow() async {
    if (_authService.currentUser == null) {
      _emit(const ScoutingSyncStatus(state: ScoutingSyncState.signedOut));
      return;
    }
    try {
      final snapshot = await _currentSeasonQuery().get();
      _emitRemote(snapshot.docs.map(_decode).whereType<ScoutEntry>().toList());
      _emit(
        ScoutingSyncStatus(
          state: ScoutingSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        ScoutingSyncStatus(
          state: ScoutingSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    await _remoteSubscription?.cancel();
    await _authSubscription?.cancel();
    await _statusController.close();
    await _remoteController.close();
  }

  CollectionReference<Map<String, dynamic>> _collection() {
    return _firestore.collection('scoutEntries');
  }

  Query<Map<String, dynamic>> _currentSeasonQuery() {
    final yearStart = DateTime.utc(DateTime.now().year, 1, 1).toIso8601String();
    return _collection().where('updatedAt', isGreaterThanOrEqualTo: yearStart);
  }

  void _subscribeToRemote() {
    _remoteSubscription?.cancel();
    _emit(const ScoutingSyncStatus(state: ScoutingSyncState.syncing));
    _remoteSubscription = _currentSeasonQuery().snapshots().listen(
      (snapshot) {
        final entries = snapshot.docs
            .map(_decode)
            .whereType<ScoutEntry>()
            .toList();
        _emitRemote(entries);
        _emit(
          ScoutingSyncStatus(
            state: ScoutingSyncState.synced,
            lastSyncedAt: DateTime.now(),
          ),
        );
      },
      onError: (Object error) {
        final errorText = error.toString().toLowerCase();
        final deniedByRules =
            (error is FirebaseException && error.code == 'permission-denied') ||
            (error is PlatformException && error.code == 'permission-denied') ||
            (errorText.contains('permission') && errorText.contains('denied'));
        if (deniedByRules) {
          final message = switch (error) {
            FirebaseException(:final message) => message,
            PlatformException(:final message) => message,
            _ => null,
          };
          _emit(
            ScoutingSyncStatus(
              state: ScoutingSyncState.noAccess,
              lastSyncedAt: _status.lastSyncedAt,
              error: message,
            ),
          );
          return;
        }
        _emit(
          ScoutingSyncStatus(
            state: ScoutingSyncState.offline,
            lastSyncedAt: _status.lastSyncedAt,
            error: error.toString(),
          ),
        );
      },
    );
  }

  ScoutEntry? _decode(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      final entry = ScoutEntry.fromJson(data);

      final ts = data['updatedAtTs'];
      if (ts is Timestamp) {
        return entry.copyWith(updatedAt: ts.toDate().toUtc());
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  void _emit(ScoutingSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void _emitRemote(List<ScoutEntry> entries) {
    if (!_remoteController.isClosed) {
      _remoteController.add(entries);
    }
  }
}
