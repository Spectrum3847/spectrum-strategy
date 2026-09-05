import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../../services/desktop_poll_backoff.dart';
import '../../services/in_flight_local_writes.dart';
import '../../services/spectrum_auth_service.dart';
import '../models/shift_trade.dart';
import 'shift_trade_sync_service.dart';

class DesktopShiftTradeSyncService implements ShiftTradeSyncService {
  DesktopShiftTradeSyncService({
    required this._authService,
    required this._firestore,
    this._pollInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const String _collection = 'shiftTrades';

  static const Duration _cursorOverlap = Duration(minutes: 2);

  static const int _fullSyncEveryPolls = 10;

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final Duration _pollInterval;
  final DateTime Function() _clock;

  final StreamController<List<ShiftTrade>> _controller =
      StreamController<List<ShiftTrade>>.broadcast();
  StreamSubscription<SpectrumAuthSnapshot>? _authSub;
  late final DesktopPollScheduler _pollScheduler = DesktopPollScheduler(
    _pollInterval,
  );

  final Map<String, ShiftTrade> _cache = <String, ShiftTrade>{};

  final InFlightLocalWrites<ShiftTrade> _inFlightWrites =
      InFlightLocalWrites<ShiftTrade>();

  DateTime? _cursor;

  int _pollsSinceFullSync = 0;

  String? _lastSeen;

  @override
  Stream<List<ShiftTrade>> get tradesStream => _controller.stream;

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
    if (snapshot.state != SpectrumAuthState.signedIn) {
      _cache.clear();
      _cursor = null;
      _pollsSinceFullSync = 0;
      _lastSeen = null;
      if (!_controller.isClosed) _controller.add(const <ShiftTrade>[]);
      return;
    }
    unawaited(_fetch());
    _pollScheduler.start(_fetch);
  }

  Future<void> _syncChain = Future<void>.value();

  Future<void> _fetch() {
    final next = _syncChain.then((_) => _fetchOnce());
    _syncChain = next.catchError((_) {});
    return next;
  }

  Future<void> _fetchOnce() async {
    final isFullSync =
        _cursor == null || _pollsSinceFullSync >= _fullSyncEveryPolls - 1;
    _inFlightWrites.beginFetch();
    try {
      final docs = isFullSync
          ? await _firestore.listDocuments(_collection)
          : await _firestore.runQuery(
              _collection,
              filters: [
                fc.FieldFilter(
                  'updatedAtTs',
                  'GREATER_THAN_OR_EQUAL',
                  _cursor!.subtract(_cursorOverlap),
                ),
              ],
            );
      _pollScheduler.onSuccess();
      if (isFullSync) {
        _pollsSinceFullSync = 0;
      } else {
        _pollsSinceFullSync++;
      }

      final next = isFullSync
          ? <String, ShiftTrade>{}
          : Map<String, ShiftTrade>.of(_cache);
      for (final doc in docs) {
        final trade = _decode(doc);

        if (trade == null) continue;
        next[trade.id] = trade;
        final ts = doc.fields['updatedAtTs'];
        if (ts is DateTime) {
          final utc = ts.toUtc();
          if (_cursor == null || utc.isAfter(_cursor!)) _cursor = utc;
        }
      }
      _cursor ??= _clock().toUtc();
      _cache
        ..clear()
        ..addAll(_inFlightWrites.resolve(next));

      final trades = _cache.values.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      final asString = trades.map((t) => t.toJson()).toList().toString();
      if (asString == _lastSeen) return;
      _lastSeen = asString;
      if (!_controller.isClosed) _controller.add(trades);
    } catch (_) {
      _inFlightWrites.abandonFetch();
      _pollScheduler.onFailure();
    }
  }

  ShiftTrade? _decode(fc.Document doc) {
    try {
      final trade = ShiftTrade.fromJson(doc.fields);

      final ts = doc.fields['updatedAtTs'];
      if (ts is DateTime) return trade.copyWith(updatedAt: ts.toUtc());
      return trade;
    } catch (_) {
      return null;
    }
  }

  void _applyLocalWrite(ShiftTrade trade) {
    _cache[trade.id] = trade;
    _inFlightWrites.recordPush(trade.id, trade);
    final ts = trade.updatedAt.toUtc();
    if (_cursor == null || ts.isAfter(_cursor!)) _cursor = ts;
  }

  @override
  Future<void> create(ShiftTrade trade) async {
    final stamped = trade.copyWith(status: ShiftTradeStatus.pending);
    await _firestore.setDocument('$_collection/${stamped.id}', {
      ...stamped.toJson(),
      'updatedAtTs': stamped.updatedAt.toUtc(),
    });
    _applyLocalWrite(stamped);
    unawaited(_fetch());
  }

  @override
  Future<void> respond(ShiftTrade trade, ShiftTradeStatus status) async {
    final stamped = trade.copyWith(
      status: status,
      updatedAt: DateTime.now().toUtc(),
    );
    await _firestore.commitUpdate(
      '$_collection/${trade.id}',
      fields: <String, Object?>{
        'status': stamped.status.wireValue,
        'updatedAt': stamped.updatedAt.toUtc().toIso8601String(),
        'updatedAtTs': stamped.updatedAt.toUtc(),
      },
      mustExist: true,
    );
    _applyLocalWrite(stamped);
    unawaited(_fetch());
  }

  @override
  Future<void> dispose() async {
    _pollScheduler.cancel();
    await _authSub?.cancel();
    if (!_controller.isClosed) await _controller.close();
  }
}
