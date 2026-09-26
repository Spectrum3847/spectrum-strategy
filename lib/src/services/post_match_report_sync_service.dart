import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../models/post_match_report.dart';
import 'spectrum_auth_service.dart';

enum PostMatchReportSyncState {
  signedOut,

  noAccess,
  syncing,
  synced,
  offline,

  rejected,
}

class PostMatchReportSyncStatus {
  const PostMatchReportSyncStatus({
    required this.state,
    this.lastSyncedAt,
    this.error,
  });

  final PostMatchReportSyncState state;
  final DateTime? lastSyncedAt;
  final String? error;
}

bool _isPermissionDenied(Object error) {
  final errorText = error.toString().toLowerCase();
  return (error is FirebaseException && error.code == 'permission-denied') ||
      (error is PlatformException && error.code == 'permission-denied') ||
      (errorText.contains('permission') && errorText.contains('denied'));
}

String _permissionErrorMessage(Object error) => switch (error) {
  FirebaseException(:final message) => message ?? error.toString(),
  PlatformException(:final message) => message ?? error.toString(),
  _ => error.toString(),
};

abstract class PostMatchReportSyncService {
  Stream<PostMatchReportSyncStatus> get statusStream;
  PostMatchReportSyncStatus get status;

  Stream<List<PostMatchReport>> get remoteReportsStream;

  String? get currentUserUid;
  String? get currentUserDisplayName;

  Future<void> initialize();
  Future<void> push(PostMatchReport report);
  Future<void> dispose();
}

class FirestorePostMatchReportSyncService
    implements PostMatchReportSyncService {
  FirestorePostMatchReportSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collection = 'postMatchReports';

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<PostMatchReportSyncStatus> _statusController =
      StreamController<PostMatchReportSyncStatus>.broadcast();
  final StreamController<List<PostMatchReport>> _remoteController =
      StreamController<List<PostMatchReport>>.broadcast();

  PostMatchReportSyncStatus _status = const PostMatchReportSyncStatus(
    state: PostMatchReportSyncState.signedOut,
  );
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteSubscription;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  @override
  Stream<PostMatchReportSyncStatus> get statusStream =>
      _statusController.stream;

  @override
  PostMatchReportSyncStatus get status => _status;

  @override
  Stream<List<PostMatchReport>> get remoteReportsStream =>
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
      _emit(
        const PostMatchReportSyncStatus(
          state: PostMatchReportSyncState.signedOut,
        ),
      );
    }
  }

  @override
  Future<void> push(PostMatchReport report) async {
    if (_authService.currentUser == null) {
      return;
    }
    final payload = report.toJson()
      ..['updatedAtTs'] = FieldValue.serverTimestamp();
    try {
      await _firestore.doc('$collection/${report.id}').set(payload);
      _emit(
        PostMatchReportSyncStatus(
          state: PostMatchReportSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(_pushFailure(error));
    }
  }

  PostMatchReportSyncStatus _pushFailure(Object error) {
    if (_isPermissionDenied(error)) {
      return PostMatchReportSyncStatus(
        state: PostMatchReportSyncState.rejected,
        lastSyncedAt: _status.lastSyncedAt,
        error: _permissionErrorMessage(error),
      );
    }
    return PostMatchReportSyncStatus(
      state: PostMatchReportSyncState.offline,
      lastSyncedAt: _status.lastSyncedAt,
      error: error.toString(),
    );
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
    _emit(
      const PostMatchReportSyncStatus(state: PostMatchReportSyncState.syncing),
    );
    _remoteSubscription = _firestore
        .collection(collection)
        .snapshots()
        .listen(
          (snapshot) {
            final reports = snapshot.docs
                .map(_decode)
                .whereType<PostMatchReport>()
                .toList();
            if (!_remoteController.isClosed) {
              _remoteController.add(reports);
            }
            _emit(
              PostMatchReportSyncStatus(
                state: PostMatchReportSyncState.synced,
                lastSyncedAt: DateTime.now(),
              ),
            );
          },

          onError: (Object error) {
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              _emit(
                const PostMatchReportSyncStatus(
                  state: PostMatchReportSyncState.noAccess,
                ),
              );
              return;
            }
            _emit(
              PostMatchReportSyncStatus(
                state: PostMatchReportSyncState.offline,
                lastSyncedAt: _status.lastSyncedAt,
              ),
            );
          },
        );
  }

  PostMatchReport? _decode(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      final report = PostMatchReport.fromJson(data);

      final ts = data['updatedAtTs'];
      if (ts is Timestamp) {
        return report.copyWith(updatedAt: ts.toDate().toUtc());
      }
      return report;
    } catch (_) {
      return null;
    }
  }

  void _emit(PostMatchReportSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }
}
