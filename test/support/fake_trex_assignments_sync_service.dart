import 'dart:async';

import 'package:spectrumstrategy/src/models/trex_assignments.dart';
import 'package:spectrumstrategy/src/services/trex_assignments_sync_service.dart';

class FakeTRexAssignmentsSyncService implements TRexAssignmentsSyncService {
  FakeTRexAssignmentsSyncService({
    this.uid = 'uid-1',
    this.displayName = 'Lead',
  });

  final String uid;
  final String displayName;

  final _assignments = StreamController<TRexAssignments>.broadcast();

  final List<TRexAssignments> pushes = <TRexAssignments>[];

  Object? failNextPush;

  bool disposed = false;
  bool initialized = false;

  @override
  Stream<TRexAssignments> get assignmentsStream => _assignments.stream;

  @override
  String? get currentUserUid => uid;

  @override
  String? get currentUserDisplayName => displayName;

  TRexAssignments stored = TRexAssignments(
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  @override
  Future<void> initialize() async {
    initialized = true;
    _assignments.add(stored);
  }

  @override
  Future<void> push(TRexAssignments assignments) async {
    final failure = failNextPush;
    if (failure != null) {
      failNextPush = null;
      throw failure;
    }
    pushes.add(assignments);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _assignments.close();
  }

  void emit(TRexAssignments assignments) => _assignments.add(assignments);
}

class LaggyTRexAssignmentsSyncService extends FakeTRexAssignmentsSyncService {
  int _pushes = 0;

  @override
  Future<void> push(TRexAssignments assignments) async {
    final isFirst = _pushes++ == 0;
    if (isFirst) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return super.push(assignments);
  }
}
