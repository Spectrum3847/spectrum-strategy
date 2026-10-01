import 'dart:async';

import 'package:firestore_client/firestore_client.dart' as fc;

import '../../services/desktop_poll_backoff.dart';
import '../../services/spectrum_auth_service.dart';
import '../models/pit_shift_mirror.dart';
import 'pit_shift_mirror_sync_service.dart';

class DesktopPitShiftMirrorSyncService implements PitShiftMirrorSyncService {
  DesktopPitShiftMirrorSyncService({
    required this._authService,
    required this._firestore,
    Duration pollInterval = const Duration(seconds: 30),
  }) : _pollScheduler = DesktopPollScheduler(pollInterval);

  static const String _collection = 'pitShifts';

  final SpectrumAuthService _authService;
  final fc.Firestore _firestore;
  final DesktopPollScheduler _pollScheduler;

  final StreamController<PitShiftMirror?> _controller =
      StreamController<PitShiftMirror?>.broadcast();
  StreamSubscription<SpectrumAuthSnapshot>? _authSubscription;
  String _eventKey = '';
  String? _lastSeenJson;

  @override
  Stream<PitShiftMirror?> get mirrorStream => _controller.stream;

  @override
  Future<void> watch(String eventKey) async {
    if (eventKey == _eventKey) {
      _startPollingIfSignedIn();
      return;
    }
    _eventKey = eventKey;
    _lastSeenJson = null;
    if (eventKey.isEmpty) {
      _emit(null);
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
    unawaited(_fetch());
    _pollScheduler.start(_fetch);
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
      final mirror = PitShiftMirror.fromJson(doc.fields);
      final asJson = mirror.toJson().toString();
      if (asJson == _lastSeenJson) return;
      _lastSeenJson = asJson;
      _emit(mirror);
    } catch (_) {
      _pollScheduler.onFailure();
    }
  }

  void _emit(PitShiftMirror? mirror) {
    if (!_controller.isClosed) _controller.add(mirror);
  }

  @override
  Future<void> dispose() async {
    _pollScheduler.cancel();
    await _authSubscription?.cancel();
    if (!_controller.isClosed) await _controller.close();
  }
}
