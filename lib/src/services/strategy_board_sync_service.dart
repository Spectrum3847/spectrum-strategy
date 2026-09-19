import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/strategy_session.dart';
import 'spectrum_auth_service.dart';

enum StrategyBoardSyncState { signedOut, noAccess, syncing, synced, offline }

class StrategyBoardSyncStatus {
  const StrategyBoardSyncStatus({
    required this.state,
    this.lastSyncedAt,
    this.error,
  });

  final StrategyBoardSyncState state;
  final DateTime? lastSyncedAt;
  final String? error;
}

abstract class StrategyBoardSyncService {
  Stream<StrategyBoardSyncStatus> get statusStream;
  StrategyBoardSyncStatus get status;
  Stream<List<StrategySession>> get remoteBoardsStream;
  Future<void> initialize();
  Future<void> push(StrategySession session);
  Future<void> delete(StrategySession session);
  Future<void> syncNow();
  Future<void> dispose();
}

class FirestoreStrategyBoardSyncService implements StrategyBoardSyncService {
  FirestoreStrategyBoardSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<StrategyBoardSyncStatus> _statusController =
      StreamController<StrategyBoardSyncStatus>.broadcast();
  final StreamController<List<StrategySession>> _remoteController =
      StreamController<List<StrategySession>>.broadcast();

  StrategyBoardSyncStatus _status = const StrategyBoardSyncStatus(
    state: StrategyBoardSyncState.signedOut,
  );
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteSubscription;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  @override
  Stream<StrategyBoardSyncStatus> get statusStream => _statusController.stream;

  @override
  StrategyBoardSyncStatus get status => _status;

  @override
  Stream<List<StrategySession>> get remoteBoardsStream =>
      _remoteController.stream;

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
      _emitRemote(<StrategySession>[]);
      _emit(
        const StrategyBoardSyncStatus(state: StrategyBoardSyncState.signedOut),
      );
    }
  }

  @override
  Future<void> push(StrategySession session) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }
    try {
      final json = prepareBoardPayload(
        session,
        user.uid,
        user.displayName,
        Timestamp.fromDate(session.updatedAt.toUtc()),
      );
      await _collection().doc(session.id).set(json);
      _emit(
        StrategyBoardSyncStatus(
          state: StrategyBoardSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emitFailure(error);
    }
  }

  @override
  Future<void> delete(StrategySession session) async {
    final user = _authService.currentUser;
    if (user == null) {
      return;
    }
    try {
      await _collection().doc(session.id).delete();
      _emit(
        StrategyBoardSyncStatus(
          state: StrategyBoardSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emitFailure(error);
    }
  }

  @override
  Future<void> syncNow() async {
    if (_authService.currentUser == null) {
      _emit(
        const StrategyBoardSyncStatus(state: StrategyBoardSyncState.signedOut),
      );
      return;
    }
    try {
      final snapshot = await _collection().get();
      _emitRemote(
        snapshot.docs.map(_decode).whereType<StrategySession>().toList(),
      );
      _emit(
        StrategyBoardSyncStatus(
          state: StrategyBoardSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emitFailure(error);
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
    return _firestore.collection('strategyBoards');
  }

  void _subscribeToRemote() {
    _remoteSubscription?.cancel();
    _emit(const StrategyBoardSyncStatus(state: StrategyBoardSyncState.syncing));
    _remoteSubscription = _collection().snapshots().listen((snapshot) {
      final boards = snapshot.docs
          .map(_decode)
          .whereType<StrategySession>()
          .toList();
      _emitRemote(boards);
      _emit(
        StrategyBoardSyncStatus(
          state: StrategyBoardSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    }, onError: _emitFailure);
  }

  StrategySession? _decode(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      final session = StrategySession.fromJson(data);
      final ts = data['updatedAtTs'];
      if (ts is Timestamp) {
        session.updatedAt = ts.toDate().toUtc();
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  void _emit(StrategyBoardSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void _emitRemote(List<StrategySession> boards) {
    if (!_remoteController.isClosed) {
      _remoteController.add(boards);
    }
  }

  void _emitFailure(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      _emitRemote(<StrategySession>[]);
      _emit(
        StrategyBoardSyncStatus(
          state: StrategyBoardSyncState.noAccess,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.message,
        ),
      );
      return;
    }
    _emit(
      StrategyBoardSyncStatus(
        state: StrategyBoardSyncState.offline,
        lastSyncedAt: _status.lastSyncedAt,
        error: error.toString(),
      ),
    );
  }
}

Map<String, dynamic> prepareBoardPayload(
  StrategySession session,
  String uid,
  String? displayName,
  Object updatedAtTs,
) {
  final json = session.toJson();
  final existingAuthor = json['authorUid'] as String?;
  json['authorUid'] = (existingAuthor != null && existingAuthor.isNotEmpty)
      ? existingAuthor
      : uid;
  final existingName = json['authorDisplayName'] as String?;

  json['authorDisplayName'] = (existingName != null && existingName.isNotEmpty)
      ? existingName
      : (displayName ?? '');
  json['updatedAtTs'] = updatedAtTs;
  return json;
}
