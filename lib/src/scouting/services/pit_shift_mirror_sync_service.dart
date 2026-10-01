import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/spectrum_auth_service.dart';
import '../models/pit_shift_mirror.dart';

abstract class PitShiftMirrorSyncService {
  Stream<PitShiftMirror?> get mirrorStream;

  Future<void> watch(String eventKey);

  Future<void> dispose();
}

class FirestorePitShiftMirrorSyncService implements PitShiftMirrorSyncService {
  FirestorePitShiftMirrorSyncService({
    required this._authService,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collection = 'pitShifts';

  final SpectrumAuthService _authService;
  final FirebaseFirestore _firestore;

  final StreamController<PitShiftMirror?> _controller =
      StreamController<PitShiftMirror?>.broadcast();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  StreamSubscription<SpectrumAuthSnapshot>? _authSub;
  String _eventKey = '';

  @override
  Stream<PitShiftMirror?> get mirrorStream => _controller.stream;

  @override
  Future<void> watch(String eventKey) async {
    if (eventKey == _eventKey && _sub != null) return;
    _eventKey = eventKey;
    await _sub?.cancel();
    _sub = null;
    if (eventKey.isEmpty) {
      _emit(null);
      return;
    }

    _authSub ??= _authService.snapshotStream.listen((_) => _resubscribe());
    _resubscribe();
  }

  void _resubscribe() {
    _sub?.cancel();
    _sub = null;
    if (_eventKey.isEmpty ||
        _authService.snapshot.state != SpectrumAuthState.signedIn) {
      return;
    }
    _sub = _firestore
        .collection(collection)
        .doc(_eventKey)
        .snapshots()
        .listen(
          (snapshot) {
            final data = snapshot.data();
            _emit(data == null ? null : PitShiftMirror.fromJson(data));
          },
          onError: (Object error) {
            if (!_controller.isClosed) _controller.addError(error);
          },
        );
  }

  void _emit(PitShiftMirror? mirror) {
    if (!_controller.isClosed) _controller.add(mirror);
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _authSub?.cancel();
    if (!_controller.isClosed) await _controller.close();
  }
}
