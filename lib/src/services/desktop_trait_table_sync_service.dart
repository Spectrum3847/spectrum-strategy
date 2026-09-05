import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../models/trait_config.dart';
import '../models/trait_table.dart';
import 'desktop_poll_backoff.dart';
import 'pending_push_queue.dart';
import 'spectrum_auth_service.dart';
import 'trait_table_sync_service.dart';

class DesktopTraitTableSyncService implements TraitTableSyncService {
  DesktopTraitTableSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    PendingPushQueue? pendingPushQueue,
  }) : _queue = pendingPushQueue ?? PendingPushQueue();

  static const String _collection = 'traitTables';

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final PendingPushQueue _queue;

  final Map<String, TraitTable> _pendingPushes = <String, TraitTable>{};

  final StreamController<TraitTable?> _tableController =
      StreamController<TraitTable?>.broadcast();
  final StreamController<TraitConfig> _configController =
      StreamController<TraitConfig>.broadcast();

  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  bool _started = false;

  String _eventKey = '';
  String _matchId = '';

  @override
  Stream<TraitTable?> get tableStream => _tableController.stream;

  @override
  Stream<TraitConfig> get configStream => _configController.stream;

  @override
  String? get currentUserUid => _authService.currentUser?.uid;

  @override
  String? get currentUserDisplayName => _authService.currentUser?.displayName;

  @override
  Future<void> watch({
    required String eventKey,
    required String matchId,
  }) async {
    final changed = eventKey != _eventKey || matchId != _matchId;
    _eventKey = eventKey;
    _matchId = matchId;
    _startListening();

    if (eventKey.isEmpty || matchId.isEmpty) {
      _emitTable(null);
      return;
    }
    if (_authService.currentUser == null) {
      _emitTable(null);
      return;
    }
    if (changed) {
      unawaited(_tick());
    }
  }

  void _startListening() {
    if (_started) return;
    _started = true;
    _authSubscription = _authService.snapshotStream.listen((snapshot) {
      if (snapshot.state == SpectrumAuthState.signedIn) {
        _startPolling();
      } else {
        _stopPolling();
        _emitTable(null);
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
    final ids = await _queue.pending(_collection);
    if (ids.isEmpty) return;
    for (final id in List<String>.of(ids)) {
      final table = _pendingPushes[id];
      if (table == null) {
        await _queue.clear(_collection, id);
        continue;
      }
      try {
        await push(table);
      } catch (_) {}
    }
  }

  Future<void> _pollOnce() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await _firestore.getDocument(
        FirestoreTraitTableSyncService.configPath,
      );

      if (_authService.currentUser?.uid != uid) return;

      _emitConfig(TraitConfig.fromJson(doc?.fields));
      _pollScheduler.onSuccess();
    } catch (_) {
      _pollScheduler.onFailure();
    }

    final eventKey = _eventKey;
    final matchId = _matchId;
    if (eventKey.isEmpty || matchId.isEmpty) return;
    try {
      final doc = await _firestore.getDocument(
        '$_collection/${TraitTable.idFor(eventKey, matchId)}',
      );
      if (_authService.currentUser?.uid != uid) return;

      if (eventKey != _eventKey || matchId != _matchId) return;
      _emitTable(doc == null ? null : _decode(doc));
      _pollScheduler.onSuccess();
    } catch (_) {
      _pollScheduler.onFailure();
    }
  }

  TraitTable? _decode(fc.Document doc) {
    try {
      final table = TraitTable.fromJson(doc.fields);

      final ts = doc.fields['updatedAtTs'];
      if (ts is DateTime) {
        return table.copyWith(updatedAt: ts.toUtc());
      }
      return table;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> push(TraitTable table) async {
    if (_authService.currentUser == null) return;
    try {
      await _firestore.setDocument('$_collection/${table.id}', {
        ...table.toJson(),

        'updatedAtTs': table.updatedAt.toUtc(),
      });
      await _queue.clear(_collection, table.id);
      _pendingPushes.remove(table.id);
    } catch (error) {
      _pendingPushes[table.id] = table;
      await _queue.mark(_collection, table.id);
      rethrow;
    }
  }

  void _emitTable(TraitTable? table) {
    if (!_tableController.isClosed) {
      _tableController.add(table);
    }
  }

  void _emitConfig(TraitConfig config) {
    if (!_configController.isClosed) {
      _configController.add(config);
    }
  }

  @override
  Future<void> dispose() async {
    _stopPolling();
    await _authSubscription?.cancel();
    if (!_tableController.isClosed) {
      await _tableController.close();
    }
    if (!_configController.isClosed) {
      await _configController.close();
    }
  }
}
