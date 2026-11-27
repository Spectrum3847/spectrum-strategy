import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/pit_shift_mirror.dart';
import '../services/pit_shift_mirror_sync_service.dart';

class PitShiftMirrorController extends ChangeNotifier {
  PitShiftMirrorController({required this.syncService});

  final PitShiftMirrorSyncService syncService;

  StreamSubscription<PitShiftMirror?>? _sub;
  String _eventKey = '';
  PitShiftMirror? _mirror;

  String get eventKey => _eventKey;

  PitShiftMirror? get mirror => _mirror;

  Future<void> watchEvent(String eventKey) async {
    final trimmed = eventKey.trim();
    if (trimmed == _eventKey && _sub != null) return;
    _eventKey = trimmed;
    _mirror = null;
    notifyListeners();
    _sub ??= syncService.mirrorStream.listen(
      (mirror) {
        _mirror = mirror;
        notifyListeners();
      },
      onError: (Object error) {
        debugPrint('Pit shift mirror stream error: $error');
      },
    );
    await syncService.watch(trimmed);
  }

  @override
  void dispose() {
    _sub?.cancel();
    syncService.dispose();
    super.dispose();
  }
}
