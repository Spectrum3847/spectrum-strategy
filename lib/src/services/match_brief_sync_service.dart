import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../models/match_brief.dart';
import 'spectrum_auth_service.dart';

enum MatchBriefSyncState {
  signedOut,

  noAccess,
  syncing,
  synced,
  offline,

  rejected,
}

class MatchBriefSyncStatus {
  const MatchBriefSyncStatus({
    required this.state,
    this.lastSyncedAt,
    this.error,
  });

  final MatchBriefSyncState state;
  final DateTime? lastSyncedAt;
  final String? error;
}

bool _isPermissionDenied(Object error) {
  final errorText = error.toString().toLowerCase();
  return (error is FirebaseException && error.code == 'permission-denied') ||
      (error is PlatformException && error.code == 'permission-denied') ||
      (errorText.contains('permission') && errorText.contains('denied'));
}

abstract class MatchBriefSyncService {
  Stream<MatchBriefSyncStatus> get statusStream;
  MatchBriefSyncStatus get status;
  Stream<List<MatchBrief>> get remoteBriefsStream;

  String? get currentUserUid;
  String? get currentUserDisplayName;

  Future<void> initialize();
  Future<void> push(MatchBrief brief);
  Future<void> dispose();
}

class FirestoreMatchBriefSyncService implements MatchBriefSyncService {
  FirestoreMatchBriefSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collection = 'matchBriefs';

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<MatchBriefSyncStatus> _statusController =
      StreamController<MatchBriefSyncStatus>.broadcast();
  final StreamController<List<MatchBrief>> _remoteController =
      StreamController<List<MatchBrief>>.broadcast();

  MatchBriefSyncStatus _status = const MatchBriefSyncStatus(
    state: MatchBriefSyncState.signedOut,
  );
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteSubscription;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  @override
  Stream<MatchBriefSyncStatus> get statusStream => _statusController.stream;

  @override
  MatchBriefSyncStatus get status => _status;

  @override
  Stream<List<MatchBrief>> get remoteBriefsStream => _remoteController.stream;

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
      _emit(const MatchBriefSyncStatus(state: MatchBriefSyncState.signedOut));
    }
  }

  @override
  Future<void> push(MatchBrief brief) async {
    if (_authService.currentUser == null) return;
    final payload = brief.toJson()
      ..['updatedAtTs'] = Timestamp.fromDate(brief.updatedAt.toUtc());
    try {
      await _firestore.doc('$collection/${brief.id}').set(payload);
      _emit(
        MatchBriefSyncStatus(
          state: MatchBriefSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        MatchBriefSyncStatus(
          state: _isPermissionDenied(error)
              ? MatchBriefSyncState.rejected
              : MatchBriefSyncState.offline,
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

  void _subscribeToRemote() {
    _remoteSubscription?.cancel();
    _emit(const MatchBriefSyncStatus(state: MatchBriefSyncState.syncing));
    _remoteSubscription = _firestore
        .collection(collection)
        .snapshots()
        .listen(
          (snapshot) {
            final briefs = snapshot.docs
                .map(_decode)
                .whereType<MatchBrief>()
                .toList();
            if (!_remoteController.isClosed) _remoteController.add(briefs);
            _emit(
              MatchBriefSyncStatus(
                state: MatchBriefSyncState.synced,
                lastSyncedAt: DateTime.now(),
              ),
            );
          },

          onError: (Object error) {
            _emit(
              MatchBriefSyncStatus(
                state: _isPermissionDenied(error)
                    ? MatchBriefSyncState.noAccess
                    : MatchBriefSyncState.offline,
                lastSyncedAt: _status.lastSyncedAt,
              ),
            );
          },
        );
  }

  MatchBrief? _decode(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      final brief = MatchBrief.fromJson(data);

      final ts = data['updatedAtTs'];
      return ts is Timestamp
          ? brief.copyWith(updatedAt: ts.toDate().toUtc())
          : brief;
    } catch (_) {
      return null;
    }
  }

  void _emit(MatchBriefSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }
}
