import 'dart:async';

import 'package:spectrumstrategy/src/scouting/models/scout_shift_schedule.dart';
import 'package:spectrumstrategy/src/scouting/services/scout_shift_sync_service.dart';

class FakeScoutShiftSyncService implements ScoutShiftSyncService {
  FakeScoutShiftSyncService({this.uid = 'uid-1', this.displayName = 'Lead'});

  final String uid;
  final String displayName;

  final _schedules = StreamController<ScoutShiftSchedule?>.broadcast();

  final List<ScoutShiftSchedule> pushes = <ScoutShiftSchedule>[];

  final List<String> watched = <String>[];

  Object? failNextPush;

  bool disposed = false;

  @override
  Stream<ScoutShiftSchedule?> get scheduleStream => _schedules.stream;

  @override
  String? get currentUserUid => uid;

  @override
  String? get currentUserDisplayName => displayName;

  ScoutShiftSchedule? stored;

  @override
  Future<void> watch(String eventKey) async {
    watched.add(eventKey);

    _schedules.add(stored);
  }

  @override
  Future<void> push(ScoutShiftSchedule schedule) async {
    final failure = failNextPush;
    if (failure != null) {
      failNextPush = null;
      throw failure;
    }
    pushes.add(schedule);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _schedules.close();
  }

  void emit(ScoutShiftSchedule? schedule) => _schedules.add(schedule);
}

class LaggyScoutShiftSyncService extends FakeScoutShiftSyncService {
  LaggyScoutShiftSyncService({super.uid = 'uid-1', super.displayName = 'Lead'});

  int _pushes = 0;

  @override
  Future<void> push(ScoutShiftSchedule schedule) async {
    final isFirst = _pushes++ == 0;
    if (isFirst) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return super.push(schedule);
  }
}
