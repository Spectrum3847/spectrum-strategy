import 'dart:async';

import 'package:spectrumstrategy/src/scouting/models/shift_trade.dart';
import 'package:spectrumstrategy/src/scouting/services/shift_trade_sync_service.dart';

class FakeShiftTradeSyncService implements ShiftTradeSyncService {
  FakeShiftTradeSyncService({this.uid = 'uid-1', this.displayName = 'Scouter'});

  final String uid;
  final String displayName;

  final _trades = StreamController<List<ShiftTrade>>.broadcast();
  final Map<String, ShiftTrade> stored = <String, ShiftTrade>{};

  final List<String> calls = <String>[];

  Object? failNext;

  bool disposed = false;

  @override
  Stream<List<ShiftTrade>> get tradesStream => _trades.stream;

  @override
  String? get currentUserUid => uid;

  @override
  String? get currentUserDisplayName => displayName;

  @override
  Future<void> initialize() async {
    _emit();
  }

  @override
  Future<void> create(ShiftTrade trade) async {
    calls.add('create:${trade.id}');
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    stored[trade.id] = trade.copyWith(status: ShiftTradeStatus.pending);
    _emit();
  }

  @override
  Future<void> respond(ShiftTrade trade, ShiftTradeStatus status) async {
    calls.add('respond:${trade.id}:${status.wireValue}');
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    final current = stored[trade.id] ?? trade;
    stored[trade.id] = current.copyWith(status: status);
    _emit();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _trades.close();
  }

  void _emit() {
    if (!_trades.isClosed) _trades.add(stored.values.toList());
  }
}
