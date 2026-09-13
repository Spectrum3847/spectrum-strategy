import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/spectrum_auth_service.dart';
import '../models/pit_scout_entry.dart';

enum PitScoutingSyncState { signedOut, noAccess, syncing, synced, offline }

class PitScoutingSyncStatus {
  const PitScoutingSyncStatus({
    required this.state,
    this.lastSyncedAt,
    this.error,
  });

  final PitScoutingSyncState state;
  final DateTime? lastSyncedAt;
  final String? error;
}

abstract class PitScoutingSyncService {
  Stream<PitScoutingSyncStatus> get statusStream;
  PitScoutingSyncStatus get status;
  Stream<List<PitScoutEntry>> get remoteEntriesStream;
  String? get currentUserUid;
  String? get currentUserDisplayName;
  Future<void> initialize();
  Future<void> push(PitScoutEntry entry);
  Future<void> delete(PitScoutEntry entry);
  Future<void> syncNow();
  Future<void> dispose();
}

class FirestorePitScoutingSyncService implements PitScoutingSyncService {
  FirestorePitScoutingSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<PitScoutingSyncStatus> _statusController =
      StreamController<PitScoutingSyncStatus>.broadcast();
  final StreamController<List<PitScoutEntry>> _remoteController =
      StreamController<List<PitScoutEntry>>.broadcast();

  PitScoutingSyncStatus _status = const PitScoutingSyncStatus(
    state: PitScoutingSyncState.signedOut,
  );
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteSubscription;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  @override
  Stream<PitScoutingSyncStatus> get statusStream => _statusController.stream;

  @override
  PitScoutingSyncStatus get status => _status;

  @override
  Stream<List<PitScoutEntry>> get remoteEntriesStream =>
      _remoteController.stream;

  @override
  String? get currentUserUid => _authService.currentUser?.uid;

  @override
  String? get currentUserDisplayName => _authService.currentUser?.displayName;

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
      _emit(const PitScoutingSyncStatus(state: PitScoutingSyncState.signedOut));
    }
  }

  @override
  Future<void> push(PitScoutEntry entry) async {
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
        ...stamped.toRemoteJson(),

        'updatedAtTs': Timestamp.fromDate(stamped.updatedAt.toUtc()),
      });
      _emit(
        PitScoutingSyncStatus(
          state: PitScoutingSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        PitScoutingSyncStatus(
          state: PitScoutingSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> delete(PitScoutEntry entry) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }

    try {
      await _collection().doc(entry.id).delete();
      _emit(
        PitScoutingSyncStatus(
          state: PitScoutingSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        PitScoutingSyncStatus(
          state: PitScoutingSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> syncNow() async {
    if (_authService.currentUser == null) {
      _emit(const PitScoutingSyncStatus(state: PitScoutingSyncState.signedOut));
      return;
    }
    try {
      final snapshot = await _collection().get();
      _emitRemote(
        snapshot.docs.map(_decode).whereType<PitScoutEntry>().toList(),
      );
      _emit(
        PitScoutingSyncStatus(
          state: PitScoutingSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        PitScoutingSyncStatus(
          state: PitScoutingSyncState.offline,
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
    return _firestore.collection('pitScoutEntries');
  }

  void _subscribeToRemote() {
    _remoteSubscription?.cancel();
    _emit(const PitScoutingSyncStatus(state: PitScoutingSyncState.syncing));
    _remoteSubscription = _collection().snapshots().listen(
      (snapshot) {
        final entries = snapshot.docs
            .map(_decode)
            .whereType<PitScoutEntry>()
            .toList();
        _emitRemote(entries);
        _emit(
          PitScoutingSyncStatus(
            state: PitScoutingSyncState.synced,
            lastSyncedAt: DateTime.now(),
          ),
        );
      },
      onError: (Object error) {
        if (error is FirebaseException && error.code == 'permission-denied') {
          _emit(
            PitScoutingSyncStatus(
              state: PitScoutingSyncState.noAccess,
              lastSyncedAt: _status.lastSyncedAt,
              error: error.message,
            ),
          );
          return;
        }
        _emit(
          PitScoutingSyncStatus(
            state: PitScoutingSyncState.offline,
            lastSyncedAt: _status.lastSyncedAt,
            error: error.toString(),
          ),
        );
      },
    );
  }

  PitScoutEntry? _decode(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      final entry = PitScoutEntry.fromJson(data);

      final ts = data['updatedAtTs'];
      if (ts is Timestamp) {
        return entry.copyWith(updatedAt: ts.toDate().toUtc());
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  void _emit(PitScoutingSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void _emitRemote(List<PitScoutEntry> entries) {
    if (!_remoteController.isClosed) {
      _remoteController.add(entries);
    }
  }
}
