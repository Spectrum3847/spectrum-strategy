import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/spectrum_auth_service.dart';
import '../models/prescout_entry.dart';

enum PrescoutingSyncState { signedOut, noAccess, syncing, synced, offline }

class PrescoutingSyncStatus {
  const PrescoutingSyncStatus({
    required this.state,
    this.lastSyncedAt,
    this.error,
  });

  final PrescoutingSyncState state;
  final DateTime? lastSyncedAt;
  final String? error;
}

abstract class PrescoutingSyncService {
  Stream<PrescoutingSyncStatus> get statusStream;
  PrescoutingSyncStatus get status;
  Stream<List<PrescoutEntry>> get remoteEntriesStream;
  String? get currentUserUid;
  String? get currentUserDisplayName;
  Future<void> initialize();
  Future<void> push(PrescoutEntry entry);
  Future<void> delete(PrescoutEntry entry);
  Future<void> syncNow();
  Future<void> dispose();
}

class FirestorePrescoutingSyncService implements PrescoutingSyncService {
  FirestorePrescoutingSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<PrescoutingSyncStatus> _statusController =
      StreamController<PrescoutingSyncStatus>.broadcast();
  final StreamController<List<PrescoutEntry>> _remoteController =
      StreamController<List<PrescoutEntry>>.broadcast();

  PrescoutingSyncStatus _status = const PrescoutingSyncStatus(
    state: PrescoutingSyncState.signedOut,
  );
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteSubscription;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  @override
  Stream<PrescoutingSyncStatus> get statusStream => _statusController.stream;

  @override
  PrescoutingSyncStatus get status => _status;

  @override
  Stream<List<PrescoutEntry>> get remoteEntriesStream =>
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
      _emit(const PrescoutingSyncStatus(state: PrescoutingSyncState.signedOut));
    }
  }

  @override
  Future<void> push(PrescoutEntry entry) async {
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
        PrescoutingSyncStatus(
          state: PrescoutingSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        PrescoutingSyncStatus(
          state: PrescoutingSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> delete(PrescoutEntry entry) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }

    try {
      await _collection().doc(entry.id).delete();
      _emit(
        PrescoutingSyncStatus(
          state: PrescoutingSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        PrescoutingSyncStatus(
          state: PrescoutingSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> syncNow() async {
    if (_authService.currentUser == null) {
      _emit(const PrescoutingSyncStatus(state: PrescoutingSyncState.signedOut));
      return;
    }
    try {
      final snapshot = await _collection().get();
      _emitRemote(
        snapshot.docs.map(_decode).whereType<PrescoutEntry>().toList(),
      );
      _emit(
        PrescoutingSyncStatus(
          state: PrescoutingSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        PrescoutingSyncStatus(
          state: PrescoutingSyncState.offline,
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
    return _firestore.collection('prescoutEntries');
  }

  void _subscribeToRemote() {
    _remoteSubscription?.cancel();
    _emit(const PrescoutingSyncStatus(state: PrescoutingSyncState.syncing));
    _remoteSubscription = _collection().snapshots().listen(
      (snapshot) {
        final entries = snapshot.docs
            .map(_decode)
            .whereType<PrescoutEntry>()
            .toList();
        _emitRemote(entries);
        _emit(
          PrescoutingSyncStatus(
            state: PrescoutingSyncState.synced,
            lastSyncedAt: DateTime.now(),
          ),
        );
      },
      onError: (Object error) {
        if (error is FirebaseException && error.code == 'permission-denied') {
          _emit(
            PrescoutingSyncStatus(
              state: PrescoutingSyncState.noAccess,
              lastSyncedAt: _status.lastSyncedAt,
              error: error.message,
            ),
          );
          return;
        }
        _emit(
          PrescoutingSyncStatus(
            state: PrescoutingSyncState.offline,
            lastSyncedAt: _status.lastSyncedAt,
            error: error.toString(),
          ),
        );
      },
    );
  }

  PrescoutEntry? _decode(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      final entry = PrescoutEntry.fromJson(data);

      final ts = data['updatedAtTs'];
      if (ts is Timestamp) {
        return entry.copyWith(updatedAt: ts.toDate().toUtc());
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  void _emit(PrescoutingSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void _emitRemote(List<PrescoutEntry> entries) {
    if (!_remoteController.isClosed) {
      _remoteController.add(entries);
    }
  }
}
