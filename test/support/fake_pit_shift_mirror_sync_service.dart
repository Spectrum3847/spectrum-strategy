import 'dart:async';

import 'package:spectrumstrategy/src/scouting/models/pit_shift_mirror.dart';
import 'package:spectrumstrategy/src/scouting/services/pit_shift_mirror_sync_service.dart';

class FakePitShiftMirrorSyncService implements PitShiftMirrorSyncService {
  final _mirrors = StreamController<PitShiftMirror?>.broadcast();

  final List<String> watched = <String>[];

  PitShiftMirror? stored;

  bool disposed = false;

  @override
  Stream<PitShiftMirror?> get mirrorStream => _mirrors.stream;

  @override
  Future<void> watch(String eventKey) async {
    watched.add(eventKey);
    _mirrors.add(stored);
  }

  void emit(PitShiftMirror? mirror) => _mirrors.add(mirror);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _mirrors.close();
  }
}
