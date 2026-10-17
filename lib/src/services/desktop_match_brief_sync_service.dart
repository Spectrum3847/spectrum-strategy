import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/match_brief.dart';
import 'desktop_poll_backoff.dart';
import 'match_brief_storage.dart';
import 'match_brief_sync_service.dart';
import 'pending_push_queue.dart';
import 'spectrum_auth_service.dart';

class DesktopMatchBriefSyncService implements MatchBriefSyncService {
  DesktopMatchBriefSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
    this._storage,
    PendingPushQueue? pendingPushQueue,
  }) : _clock = clock ?? DateTime.now,
       _queue = pendingPushQueue ?? PendingPushQueue();

  static const String _collection = 'matchBriefs';

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final DateTime Function() _clock;
  final MatchBriefStorage? _storage;
  final PendingPushQueue _queue;

  final StreamController<MatchBriefSyncStatus> _statusController =
      StreamController<MatchBriefSyncStatus>.broadcast();
  final StreamController<List<MatchBrief>> _remoteController =
      StreamController<List<MatchBrief>>.broadcast();

  MatchBriefSyncStatus _status = const MatchBriefSyncStatus(
    state: MatchBriefSyncState.signedOut,
  );
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );

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
      _emit(const MatchBriefSyncStatus(state: MatchBriefSyncState.syncing));
      unawaited(_syncNow());
      _pollScheduler.start(_syncNow);
    } else {
      _pollScheduler.cancel();
      _emit(const MatchBriefSyncStatus(state: MatchBriefSyncState.signedOut));
    }
  }

  @override
  Future<void> push(MatchBrief brief) async {
    if (_authService.currentUser == null) return;
    try {
      await _firestore.setDocument('$_collection/${brief.id}', {
        ...brief.toJson(),
        'updatedAtTs': brief.updatedAt.toUtc(),
      });
      await _queue.clear(_collection, brief.id);
      _emitSynced();
    } catch (error) {
      await _queue.mark(_collection, brief.id);
      _emitFailure(error, isWrite: true);
    }
  }

  Future<void> _syncChain = Future<void>.value();

  Future<void> _syncNow() {
    final next = _syncChain
        .then((_) => _flushPending())
        .then((_) => _syncOnce());
    _syncChain = next.catchError((_) {});
    return next;
  }

  Future<void> _flushPending() async {
    final storage = _storage;
    if (storage == null) return;
    final ids = await _queue.pending(_collection);
    if (ids.isEmpty) return;
    final all = await storage.loadAll();
    for (final id in ids) {
      final brief = all.where((b) => b.id == id).firstOrNull;
      if (brief == null) {
        await _queue.clear(_collection, id);
        continue;
      }
      await push(brief);
    }
  }

  Future<void> _syncOnce() async {
    if (_authService.currentUser == null) {
      _emit(const MatchBriefSyncStatus(state: MatchBriefSyncState.signedOut));
      return;
    }
    try {
      final docs = await _firestore.listDocuments(_collection);
      final briefs = docs.map(_decode).whereType<MatchBrief>().toList();
      if (!_remoteController.isClosed) _remoteController.add(briefs);
      _emitSynced();
    } catch (error) {
      _emitFailure(error);
    }
  }

  @override
  Future<void> dispose() async {
    _pollScheduler.cancel();
    await _authSubscription?.cancel();
    await _statusController.close();
    await _remoteController.close();
  }

  MatchBrief? _decode(fc.Document doc) {
    try {
      final brief = MatchBrief.fromJson(doc.fields);
      final ts = doc.fields['updatedAtTs'];
      return ts is DateTime ? brief.copyWith(updatedAt: ts.toUtc()) : brief;
    } catch (_) {
      return null;
    }
  }

  void _emitSynced() {
    _pollScheduler.onSuccess();
    _emit(
      MatchBriefSyncStatus(
        state: MatchBriefSyncState.synced,
        lastSyncedAt: _clock(),
      ),
    );
  }

  void _emitFailure(Object error, {bool isWrite = false}) {
    _pollScheduler.onFailure();
    final api = error is fc.FirestoreApiException ? error : null;
    final denied =
        api != null &&
        (api.statusCode == 403 || api.status == 'PERMISSION_DENIED');
    final unauthorized = api != null && api.statusCode == 401;
    final state = switch ((isWrite, denied, unauthorized)) {
      (true, true, _) => MatchBriefSyncState.rejected,
      (false, true, _) || (false, _, true) => MatchBriefSyncState.noAccess,
      _ => MatchBriefSyncState.offline,
    };
    _emit(
      MatchBriefSyncStatus(
        state: state,
        lastSyncedAt: _status.lastSyncedAt,
        error: api?.message ?? error.toString(),
      ),
    );
  }

  void _emit(MatchBriefSyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }
}
