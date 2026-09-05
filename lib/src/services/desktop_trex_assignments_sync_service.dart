import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart';

import '../models/trex_assignments.dart';
import 'desktop_poll_backoff.dart';
import 'pending_push_queue.dart';
import 'spectrum_auth_service.dart';
import 'trex_assignments_sync_service.dart';

class DesktopTRexAssignmentsSyncService implements TRexAssignmentsSyncService {
  DesktopTRexAssignmentsSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    PendingPushQueue? pendingPushQueue,
  }) : _queue = pendingPushQueue ?? PendingPushQueue();

  static const String _collection = 'appConfig';
  static const String _docId = 'trexAssignments';
  static const String _docPath = '$_collection/$_docId';

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final PendingPushQueue _queue;

  final StreamController<TRexAssignments> _controller =
      StreamController<TRexAssignments>.broadcast();
  StreamSubscription<SpectrumAuthSnapshot>? _authSub;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );

  TRexAssignments? _pending;

  @override
  Stream<TRexAssignments> get assignmentsStream => _controller.stream;

  @override
  String? get currentUserUid => _authService.currentUser?.uid;

  @override
  String? get currentUserDisplayName => _authService.currentUser?.displayName;

  @override
  Future<void> initialize() async {
    _authSub = _authService.snapshotStream.listen(_onAuthChanged);
    _onAuthChanged(_authService.snapshot);
  }

  void _onAuthChanged(SpectrumAuthSnapshot snapshot) {
    _pollScheduler.cancel();
    if (snapshot.state == SpectrumAuthState.signedIn) {
      unawaited(_tick());
      _pollScheduler.start(_tick);
    } else {
      _emit(TRexAssignments(updatedAt: _epoch));
    }
  }

  Future<void> _writeChain = Future<void>.value();

  Future<void> _tick() {
    final next = _writeChain.then((_) => _flushPending()).then((_) => _fetch());
    _writeChain = next.catchError((_) {});
    return next;
  }

  Future<void> _flushPending() async {
    final pending = _pending;
    if (pending == null) return;
    try {
      await _write(pending);
      await _queue.clear(_collection, _docId);
      _pending = null;
    } catch (_) {}
  }

  Future<void> _fetch() async {
    try {
      final doc = await _firestore.getDocument(_docPath);
      _emit(TRexAssignments.fromJson(doc?.fields));
      _pollScheduler.onSuccess();
    } catch (error) {
      debugPrint('Desktop T-Rex assignments sync error: $error');
      _pollScheduler.onFailure();
    }
  }

  @override
  Future<void> push(TRexAssignments assignments) {
    final next = _writeChain.then((_) async {
      try {
        await _write(assignments);
        await _queue.clear(_collection, _docId);
        _pending = null;
      } catch (error) {
        _pending = assignments;
        await _queue.mark(_collection, _docId);
        rethrow;
      }
    });
    _writeChain = next.catchError((_) {});
    return next;
  }

  Future<void> _write(TRexAssignments assignments) {
    return _firestore.setDocument(_docPath, <String, dynamic>{
      ...assignments.toJson(),

      'updatedAtTs': assignments.updatedAt.toUtc(),
    });
  }

  @override
  Future<void> dispose() async {
    _pollScheduler.cancel();
    await _authSub?.cancel();
    await _controller.close();
  }

  DateTime get _epoch => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  void _emit(TRexAssignments assignments) {
    if (!_controller.isClosed) _controller.add(assignments);
  }
}
