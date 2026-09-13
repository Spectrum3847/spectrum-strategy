import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../../services/desktop_poll_backoff.dart';
import '../../services/pending_push_queue.dart';
import '../../services/spectrum_auth_service.dart';
import '../models/scout_shift_schedule.dart';
import 'scout_shift_sync_service.dart';

class DesktopScoutShiftSyncService implements ScoutShiftSyncService {
  DesktopScoutShiftSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    PendingPushQueue? pendingPushQueue,
  }) : _queue = pendingPushQueue ?? PendingPushQueue();

  static const String _collection = 'scoutShifts';

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final PendingPushQueue _queue;

  final StreamController<ScoutShiftSchedule?> _controller =
      StreamController<ScoutShiftSchedule?>.broadcast();
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );
  String _eventKey = '';
  String? _lastSeenJson;

  ScoutShiftSchedule? _pendingSchedule;

  @override
  Stream<ScoutShiftSchedule?> get scheduleStream => _controller.stream;

  @override
  String? get currentUserUid => _authService.currentUser?.uid;

  @override
  String? get currentUserDisplayName => _authService.currentUser?.displayName;

  @override
  Future<void> watch(String eventKey) async {
    if (eventKey == _eventKey) {
      _startPollingIfSignedIn();
      return;
    }
    _eventKey = eventKey;
    _lastSeenJson = null;
    if (eventKey.isEmpty) {
      _controller.add(null);
      return;
    }
    _authSubscription ??= _authService.snapshotStream.listen(
      (_) => _startPollingIfSignedIn(),
    );
    _startPollingIfSignedIn();
  }

  void _startPollingIfSignedIn() {
    _pollScheduler.cancel();
    if (_authService.snapshot.state != SpectrumAuthState.signedIn ||
        _eventKey.isEmpty) {
      return;
    }
    unawaited(_tick());
    _pollScheduler.start(_tick);
  }

  Future<void> _writeChain = Future<void>.value();

  Future<void> _tick() {
    final next = _writeChain.then((_) => _flushPending()).then((_) => _fetch());
    _writeChain = next.catchError((_) {});
    return next;
  }

  Future<void> _flushPending() async {
    final schedule = _pendingSchedule;
    if (schedule == null) return;
    try {
      await _writeSchedule(schedule);
      await _queue.clear(_collection, schedule.eventKey);
      _pendingSchedule = null;
    } catch (_) {}
  }

  Future<void> _fetch() async {
    final eventKey = _eventKey;
    if (eventKey.isEmpty) return;
    try {
      final doc = await _firestore.getDocument('$_collection/$eventKey');
      _pollScheduler.onSuccess();
      if (_eventKey != eventKey) return;
      if (doc == null) {
        if (_lastSeenJson != null) {
          _lastSeenJson = null;
          _emit(null);
        }
        return;
      }
      final schedule = _decode(doc);
      final asJson = schedule.toJson().toString();
      if (asJson == _lastSeenJson) return;
      _lastSeenJson = asJson;
      _emit(schedule);
    } catch (_) {
      _pollScheduler.onFailure();
    }
  }

  ScoutShiftSchedule _decode(fc.Document doc) {
    final data = doc.fields;
    final schedule = ScoutShiftSchedule.fromJson(data);
    final ts = data['updatedAtTs'];
    if (ts is DateTime) {
      return ScoutShiftSchedule(
        eventKey: schedule.eventKey,
        matchCount: schedule.matchCount,
        roster: schedule.roster,
        rotations: schedule.rotations,
        cellOverrides: schedule.cellOverrides,
        authorUid: schedule.authorUid,
        authorDisplayName: schedule.authorDisplayName,
        updatedAt: ts.toUtc(),
      );
    }
    return schedule;
  }

  @override
  Future<void> push(ScoutShiftSchedule schedule) {
    final next = _writeChain.then((_) async {
      try {
        await _writeSchedule(schedule);
        await _queue.clear(_collection, schedule.eventKey);
        _pendingSchedule = null;
      } catch (error) {
        _pendingSchedule = schedule;
        await _queue.mark(_collection, schedule.eventKey);
        rethrow;
      }
    });
    _writeChain = next.catchError((_) {});
    return next.then((_) {
      unawaited(_fetch());
    });
  }

  Future<void> _writeSchedule(ScoutShiftSchedule schedule) {
    final user = _authService.currentUser;
    final stamped = ScoutShiftSchedule(
      eventKey: schedule.eventKey,
      matchCount: schedule.matchCount,
      roster: schedule.roster,
      rotations: schedule.rotations,
      cellOverrides: schedule.cellOverrides,
      authorUid: schedule.authorUid.isEmpty
          ? (user?.uid ?? '')
          : schedule.authorUid,
      authorDisplayName: schedule.authorDisplayName.isEmpty
          ? (user?.displayName ?? '')
          : schedule.authorDisplayName,
      updatedAt: DateTime.now().toUtc(),
    );
    return _firestore.setDocument('$_collection/${stamped.eventKey}', {
      ...stamped.toJson(),
      'updatedAtTs': stamped.updatedAt.toUtc(),
    });
  }

  void _emit(ScoutShiftSchedule? schedule) {
    if (!_controller.isClosed) {
      _controller.add(schedule);
    }
  }

  @override
  Future<void> dispose() async {
    _pollScheduler.cancel();
    await _authSubscription?.cancel();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
