import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../models/trex_trait_report.dart';
import 'spectrum_auth_service.dart';

enum TrexTraitReportSyncState { signedOut, noAccess, syncing, synced, offline }

class TrexTraitReportSyncStatus {
  const TrexTraitReportSyncStatus({
    required this.state,
    this.lastSyncedAt,
    this.error,
    this.pendingWrites = 0,
  });

  final TrexTraitReportSyncState state;
  final DateTime? lastSyncedAt;
  final String? error;

  final int pendingWrites;
}

abstract class TrexTraitReportSyncService {
  Stream<TrexTraitReportSyncStatus> get statusStream;
  TrexTraitReportSyncStatus get status;
  Stream<List<TrexTraitReport>> get remoteReportsStream;
  Future<void> initialize();
  Future<void> push(TrexTraitReport report);
  Future<void> syncNow();
  Future<void> dispose();
}

class FirestoreTrexTraitReportSyncService
    implements TrexTraitReportSyncService {
  FirestoreTrexTraitReportSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<TrexTraitReportSyncStatus> _statusController =
      StreamController<TrexTraitReportSyncStatus>.broadcast();
  final StreamController<List<TrexTraitReport>> _remoteController =
      StreamController<List<TrexTraitReport>>.broadcast();

  TrexTraitReportSyncStatus _status = const TrexTraitReportSyncStatus(
    state: TrexTraitReportSyncState.signedOut,
  );
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remoteSubscription;
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  @override
  Stream<TrexTraitReportSyncStatus> get statusStream =>
      _statusController.stream;

  @override
  TrexTraitReportSyncStatus get status => _status;

  @override
  Stream<List<TrexTraitReport>> get remoteReportsStream =>
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
      _emit(
        const TrexTraitReportSyncStatus(
          state: TrexTraitReportSyncState.signedOut,
        ),
      );
    }
  }

  @override
  Future<void> push(TrexTraitReport report) async {
    final user = _authService.currentUser;
    if (user == null) return;
    final stamped = report.copyWith(
      authorUid: report.authorUid.isEmpty ? user.uid : report.authorUid,
      authorDisplayName: report.authorDisplayName.isEmpty
          ? user.displayName
          : report.authorDisplayName,
    );
    try {
      await _collection().doc(stamped.id).set(<String, dynamic>{
        ...stamped.toJson(),
        'updatedAtTs': Timestamp.fromDate(stamped.updatedAt.toUtc()),
      });
      _emit(
        TrexTraitReportSyncStatus(
          state: TrexTraitReportSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        TrexTraitReportSyncStatus(
          state: TrexTraitReportSyncState.offline,
          lastSyncedAt: _status.lastSyncedAt,
          error: error.toString(),
        ),
      );
    }
  }

  @override
  Future<void> syncNow() async {
    if (_authService.currentUser == null) {
      _emit(
        const TrexTraitReportSyncStatus(
          state: TrexTraitReportSyncState.signedOut,
        ),
      );
      return;
    }
    try {
      final snapshot = await _collection().get();
      _emitRemote(
        snapshot.docs.map(_decode).whereType<TrexTraitReport>().toList(),
      );
      _emit(
        TrexTraitReportSyncStatus(
          state: TrexTraitReportSyncState.synced,
          lastSyncedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      _emit(
        TrexTraitReportSyncStatus(
          state: TrexTraitReportSyncState.offline,
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
    return _firestore.collection('trexTraitReports');
  }

  void _subscribeToRemote() {
    _remoteSubscription?.cancel();
    _emit(
      const TrexTraitReportSyncStatus(state: TrexTraitReportSyncState.syncing),
    );
    _remoteSubscription = _collection().snapshots().listen(
      (snapshot) {
        final reports = snapshot.docs
            .map(_decode)
            .whereType<TrexTraitReport>()
            .toList();
        _emitRemote(reports);
        _emit(
          TrexTraitReportSyncStatus(
            state: TrexTraitReportSyncState.synced,
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
            TrexTraitReportSyncStatus(
              state: TrexTraitReportSyncState.noAccess,
              lastSyncedAt: _status.lastSyncedAt,
              error: message,
            ),
          );
          return;
        }
        _emit(
          TrexTraitReportSyncStatus(
            state: TrexTraitReportSyncState.offline,
            lastSyncedAt: _status.lastSyncedAt,
            error: error.toString(),
          ),
        );
      },
    );
  }

  TrexTraitReport? _decode(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      final report = TrexTraitReport.fromJson(data);
      final ts = data['updatedAtTs'];
      if (ts is Timestamp) {
        return report.copyWith(updatedAt: ts.toDate().toUtc());
      }
      return report;
    } catch (_) {
      return null;
    }
  }

  void _emit(TrexTraitReportSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  void _emitRemote(List<TrexTraitReport> reports) {
    if (!_remoteController.isClosed) _remoteController.add(reports);
  }
}
