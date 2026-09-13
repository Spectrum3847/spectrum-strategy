import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;
import 'package:flutter/foundation.dart';

import 'desktop_poll_backoff.dart';
import 'pending_push_queue.dart';
import 'spectrum_auth_service.dart';
import 'firestore_active_event_service.dart';

class DesktopActiveEventSyncService implements ActiveEventSyncService {
  DesktopActiveEventSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    PendingPushQueue? pendingPushQueue,
  }) : _queue = pendingPushQueue ?? PendingPushQueue();

  static const String _collection = 'appConfig';
  static const String _docId = 'activeEvent';
  static const String _docPath = '$_collection/$_docId';

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final PendingPushQueue _queue;

  final StreamController<String?> _eventKeyController =
      StreamController<String?>.broadcast();
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );
  String? _lastEventKey;

  String? _pendingEventKey;

  @override
  Stream<String?> get eventKeyStream => _eventKeyController.stream;

  @override
  Future<void> initialize() async {
    _authSubscription = _authService.snapshotStream.listen(_onAuthChanged);
    _onAuthChanged(_authService.snapshot);
  }

  void _onAuthChanged(SpectrumAuthSnapshot snapshot) {
    _pollScheduler.cancel();
    if (snapshot.state == SpectrumAuthState.signedIn) {
      unawaited(_tick());
      _pollScheduler.start(_tick);
    }
  }

  Future<void> _writeChain = Future<void>.value();

  Future<void> _tick() {
    final next = _writeChain.then((_) => _flushPending()).then((_) => _fetch());
    _writeChain = next.catchError((_) {});
    return next;
  }

  Future<void> _flushPending() async {
    final eventKey = _pendingEventKey;
    if (eventKey == null) return;
    try {
      await _writeEventKey(eventKey);
      await _queue.clear(_collection, _docId);
      _pendingEventKey = null;
    } catch (_) {}
  }

  Future<void> _fetch() async {
    try {
      final doc = await _firestore.getDocument(_docPath);
      final raw = doc?.fields['eventKey'];
      _pollScheduler.onSuccess();
      if (raw is! String) {
        if (_lastEventKey != null || doc == null) {
          _lastEventKey = null;
          _emit(null);
        }
        return;
      }
      if (raw == _lastEventKey) {
        return;
      }
      _lastEventKey = raw;
      _emit(raw);
    } catch (error) {
      debugPrint('Desktop active event sync error: $error');
      _pollScheduler.onFailure();
    }
  }

  @override
  Future<void> push(String eventKey) {
    final next = _writeChain.then((_) async {
      try {
        await _writeEventKey(eventKey);
        await _queue.clear(_collection, _docId);
        _pendingEventKey = null;
      } catch (error) {
        _pendingEventKey = eventKey;
        await _queue.mark(_collection, _docId);
        rethrow;
      }
    });
    _writeChain = next.catchError((_) {});
    return next;
  }

  Future<void> _writeEventKey(String eventKey) {
    return _firestore.setDocument(_docPath, <String, dynamic>{
      'eventKey': eventKey,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> dispose() async {
    _pollScheduler.cancel();
    await _authSubscription?.cancel();
    await _eventKeyController.close();
  }

  void _emit(String? eventKey) {
    if (!_eventKeyController.isClosed) {
      _eventKeyController.add(eventKey);
    }
  }
}
