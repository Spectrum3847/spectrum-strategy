import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../state/failed_write_tracker.dart';
import '../models/scout_shift_schedule.dart';
import '../models/shift_trade.dart';
import '../services/shift_trade_sync_service.dart';

class ShiftTradeController extends ChangeNotifier {
  ShiftTradeController({required this.syncService, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final ShiftTradeSyncService syncService;
  final Uuid _uuid;

  final FailedWriteTracker failedWrites = FailedWriteTracker();

  Future<void> _saveQueue = Future<void>.value();
  StreamSubscription<List<ShiftTrade>>? _sub;

  String _eventKey = '';
  List<ShiftTrade> _allTrades = const <ShiftTrade>[];
  bool _loading = true;

  bool get isLoading => _loading;

  List<ShiftTrade> get trades {
    final forEvent = _allTrades
        .where((t) => t.eventKey == _eventKey)
        .toList(growable: false);
    forEvent.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return forEvent;
  }

  List<ShiftTrade> tradesFor(String uid) =>
      trades.where((t) => t.involves(uid)).toList(growable: false);

  List<ShiftTrade> pendingTradesFor(String uid) =>
      tradesFor(uid).where((t) => t.isPending).toList(growable: false);

  List<ShiftTrade> acceptedTradesFor(String uid) =>
      tradesFor(uid)
          .where((t) => t.status == ShiftTradeStatus.accepted)
          .toList(growable: false);

  Future<void> bootstrap() async {
    _sub ??= syncService.tradesStream.listen((trades) {
      _allTrades = trades;
      _loading = false;
      notifyListeners();
    });
    await syncService.initialize();
  }

  Future<void> watchEvent(String eventKey) async {
    _eventKey = eventKey.trim();
    notifyListeners();
  }

  Future<void> requestTrade({
    required String targetUid,
    required String targetDisplayName,
    required ScoutShiftBlock requesterBlock,
    ScoutShiftBlock? targetBlock,
  }) {
    final requesterUid = syncService.currentUserUid ?? '';
    if (requesterUid.isEmpty || _eventKey.isEmpty) return Future<void>.value();
    final trade = ShiftTrade(
      id: _uuid.v4(),
      eventKey: _eventKey,
      requesterUid: requesterUid,
      requesterDisplayName: syncService.currentUserDisplayName ?? '',
      targetUid: targetUid,
      targetDisplayName: targetDisplayName,
      requesterBlock: requesterBlock,
      targetBlock: targetBlock,
    );
    return _enqueue(() => syncService.create(trade));
  }

  Future<void> accept(ShiftTrade trade) =>
      _respond(trade, ShiftTradeStatus.accepted);

  Future<void> decline(ShiftTrade trade) =>
      _respond(trade, ShiftTradeStatus.declined);

  Future<void> cancel(ShiftTrade trade) =>
      _respond(trade, ShiftTradeStatus.cancelled);

  Future<void> _respond(ShiftTrade trade, ShiftTradeStatus status) {
    return _enqueue(() => syncService.respond(trade, status));
  }

  Future<void> _enqueue(Future<void> Function() op) {
    _saveQueue = _saveQueue
        .then((_) => op())
        .then((_) {
          if (failedWrites.recordSuccess()) notifyListeners();
        })
        .catchError((Object error) {
          debugPrint('Shift trade save failed: $error');
          failedWrites.recordFailure();
          notifyListeners();
        });
    return _saveQueue;
  }

  ScoutShiftSchedule effectiveSchedule(ScoutShiftSchedule schedule) {
    final accepted = trades.where((t) => t.status == ShiftTradeStatus.accepted);
    if (accepted.isEmpty) return schedule;

    final rotations = [...schedule.rotations];
    for (final trade in accepted) {
      _swap(
        rotations,
        trade.requesterUid,
        trade.targetUid,
        trade.requesterBlock,
      );
      final targetBlock = trade.targetBlock;
      if (targetBlock != null) {
        _swap(rotations, trade.targetUid, trade.requesterUid, targetBlock);
      }
    }
    return ScoutShiftSchedule(
      eventKey: schedule.eventKey,
      matchCount: schedule.matchCount,
      roster: schedule.roster,
      rotations: List<ScouterShiftRotation>.unmodifiable(rotations),
      cellOverrides: schedule.cellOverrides,
      authorUid: schedule.authorUid,
      authorDisplayName: schedule.authorDisplayName,
      updatedAt: schedule.updatedAt,
    );
  }

  void _swap(
    List<ScouterShiftRotation> rotations,
    String fromUid,
    String toUid,
    ScoutShiftBlock block,
  ) {
    if (fromUid.isEmpty || toUid.isEmpty) return;

    final fromIndex = rotations.indexWhere((r) => r.uid == fromUid);
    final toIndex = rotations.indexWhere((r) => r.uid == toUid);
    if (fromIndex == -1 || toIndex == -1) return;
    final from = rotations[fromIndex];
    rotations[fromIndex] = ScouterShiftRotation(
      uid: from.uid,
      name: from.name,
      shifts: from.shifts.where((s) => !_sameBlock(s, block)).toList(),
    );
    final to = rotations[toIndex];
    rotations[toIndex] = ScouterShiftRotation(
      uid: to.uid,
      name: to.name,
      shifts: [...to.shifts, block],
    );
  }

  bool _sameBlock(ScoutShiftBlock a, ScoutShiftBlock b) =>
      a.startMatch == b.startMatch && a.endMatch == b.endMatch;

  @override
  void dispose() {
    _sub?.cancel();
    syncService.dispose();
    super.dispose();
  }
}
