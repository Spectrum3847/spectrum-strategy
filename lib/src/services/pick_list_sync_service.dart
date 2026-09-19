import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pick_list.dart';
import 'spectrum_auth_service.dart';

enum PickListSyncState { signedOut, noAccess, syncing, synced, offline }

class PickListSyncStatus {
  const PickListSyncStatus({
    required this.state,
    this.lastSyncedAt,
    this.error,
  });

  final PickListSyncState state;
  final DateTime? lastSyncedAt;
  final String? error;
}

abstract class PickListSyncService {
  Stream<PickListSyncStatus> get statusStream;
  PickListSyncStatus get status;
  Stream<List<PickList>> get remoteListsStream;
  String? get currentUserUid;
  String? get currentUserDisplayName;
  Future<void> initialize();
  Future<void> push(PickList list);

  Future<void> pushTeamAdd(PickList list, int team);

  Future<void> pushTeamRemove(PickList list, int team);
  Future<void> delete(PickList list);
  Future<void> syncNow();
  Future<void> dispose();
}

class FirestorePickListSyncService implements PickListSyncService {
  FirestorePickListSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<PickListSyncStatus> _statusController =
      StreamController<PickListSyncStatus>.broadcast();
  final StreamController<List<PickList>> _remoteController =
      StreamController<List<PickList>>.broadcast();

  PickListSyncStatus _status = const PickListSyncStatus(
    state: PickListSyncState.signedOut,
  );
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteSubscription;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  @override
  Stream<PickListSyncStatus> get statusStream => _statusController.stream;

  @override
  PickListSyncStatus get status => _status;

  @override
  Stream<List<PickList>> get remoteListsStream => _remoteController.stream;

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
      _emit(const PickListSyncStatus(state: PickListSyncState.signedOut));
    }
  }

  @override
  Future<void> push(PickList list) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }

    final stamped = list.copyWith(
      authorUid: list.authorUid.isEmpty ? user.uid : list.authorUid,
      authorDisplayName: list.authorDisplayName.isEmpty
          ? user.displayName
          : list.authorDisplayName,
    );
    try {
      await _collection().doc(stamped.id).set(<String, dynamic>{
        ...stamped.toJson(),

        'updatedAtTs': Timestamp.fromDate(stamped.updatedAt.toUtc()),
      });
      _emit(
        PickListSyncStatus(
          state: PickListSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        PickListSyncStatus(
          state: PickListSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> pushTeamAdd(PickList list, int team) {
    return _pushTeamOp(list, <String, Object?>{
      'teamNumbers': FieldValue.arrayUnion(<int>[team]),
    });
  }

  @override
  Future<void> pushTeamRemove(PickList list, int team) {
    return _pushTeamOp(list, <String, Object?>{
      'teamNumbers': FieldValue.arrayRemove(<int>[team]),
    });
  }

  Future<void> _pushTeamOp(PickList list, Map<String, Object?> op) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }
    try {
      await _collection().doc(list.id).update(<String, Object?>{
        ...op,
        'updatedAt': list.updatedAt.toUtc().toIso8601String(),
        'updatedAtTs': Timestamp.fromDate(list.updatedAt.toUtc()),
      });
      _emit(
        PickListSyncStatus(
          state: PickListSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } on FirebaseException catch (error) {
      if (error.code == 'not-found') {
        await push(list);
        return;
      }
      _emit(
        PickListSyncStatus(
          state: PickListSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.toString(),
        ),
      );
    } catch (error) {
      _emit(
        PickListSyncStatus(
          state: PickListSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> delete(PickList list) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }

    try {
      await _collection().doc(list.id).delete();
      _emit(
        PickListSyncStatus(
          state: PickListSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        PickListSyncStatus(
          state: PickListSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> syncNow() async {
    if (_authService.currentUser == null) {
      _emit(const PickListSyncStatus(state: PickListSyncState.signedOut));
      return;
    }
    try {
      final snapshot = await _collection().get();
      _emitRemote(snapshot.docs.map(_decode).whereType<PickList>().toList());
      _emit(
        PickListSyncStatus(
          state: PickListSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        PickListSyncStatus(
          state: PickListSyncState.offline,
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
    return _firestore.collection('pickLists');
  }

  void _subscribeToRemote() {
    _remoteSubscription?.cancel();
    _emit(const PickListSyncStatus(state: PickListSyncState.syncing));
    _remoteSubscription = _collection().snapshots().listen(
      (snapshot) {
        final lists = snapshot.docs.map(_decode).whereType<PickList>().toList();
        _emitRemote(lists);
        _emit(
          PickListSyncStatus(
            state: PickListSyncState.synced,
            lastSyncedAt: DateTime.now(),
          ),
        );
      },
      onError: (Object error) {
        if (error is FirebaseException && error.code == 'permission-denied') {
          _emit(
            PickListSyncStatus(
              state: PickListSyncState.noAccess,
              lastSyncedAt: _status.lastSyncedAt,
              error: error.message,
            ),
          );
          return;
        }
        _emit(
          PickListSyncStatus(
            state: PickListSyncState.offline,
            lastSyncedAt: _status.lastSyncedAt,
            error: error.toString(),
          ),
        );
      },
    );
  }

  PickList? _decode(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      final list = PickList.fromJson(data);

      final ts = data['updatedAtTs'];
      if (ts is Timestamp) {
        return list.copyWith(updatedAt: ts.toDate().toUtc());
      }
      return list;
    } catch (_) {
      return null;
    }
  }

  void _emit(PickListSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void _emitRemote(List<PickList> lists) {
    if (!_remoteController.isClosed) {
      _remoteController.add(lists);
    }
  }
}
