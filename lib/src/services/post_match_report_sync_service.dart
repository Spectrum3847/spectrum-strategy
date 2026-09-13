import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/post_match_report.dart';
import 'spectrum_auth_service.dart';

enum PostMatchReportSyncState { signedOut, noAccess, syncing, synced, offline }

class PostMatchReportSyncStatus {
  const PostMatchReportSyncStatus({required this.state, this.lastSyncedAt});

  final PostMatchReportSyncState state;
  final DateTime? lastSyncedAt;
}

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
      _emit(
        PostMatchReportSyncStatus(
          state: PostMatchReportSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
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
