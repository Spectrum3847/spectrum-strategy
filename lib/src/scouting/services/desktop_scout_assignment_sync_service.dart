import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../../services/desktop_poll_backoff.dart';
import '../../services/in_flight_local_writes.dart';
import '../../services/pending_push_queue.dart';
import '../../services/spectrum_auth_service.dart';
import '../models/scout_assignment.dart';
import 'scout_assignment_sync_service.dart';

class DesktopScoutAssignmentSyncService implements ScoutAssignmentSyncService {
  DesktopScoutAssignmentSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    PendingPushQueue? pendingPushQueue,
    DateTime Function()? clock,
  }) : _queue = pendingPushQueue ?? PendingPushQueue(),
       _clock = clock ?? DateTime.now;

  static const Duration _cursorOverlap = Duration(minutes: 2);

  static const int _fullSyncEveryPolls = 10;

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final PendingPushQueue _queue;
  final DateTime Function() _clock;

  final Map<String, ScoutAssignment> _cache = <String, ScoutAssignment>{};

  final InFlightLocalWrites<ScoutAssignment> _inFlightWrites =
      InFlightLocalWrites<ScoutAssignment>();

  DateTime? _cursor;

  int _pollsSinceFullSync = 0;

  final Map<String, ScoutAssignment> _pendingUpserts =
      <String, ScoutAssignment>{};

  static const String _deletedCollection = 'scoutAssignments_deleted';

  final StreamController<List<ScoutAssignment>> _controller =
      StreamController<List<ScoutAssignment>>.broadcast();

  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;

  @override
  Stream<List<ScoutAssignment>> watchAll() {
    _startListening();
    return _controller.stream;
  }

  bool _started = false;

  void _startListening() {
    if (_started) return;
    _started = true;
    _authSubscription = _authService.snapshotStream.listen((snapshot) {
      if (snapshot.state == SpectrumAuthState.signedIn) {
        _startPolling();
      } else {
        _stopPolling();

        _cache.clear();
        _cursor = null;
        _emit(const <ScoutAssignment>[]);
      }
    });

    if (_authService.snapshot.state == SpectrumAuthState.signedIn) {
      _startPolling();
    }
  }

  void _startPolling() {
    unawaited(_tick());
    _pollScheduler.start(_tick);
  }

  void _stopPolling() {
    _pollScheduler.cancel();
  }

  Future<void> _tickChain = Future<void>.value();

  Future<void> _tick() {
    final next = _tickChain.then((_) async {
      await _flushPending();
      await _pollOnce();
    });
    _tickChain = next.catchError((_) {});
    return next;
  }

  Future<void> _flushPending() async {
    for (final id in await _queue.pending(_deletedCollection)) {
      try {
        await delete(id);
      } catch (_) {}
    }

    final ids = await _queue.pending('scoutAssignments');
    if (ids.isEmpty) return;
    for (final id in List<String>.of(ids)) {
      try {
        final assignment = _pendingUpserts[id];
        if (assignment == null) {
          await _queue.clear('scoutAssignments', id);
          continue;
        }
        await upsert(assignment);
      } catch (_) {}
    }
  }

  Future<void> _pollOnce() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;

    final isFullSync =
        _cursor == null || _pollsSinceFullSync >= _fullSyncEveryPolls - 1;

    _inFlightWrites.beginFetch();
    try {
      final docs = isFullSync
          ? await _firestore.runQuery('scoutAssignments')
          : await _firestore.runQuery(
              'scoutAssignments',
              filters: [
                fc.FieldFilter(
                  'updatedAtTs',
                  'GREATER_THAN_OR_EQUAL',
                  _cursor!.subtract(_cursorOverlap),
                ),
              ],
            );

      if (_authService.currentUser?.uid != uid) {
        _inFlightWrites.abandonFetch();
        return;
      }
      if (isFullSync) {
        _pollsSinceFullSync = 0;
      } else {
        _pollsSinceFullSync++;
      }

      final next = isFullSync
          ? <String, ScoutAssignment>{}
          : Map<String, ScoutAssignment>.of(_cache);
      for (final doc in docs) {
        final item = _decode(doc);
        if (item == null) continue;
        next[item.id] = item;
        final serverTs = doc.fields['updatedAtTs'];
        if (serverTs is DateTime) {
          final ts = serverTs.toUtc();
          if (_cursor == null || ts.isAfter(_cursor!)) {
            _cursor = ts;
          }
        }
      }
      _cursor ??= _clock().toUtc();
      _cache
        ..clear()
        ..addAll(_inFlightWrites.resolve(next));
      _emit(_cache.values.toList(growable: false));
      _pollScheduler.onSuccess();
    } catch (_) {
      _inFlightWrites.abandonFetch();

      _pollScheduler.onFailure();
    }
  }

  void _emit(List<ScoutAssignment> items) {
    if (!_controller.isClosed) {
      _controller.add(items);
    }
  }

  ScoutAssignment? _decode(fc.Document doc) {
    try {
      final data = doc.fields;
      final matchKey = data['matchKey'] as String? ?? '';
      final station = data['station'] as String? ?? '';
      final assignment = ScoutAssignment(
        id: data['id'] as String? ?? ScoutAssignment.idFor(matchKey, station),
        matchKey: matchKey,
        matchNumber: (data['matchNumber'] as num?)?.toInt() ?? 0,
        station: station,
        scouterUid: data['scouterUid'] as String? ?? '',
        scouterName: data['scouterName'] as String? ?? '',
        authorUid: data['authorUid'] as String? ?? '',
        authorDisplayName: data['authorDisplayName'] as String? ?? '',
        updatedAt:
            DateTime.tryParse(data['updatedAt'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
      );

      final ts = data['updatedAtTs'];
      if (ts is DateTime) {
        return assignment.copyWith(updatedAt: ts.toUtc());
      }
      return assignment;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> upsert(ScoutAssignment assignment) async {
    final user = _authService.currentUser;
    if (user == null) return;
    final stamped = assignment.copyWith(
      authorUid: assignment.authorUid.isEmpty ? user.uid : assignment.authorUid,
      authorDisplayName: assignment.authorDisplayName.isEmpty
          ? user.displayName
          : assignment.authorDisplayName,
      updatedAt: DateTime.now().toUtc(),
    );

    await _queue.clear(_deletedCollection, stamped.id);
    try {
      await _firestore.setDocument('scoutAssignments/${stamped.id}', {
        ...stamped.toJson(),
        'updatedAtTs': stamped.updatedAt.toUtc(),
      });
      await _queue.clear('scoutAssignments', stamped.id);
      _pendingUpserts.remove(stamped.id);

      _cache[stamped.id] = stamped;

      _inFlightWrites.recordPush(stamped.id, stamped);
      final ts = stamped.updatedAt.toUtc();
      if (_cursor == null || ts.isAfter(_cursor!)) {
        _cursor = ts;
      }
      _emit(_cache.values.toList(growable: false));
    } catch (error) {
      _pendingUpserts[stamped.id] = stamped;
      await _queue.mark('scoutAssignments', stamped.id);
      rethrow;
    }
  }

  @override
  Future<void> delete(String id) async {
    if (_authService.currentUser == null) return;
    try {
      await _firestore.deleteDocument('scoutAssignments/$id');
      await _queue.clear(_deletedCollection, id);

      await _queue.clear('scoutAssignments', id);
      _pendingUpserts.remove(id);

      _cache.remove(id);

      _inFlightWrites.recordDelete(id);
      _emit(_cache.values.toList(growable: false));
    } catch (error) {
      _pendingUpserts.remove(id);
      await _queue.clear('scoutAssignments', id);
      await _queue.mark(_deletedCollection, id);
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    _stopPolling();
    await _authSubscription?.cancel();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
