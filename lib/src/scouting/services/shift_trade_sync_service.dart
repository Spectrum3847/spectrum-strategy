import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/spectrum_auth_service.dart';
import '../models/shift_trade.dart';

abstract class ShiftTradeSyncService {
  Stream<List<ShiftTrade>> get tradesStream;

  String? get currentUserUid;
  String? get currentUserDisplayName;

  Future<void> initialize();

  Future<void> create(ShiftTrade trade);

  Future<void> respond(ShiftTrade trade, ShiftTradeStatus status);

  Future<void> dispose();
}

class FirestoreShiftTradeSyncService implements ShiftTradeSyncService {
  FirestoreShiftTradeSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collection = 'shiftTrades';

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<List<ShiftTrade>> _controller =
      StreamController<List<ShiftTrade>>.broadcast();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  StreamSubscription<SpectrumAuthSnapshot>? _authSub;

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
    if (snapshot.state != SpectrumAuthState.signedIn) {
      _sub?.cancel();
      _sub = null;
      _controller.add(const <ShiftTrade>[]);
      return;
    }
    _sub ??= _firestore.collection(collection).snapshots().listen((snapshot) {
      final trades = snapshot.docs
          .map((doc) => ShiftTrade.fromJson(doc.data()))
          .toList(growable: false);
      if (!_controller.isClosed) _controller.add(trades);
    }, onError: (Object _) => _controller.add(const <ShiftTrade>[]));
  }

  @override
  Future<void> create(ShiftTrade trade) async {
    final stamped = trade.copyWith(status: ShiftTradeStatus.pending);
    await _firestore.doc('$collection/${stamped.id}').set(<String, dynamic>{
      ...stamped.toJson(),

      'updatedAtTs': Timestamp.fromDate(stamped.updatedAt.toUtc()),
    });
  }

  @override
  Future<void> respond(ShiftTrade trade, ShiftTradeStatus status) async {
    final stamped = trade.copyWith(
      status: status,
      updatedAt: DateTime.now().toUtc(),
    );
    await _firestore.doc('$collection/${trade.id}').update(<String, dynamic>{
      'status': stamped.status.wireValue,
      'updatedAt': stamped.updatedAt.toUtc().toIso8601String(),
      'updatedAtTs': Timestamp.fromDate(stamped.updatedAt.toUtc()),
    });
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _authSub?.cancel();
    await _controller.close();
  }
}
